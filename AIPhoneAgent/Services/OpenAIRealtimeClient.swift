import Foundation
import AVFoundation
import WebRTC
import OSLog

@MainActor
protocol RealtimeServicing: AnyObject {
    var onEvent: ((RealtimeEvent) -> Void)? { get set }
    func start(definition: CallDefinition, language: AppLanguage, configuration: RealtimeConfiguration) async throws
    func stop()
    func submitAnswer(requestID: UUID, answer: String) throws
    func submitInstruction(id: UUID, text: String) throws
}

enum TranscriptSpeaker: Equatable { case agent, recipient, userInstruction }

enum RealtimeEvent {
    case ready, listening, thinking, speaking, ending, endedByAgent
    case askUser(AskUserRequest)
    case questionSuperseded
    case instructionSubmitted(id: UUID, text: String)
    case answerSubmitted
    case transcript(id: String, text: String, final: Bool, speaker: TranscriptSpeaker = .agent)
    case transcriptUnavailable(id: String)
    case failed(RealtimeError)
}

/// Owns only the independent OpenAI peer. Never creates a Telnyx client or call.
@MainActor
final class OpenAIRealtimeClient: NSObject, RealtimeServicing {
    var onEvent: ((RealtimeEvent) -> Void)?
    // Allows protocol-level regression tests without opening a microphone or network connection.
    private let sendEvent: (([String: Any]) throws -> Void)?
    private var stopped = false

    init(sendEvent: (([String: Any]) throws -> Void)? = nil) {
        self.sendEvent = sendEvent
        super.init()
    }

    private var factory: RTCPeerConnectionFactory?
    private var peer: RTCPeerConnection?
    private var channel: RTCDataChannel?
    private var microphone: RTCAudioTrack?
    private var diagnosticsTask: Task<Void, Never>?
    private var outputPlaying = false
    private var pendingQuestion: AskUserRequest?
    private var handledCalls: Set<String> = []
    private var completedResponses: Set<String> = []
    private var inputSpeechActive = false
    private var responseActive = false
    private var queuedAnswer: String?
    private var activeResponseID: String?
    private var pendingInstruction: (id: UUID, text: String)?
    private var instructionCancelEventID: String?
    private var cancellationRequests: [String: String] = [:]
    private var interruptedResponses: Set<String> = []
    private var instructionTimeoutTask: Task<Void, Never>?
    private var acceptedInstructionIDs: Set<UUID> = []
    private var hasUserInstruction = false
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
        stopped = false
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
        stopped = true
        pendingInstruction = nil
        activeResponseID = nil
        instructionCancelEventID = nil
        instructionTimeoutTask?.cancel()
        instructionTimeoutTask = nil
        hasUserInstruction = false
        acceptedInstructionIDs = []
        cancellationRequests = [:]
        interruptedResponses = []
        pendingQuestion = nil
        queuedAnswer = nil
        handledCalls = []
        completedResponses = []
        inputSpeechActive = false
        responseActive = false
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
        guard !stopped else { throw RealtimeError.connection }
        if let sendEvent { try sendEvent(event); return }
        guard let channel, channel.readyState == .open,
              let data = try? JSONSerialization.data(withJSONObject: event),
              channel.sendData(RTCDataBuffer(data: data, isBinary: false)) else {
            throw RealtimeError.connection
        }
    }

    func submitAnswer(requestID: UUID, answer: String) throws {
        guard !closing, let request = pendingQuestion, request.id == requestID,
              queuedAnswer == nil, !answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        queuedAnswer = answer
        try flushAnswer()
    }

    func submitInstruction(id: UUID, text: String) throws {
        guard !stopped, pendingInstruction == nil,
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              acceptedInstructionIDs.insert(id).inserted else { return }
        pendingInstruction = (id, text)
        // A user can still change course during the goodbye, until the session is released.
        if closing {
            closing = false
            audioTailTask?.cancel()
            audioTailTask = nil
            farewellTimeoutTask?.cancel()
            farewellTimeoutTask = nil
            farewell = RealtimeFarewellProgress()
            microphone?.isEnabled = true
        }
        instructionTimeoutTask = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(30)) } catch { return }
            guard let self, self.pendingInstruction?.id == id else { return }
            self.onEvent?(.failed(.instructionTimeout))
        }
        // Keep receiving audio, but prevent VAD from racing the replacement response.
        try setAutomaticTurns(enabled: false)
        try interruptForInstruction()
        try flushInstruction()
    }

    private func setAutomaticTurns(enabled: Bool) throws {
        try send(["type": "session.update", "session": ["type": "realtime",
            "audio": ["input": ["turn_detection": ["type": "server_vad",
                "threshold": 0.7, "prefix_padding_ms": 300, "silence_duration_ms": 650,
                "create_response": enabled, "interrupt_response": enabled]]]]])
    }

    private func interruptForInstruction() throws {
        guard pendingInstruction != nil else { return }
        if let activeResponseID, instructionCancelEventID == nil {
            let eventID = UUID().uuidString
            instructionCancelEventID = eventID
            cancellationRequests[eventID] = activeResponseID
            interruptedResponses.insert(activeResponseID)
            try send(["type": "response.cancel", "response_id": activeResponseID, "event_id": eventID])
        }
        if outputPlaying || responseActive {
            try send(["type": "output_audio_buffer.clear"])
        }
    }

    private func flushInstruction() throws {
        guard !stopped, !responseActive, let instruction = pendingInstruction else { return }
        if let question = pendingQuestion {
            try toolOutput(callID: question.callID, payload: ["status": "superseded_by_instruction",
                "message": "No answer supplied. Reevaluate this question using the new app-user instruction and ask again if still needed."])
            pendingQuestion = nil
            queuedAnswer = nil
            onEvent?(.questionSuperseded)
        }
        let encoded = try JSONSerialization.data(withJSONObject: ["instruction": instruction.text])
        try send(["type": "conversation.item.create", "item": ["type": "message", "role": "system",
            "content": [["type": "input_text", "text": "APP_USER_INSTRUCTION\n" + String(decoding: encoded, as: UTF8.self)]]]])
        try send(["type": "response.create"])
        responseActive = true
        hasUserInstruction = true
        pendingInstruction = nil
        instructionCancelEventID = nil
        instructionTimeoutTask?.cancel()
        instructionTimeoutTask = nil
        try setAutomaticTurns(enabled: true)
        onEvent?(.instructionSubmitted(id: instruction.id, text: instruction.text))
        logger.info("App-user instruction sent")
    }

    private func supersedeTools(in response: [String: Any]) throws {
        for call in response["output"] as? [[String: Any]] ?? [] where call["type"] as? String == "function_call" {
            if let callID = call["call_id"] as? String, handledCalls.insert(callID).inserted {
                try toolOutput(callID: callID, payload: ["status": "superseded_by_instruction",
                    "message": "The app user interrupted this turn. Reevaluate using the new instruction before taking action."])
            }
        }
    }

    private func toolOutput(callID: String, payload: [String: String]) throws {
        let data = try JSONSerialization.data(withJSONObject: payload)
        try send(["type": "conversation.item.create", "item": [
            "type": "function_call_output", "call_id": callID,
            "output": String(decoding: data, as: UTF8.self)]])
    }

    private func flushAnswer() throws {
        guard pendingInstruction == nil, !closing, !responseActive, !inputSpeechActive, let question = pendingQuestion,
              let answer = queuedAnswer else { return }
        try toolOutput(callID: question.callID, payload: ["status": "answered", "answer": answer])
        pendingQuestion = nil
        queuedAnswer = nil
        onEvent?(.answerSubmitted)
        logger.info("User response submitted")
        try send(["type": "response.create"])
        responseActive = true
    }

    private func handleTools(_ calls: [[String: Any]]) throws {
        var rejected = false
        var closingCallID: String?
        var closingReason: RealtimeEndReason?
        // Process questions before closure even if the model emits both in one response.
        let functions = calls.filter { $0["type"] as? String == "function_call" }
        let ordered = functions.filter { $0["name"] as? String != "end_session" }
            + functions.filter { $0["name"] as? String == "end_session" }
        for call in ordered {
            guard let callID = call["call_id"] as? String,
                  handledCalls.insert(callID).inserted else { continue }
            let arguments = call["arguments"] as? String ?? ""
            switch call["name"] as? String {
            case "ask_user":
                if pendingQuestion == nil, let request = AskUserRequest.parse(callID: callID, arguments: arguments) {
                    pendingQuestion = request
                    logger.info("ask_user requested")
                    onEvent?(.askUser(request))
                } else {
                    try toolOutput(callID: callID, payload: ["status": "rejected", "message": "Invalid arguments or another question is pending. Do not assume an answer. Use question and suggestedAnswers in the app language."])
                    rejected = true
                }
            case "end_session":
                if closingCallID == nil, let reason = RealtimeEndReason.parse(arguments: arguments),
                   (reason != .userRequestedEnd || hasUserInstruction),
                   pendingQuestion == nil || reason == .recipientRequestedEnd || reason == .userRequestedEnd {
                    if let pendingQuestion {
                        try toolOutput(callID: pendingQuestion.callID, payload: ["status": "cancelled", "message": "Session ending; no user answer was supplied."])
                    }
                    pendingQuestion = nil
                    queuedAnswer = nil
                    closingCallID = callID
                    closingReason = reason
                    continue
                }
                try toolOutput(callID: callID, payload: ["status": "not_closed", "message": "A valid closing reason is required. While ask_user is pending only an explicit recipient or app-user request to end permits closing. Missing information is not permission to close."])
                rejected = true
            default:
                try toolOutput(callID: callID, payload: ["status": "rejected", "message": "Unknown tool."])
                rejected = true
            }
        }
        if let closingCallID, let closingReason {
            beginFarewell(callID: closingCallID, reason: closingReason)
            return
        }
        if rejected && pendingQuestion == nil {
            try send(["type": "response.create", "response": ["tool_choice": "none"]])
            responseActive = true
        }
    }

    private func beginFarewell(callID: String, reason: RealtimeEndReason) {
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
            responseActive = true
            try send(["type": "response.create", "response": [
                "metadata": ["ember_final_goodbye": "true"],
                "output_modalities": ["audio"], "tool_choice": "none",
                "instructions": RealtimeSessionContext.farewellInstructions(reason: reason, language: agentLanguage)]])
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

    func receive(_ data: Data) {
        guard !stopped else { return }
        guard let event = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = event["type"] as? String else { return }
        switch type {
        case "session.created":
            logger.info("Session ready; VAD threshold=0.7, silence=650ms, noise=far_field")
            startDiagnostics()
            microphone?.isEnabled = true
            onEvent?(.ready)
        case "input_audio_buffer.speech_started":
            inputSpeechActive = true
            if let id = event["item_id"] as? String {
                onEvent?(.transcript(id: id, text: "", final: false, speaker: .recipient))
            }
            logger.info("Input speech started; output playing=\(self.outputPlaying)")
            onEvent?(.listening)
        case "input_audio_buffer.speech_stopped":
            inputSpeechActive = false
            // Automatic VAD generation follows; do not race it with a user result.
            if !closing && pendingInstruction == nil { responseActive = true }
            logger.info("Input speech stopped")
            onEvent?(.thinking)
        case "output_audio_buffer.started":
            outputPlaying = true
            logger.info("Output playback started")
            if pendingInstruction != nil {
                do { try interruptForInstruction() } catch { onEvent?(.failed(.connection)) }
            } else { onEvent?(.speaking) }
        case "output_audio_buffer.stopped", "output_audio_buffer.cleared":
            outputPlaying = false
            logger.info("Output playback event: \(type, privacy: .public)")
            if closing, type == "output_audio_buffer.stopped", let id = event["response_id"] as? String {
                farewell.playbackStopped(id: id)
                completeFarewellIfReady()
            }
            if !closing { onEvent?(.listening) }
        case "input_audio_buffer.committed":
            // Reserve the turn before the agent answers; transcription can arrive later.
            if let id = event["item_id"] as? String {
                onEvent?(.transcript(id: id, text: "", final: false, speaker: .recipient))
            }
        case "conversation.item.input_audio_transcription.delta", "conversation.item.input_audio_transcription.completed":
            if let id = event["item_id"] as? String {
                let final = type.hasSuffix(".completed")
                let text = event[final ? "transcript" : "delta"] as? String ?? ""
                onEvent?(.transcript(id: id, text: text, final: final, speaker: .recipient))
            }
        case "conversation.item.input_audio_transcription.failed":
            // Transcription is auxiliary; a failed text turn must not end the voice session.
            if let id = event["item_id"] as? String { onEvent?(.transcriptUnavailable(id: id)) }
        case "response.output_audio_transcript.delta", "response.output_audio_transcript.done":
            if let id = event["item_id"] as? String {
                let final = type.hasSuffix(".done")
                let text = event[final ? "transcript" : "delta"] as? String ?? ""
                onEvent?(.transcript(id: id, text: text, final: final))
            }
        case "error":
            if let error = event["error"] as? [String: Any],
               let eventID = error["event_id"] as? String,
               error["code"] as? String == "response_cancel_not_active",
               cancellationRequests.removeValue(forKey: eventID) != nil {
                // A late acknowledgement of our cancellation must not fail the replacement.
                if instructionCancelEventID == eventID {
                    responseActive = false
                    activeResponseID = nil
                    instructionCancelEventID = nil
                    do { try flushInstruction() } catch { onEvent?(.failed(.connection)) }
                }
                return
            }
            logger.error("Realtime API rejected an event") // Never log payloads, SDP, keys or personal context.
            onEvent?(.failed(.rejected))
        case "response.created":
            responseActive = true
            activeResponseID = (event["response"] as? [String: Any])?["id"] as? String
            if pendingInstruction != nil {
                do { try interruptForInstruction() } catch { onEvent?(.failed(.connection)) }
            }
            logger.info("Response created")
            if closing, let response = event["response"] as? [String: Any],
               let metadata = response["metadata"] as? [String: String],
               metadata["ember_final_goodbye"] == "true" {
                farewell.responseID = response["id"] as? String
            }
        case "response.done":
            if let response = event["response"] as? [String: Any], let id = response["id"] as? String {
                guard completedResponses.insert(id).inserted else { return }
                if interruptedResponses.remove(id) != nil && pendingInstruction == nil {
                    // Cancellation's completion may arrive after the replacement has begun.
                    do { try supersedeTools(in: response) } catch { onEvent?(.failed(.connection)) }
                    return
                }
            }
            responseActive = false
            activeResponseID = nil
            if pendingInstruction != nil, let response = event["response"] as? [String: Any] {
                do {
                    try supersedeTools(in: response)
                    instructionCancelEventID = nil
                    try flushInstruction()
                } catch { onEvent?(.failed(.connection)) }
                return
            }
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
                if !closing {
                    do {
                        if status == "completed", let output = response["output"] as? [[String: Any]] {
                            try handleTools(output)
                        }
                        if status == "completed" || status == "cancelled" { try flushAnswer() }
                    } catch { onEvent?(.failed(.connection)) }
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
