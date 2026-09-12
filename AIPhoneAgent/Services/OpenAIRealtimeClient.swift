import Foundation
import AVFoundation
import WebRTC
import OSLog

@MainActor
protocol RealtimeServicing: AnyObject {
    var onEvent: ((RealtimeEvent) -> Void)? { get set }
    func start(definition: CallDefinition, language: AppLanguage, configuration: RealtimeConfiguration) async throws
    func stop()
}

enum RealtimeEvent {
    case ready, listening, thinking, speaking, ending, endedByAgent
    case transcript(id: String, text: String, final: Bool)
    case failed(RealtimeError)
}

/// Owns only the independent OpenAI peer. Never creates a Telnyx client or call.
@MainActor
final class OpenAIRealtimeClient: NSObject, RealtimeServicing {
    var onEvent: ((RealtimeEvent) -> Void)?
    private var factory: RTCPeerConnectionFactory?
    private var peer: RTCPeerConnection?
    private var channel: RTCDataChannel?
    private var microphone: RTCAudioTrack?
    private var diagnosticsTask: Task<Void, Never>?
    private var outputPlaying = false
    private var closing = false
    private var farewell = RealtimeFarewellProgress()
    private var audioTailTask: Task<Void, Never>?
    private var farewellTimeoutTask: Task<Void, Never>?
    private var agentLanguage = ""

    private var observers: [NSObjectProtocol] = []
    private var previousWebRTCConfiguration: RTCAudioSessionConfiguration?
    private var ownsAudio = false
    private var previousManualAudio = false
    private var previousAudioEnabled = false
    private let logger = Logger(subsystem: "Ember", category: "OpenAI")

    func start(definition: CallDefinition, language: AppLanguage, configuration: RealtimeConfiguration) async throws {
        agentLanguage = definition.agentLanguage
        try configureAudio()
        try await negotiate(definition: definition, language: language, configuration: configuration)
    }

    private func configureAudio() throws {
        let audio = RTCAudioSession.sharedInstance()
        audio.lockForConfiguration()
        defer { audio.unlockForConfiguration() }
        previousManualAudio = audio.useManualAudio
        previousAudioEnabled = audio.isAudioEnabled
        ownsAudio = true
        previousWebRTCConfiguration = RTCAudioSessionConfiguration.webRTC()
        let voiceConfiguration = RTCAudioSessionConfiguration()
        voiceConfiguration.category = AVAudioSession.Category.playAndRecord.rawValue
        voiceConfiguration.mode = AVAudioSession.Mode.voiceChat.rawValue
        voiceConfiguration.categoryOptions = [.defaultToSpeaker, .allowBluetoothHFP]
        RTCAudioSessionConfiguration.setWebRTC(voiceConfiguration)
        audio.useManualAudio = true
        audio.isAudioEnabled = false
        try audio.setCategory(AVAudioSession.Category.playAndRecord,
                              with: [.defaultToSpeaker, .allowBluetoothHFP])
        try audio.setMode(AVAudioSession.Mode.voiceChat)
        try audio.setActive(true)
        audio.isAudioEnabled = true
    }

    private func negotiate(definition: CallDefinition, language: AppLanguage, configuration: RealtimeConfiguration) async throws {
        let factory = RTCPeerConnectionFactory()
        self.factory = factory
        let config = RTCConfiguration()
        config.sdpSemantics = .unifiedPlan
        let constraints = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)
        guard let peer = factory.peerConnection(with: config, constraints: constraints, delegate: self) else {
            throw RealtimeError.connection
        }
        self.peer = peer
        let track = factory.audioTrack(with: factory.audioSource(with: constraints), trackId: "ember-microphone")
        track.isEnabled = false // Do not transmit before the configured session is ready.
        microphone = track
        peer.add(track, streamIds: ["ember-realtime"])
        guard let channel = peer.dataChannel(forLabel: "oai-events", configuration: RTCDataChannelConfiguration()) else {
            throw RealtimeError.connection
        }
        self.channel = channel
        channel.delegate = self
        observeAudioChanges()
        let offer: RTCSessionDescription = try await withCheckedThrowingContinuation { continuation in
            peer.offer(for: constraints) { sdp, error in
                if let error { continuation.resume(throwing: error) }
                else if let sdp { continuation.resume(returning: sdp) }
                else { continuation.resume(throwing: RealtimeError.connection) }
            }
        }
        try Task.checkCancellation()
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            peer.setLocalDescription(offer) { error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume() }
            }
        }
        // Include gathered candidates in the single SDP exchange (no trickle endpoint).
        let deadline = Date().addingTimeInterval(10)
        while peer.iceGatheringState != .complete {
            guard Date() < deadline else { throw RealtimeError.timeout }
            try await Task.sleep(for: .milliseconds(50))
        }
        try Task.checkCancellation()
        guard self.peer === peer, let sdp = peer.localDescription?.sdp else { throw CancellationError() }
        let boundary = "Ember-\(UUID().uuidString)"
        let session = try JSONSerialization.data(withJSONObject: RealtimeSessionContext.session(
            for: definition, userLanguage: language, model: configuration.model))
        var body = Data()
        for (name, value) in [("sdp", Data(sdp.utf8)), ("session", session)] {
            body.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\n\r\n".utf8))
            body.append(value)
            body.append(Data("\r\n".utf8))
        }
        body.append(Data("--\(boundary)--\r\n".utf8))
        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/realtime/calls")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 25
        request.setValue("Bearer \(configuration.apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        let (data, response) = try await URLSession.shared.data(for: request)
        try Task.checkCancellation()
        guard self.peer === peer else { throw CancellationError() }
        guard let http = response as? HTTPURLResponse else { throw RealtimeError.connection }
        guard (200..<300).contains(http.statusCode) else { throw RealtimeError.service(http.statusCode) }
        guard let answer = String(data: data, encoding: .utf8), answer.hasPrefix("v=0") else {
            throw RealtimeError.connection
        }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            peer.setRemoteDescription(RTCSessionDescription(type: .answer, sdp: answer)) { error in
                if let error { continuation.resume(throwing: error) }
                else { continuation.resume() }
            }
        }
    }

    func stop() {
        audioTailTask?.cancel()
        audioTailTask = nil
        farewellTimeoutTask?.cancel()
        farewellTimeoutTask = nil
        closing = false
        farewell = RealtimeFarewellProgress()
        diagnosticsTask?.cancel()
        diagnosticsTask = nil
        outputPlaying = false
        observers.forEach(NotificationCenter.default.removeObserver)
        observers.removeAll()
        microphone?.isEnabled = false
        channel?.delegate = nil
        channel?.close()
        channel = nil
        peer?.delegate = nil
        peer?.close()
        peer = nil
        microphone = nil
        factory = nil
        if ownsAudio {
            let audio = RTCAudioSession.sharedInstance()
            audio.lockForConfiguration()
            audio.isAudioEnabled = false
            try? audio.setActive(false)
            audio.useManualAudio = previousManualAudio
            audio.isAudioEnabled = previousAudioEnabled
            audio.unlockForConfiguration()
            if let previousWebRTCConfiguration {
                RTCAudioSessionConfiguration.setWebRTC(previousWebRTCConfiguration)
            }
            previousWebRTCConfiguration = nil
            ownsAudio = false
        }
        logger.info("Session closed")
    }

    /// Cumulative counters, sampled every five seconds. No SDP, IP addresses or audio content.
    private func startDiagnostics() {
        diagnosticsTask?.cancel()
        diagnosticsTask = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(5)) } catch { return }
                guard let peer = self?.peer else { return }
                let report = await peer.statistics()
                guard let self, self.peer === peer, !Task.isCancelled else { return }
                for stat in report.statistics.values where stat.type == "inbound-rtp" {
                    guard (stat.values["kind"] as? String ?? stat.values["mediaType"] as? String) == "audio" else { continue }
                    // Missing metrics remain absent, rather than being reported as zero.
                    let keys = ["packetsReceived", "packetsLost", "jitter", "concealedSamples",
                                "totalSamplesReceived", "jitterBufferDelay", "jitterBufferEmittedCount"]
                    let counters = keys.compactMap { key -> String? in
                        guard let value = stat.values[key] as? NSNumber else { return nil }
                        return "\(key)=\(value)"
                    }.joined(separator: " ")
                    self.logger.info("Audio receive counters: \(counters, privacy: .public)")
                }
            }
        }
    }

    private func observeAudioChanges() {
        for name in [AVAudioSession.interruptionNotification, AVAudioSession.mediaServicesWereResetNotification,
                     AVAudioSession.routeChangeNotification] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                if note.name == AVAudioSession.routeChangeNotification {
                    let reason = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt
                    guard reason == AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue else { return }
                }
                Task { @MainActor [weak self] in self?.onEvent?(.failed(.audio)) }
            })
        }
    }

    private func send(_ event: [String: Any]) throws {
        guard let channel, channel.readyState == .open,
              let data = try? JSONSerialization.data(withJSONObject: event),
              channel.sendData(RTCDataBuffer(data: data, isBinary: false)) else {
            throw RealtimeError.connection
        }
    }

    private func beginFarewell(callID: String) {
        guard !closing else { return }
        closing = true
        microphone?.isEnabled = false
        onEvent?(.ending)
        logger.info("Agent requested session end; preparing final goodbye")
        do {
            // Prevent noise or new VAD turns from cancelling the final goodbye.
            try send(["type": "session.update", "session": ["type": "realtime",
                "audio": ["input": ["turn_detection": NSNull()]]]])
            try send(["type": "conversation.item.create", "item": [
                "type": "function_call_output", "call_id": callID,
                "output": "{\"status\":\"closing_after_goodbye\"}"]])
            try send(["type": "response.create", "response": [
                "metadata": ["ember_final_goodbye": "true"],
                "output_modalities": ["audio"], "tool_choice": "none",
                "instructions": "Say only a brief natural thank-you and goodbye in \(agentLanguage). Do not ask questions, add facts, or claim the appointment is confirmed. The outcome was already summarized. The session will disconnect after your goodbye."]])
            farewellTimeoutTask = Task { [weak self] in
                do { try await Task.sleep(for: .seconds(30)) } catch { return }
                guard let self, self.closing else { return }
                self.onEvent?(.failed(.farewellTimeout))
            }
        } catch {
            onEvent?(.failed(.connection))
        }
    }

    private func completeFarewellIfReady() {
        guard closing, farewell.isComplete, audioTailTask == nil else { return }
        farewellTimeoutTask?.cancel()
        // The server buffer is drained, but media can still be in the client's jitter buffer.
        // Leave a short playback tail; validate this margin on the physical audio route.
        audioTailTask = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(750)) } catch { return }
            guard let self, self.closing, self.farewell.isComplete else { return }
            self.logger.info("Goodbye output drained; emitting agent session completion")
            // Future bridge coordinator can hang up Telnyx on this explicit event.
            self.onEvent?(.endedByAgent)
        }
    }

    private func receive(_ data: Data) {
        guard let event = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = event["type"] as? String else { return }
        switch type {
        case "session.created":
            logger.info("Session ready; VAD threshold=0.7, silence=650ms, noise=far_field")
            startDiagnostics()
            microphone?.isEnabled = true
            onEvent?(.ready)
        case "input_audio_buffer.speech_started":
            logger.info("Input speech started; output playing=\(self.outputPlaying)")
            onEvent?(.listening)
        case "input_audio_buffer.speech_stopped":
            logger.info("Input speech stopped")
            onEvent?(.thinking)
        case "output_audio_buffer.started":
            outputPlaying = true
            logger.info("Output playback started")
            onEvent?(.speaking)
        case "output_audio_buffer.stopped", "output_audio_buffer.cleared":
            outputPlaying = false
            logger.info("Output playback event: \(type, privacy: .public)")
            if closing, type == "output_audio_buffer.stopped", let id = event["response_id"] as? String {
                farewell.playbackStopped(id: id)
                completeFarewellIfReady()
            }
            if !closing { onEvent?(.listening) }
        case "response.output_audio_transcript.delta", "response.output_audio_transcript.done":
            if let id = event["item_id"] as? String {
                let final = type.hasSuffix(".done")
                let text = event[final ? "transcript" : "delta"] as? String ?? ""
                onEvent?(.transcript(id: id, text: text, final: final))
            }
        case "error":
            logger.error("Realtime API rejected an event") // Never log payloads, SDP, keys or personal context.
            onEvent?(.failed(.rejected))
        case "response.created":
            logger.info("Response created")
            if closing, let response = event["response"] as? [String: Any],
               let metadata = response["metadata"] as? [String: String],
               metadata["ember_final_goodbye"] == "true" {
                farewell.responseID = response["id"] as? String
            }
        case "response.done":
            if let response = event["response"] as? [String: Any], let status = response["status"] as? String {
                // Log only known protocol values, never arbitrary server text.
                if ["completed", "cancelled", "failed", "incomplete"].contains(status) {
                    logger.info("Response done: \(status, privacy: .public)")
                }
            }
            if let response = event["response"] as? [String: Any],
               let status = response["status"] as? String,
               let id = response["id"] as? String {
                if closing, id == farewell.responseID {
                    guard status == "completed" else {
                        onEvent?(.failed(.rejected))
                        return
                    }
                    farewell.generationCompleted(id: id)
                    completeFarewellIfReady()
                    return
                }
                if !closing, status == "completed", let output = response["output"] as? [[String: Any]],
                   let call = output.first(where: { $0["type"] as? String == "function_call" && $0["name"] as? String == "end_session" }),
                   let callID = call["call_id"] as? String {
                    if let arguments = call["arguments"] as? String,
                       let reason = RealtimeEndReason.parse(arguments: arguments) {
                        logger.info("End requested: \(reason.rawValue, privacy: .public)")
                        beginFarewell(callID: callID)
                    } else {
                        // Invalid tool arguments must not silently hang up or leave a tool unanswered.
                        do {
                            try send(["type": "conversation.item.create", "item": [
                                "type": "function_call_output", "call_id": callID,
                                "output": "{\"status\":\"not_closed\",\"message\":\"A valid closing reason is required. Missing information alone is not a closing reason. Continue addressing the recipient's pending question.\"}"]])
                            try send(["type": "response.create", "response": ["tool_choice": "none"]])
                        } catch { onEvent?(.failed(.connection)) }
                    }
                    return
                }
            }
            if let response = event["response"] as? [String: Any],
               let status = response["status"] as? String, ["failed", "incomplete"].contains(status) {
                onEvent?(.failed(.rejected))
            }
        default: break
        }
    }
}

extension OpenAIRealtimeClient: RTCPeerConnectionDelegate, RTCDataChannelDelegate {
    nonisolated func dataChannelDidChangeState(_ dataChannel: RTCDataChannel) {
        Task { @MainActor [weak self] in
            guard let self, self.channel === dataChannel else { return }
            if dataChannel.readyState == .closed { self.onEvent?(.failed(.connection)) }
        }
    }
    nonisolated func dataChannel(_ dataChannel: RTCDataChannel, didReceiveMessageWith buffer: RTCDataBuffer) {
        let data = buffer.data
        Task { @MainActor [weak self] in
            guard let self, self.channel === dataChannel else { return }
            self.receive(data)
        }
    }
    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceConnectionState) {
        Task { @MainActor [weak self] in
            guard let self, self.peer === peerConnection else { return }
            if [.failed, .disconnected, .closed].contains(newState) { self.onEvent?(.failed(.connection)) }
        }
    }
    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didChange stateChanged: RTCSignalingState) {}
    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didAdd stream: RTCMediaStream) {}
    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didRemove stream: RTCMediaStream) {}
    nonisolated func peerConnectionShouldNegotiate(_ peerConnection: RTCPeerConnection) {}
    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceGatheringState) {}
    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didGenerate candidate: RTCIceCandidate) {}
    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didRemove candidates: [RTCIceCandidate]) {}
    nonisolated func peerConnection(_ peerConnection: RTCPeerConnection, didOpen dataChannel: RTCDataChannel) {}
}
