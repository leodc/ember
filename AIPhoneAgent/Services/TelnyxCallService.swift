import Foundation
import AVFoundation
import OSLog
import TelnyxRTC

@MainActor
protocol TelnyxCallServiceDelegate: AnyObject {
    func telnyxServiceDidStartDialing(_ service: TelnyxCallService)
    func telnyxServiceDidConnect(_ service: TelnyxCallService)
    func telnyxService(_ service: TelnyxCallService, didEndWith reason: String?)
    func telnyxService(_ service: TelnyxCallService, didFailWith error: Error)
}

final class TelnyxCallService: NSObject {
    weak var delegate: (any TelnyxCallServiceDelegate)?

    private let client = TxClient()
    private let audioLogger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "AIPhoneAgent",
        category: "TelnyxAudio"
    )
    private var currentCall: Call?
    private var pendingCall: PendingCall?
    private var activeCallID: UUID?
    private var endedCallIDs = Set<UUID>()
    private var isAudioSessionActive = false

    override init() {
        super.init()
        client.delegate = self
    }

    deinit {
        if isAudioSessionActive {
            client.disableAudioSession(audioSession: AVAudioSession.sharedInstance())
        }
        client.delegate = nil
        client.disconnect()
    }

    func startCall(
        destinationNumber: String,
        callerName: String,
        configuration: TelnyxConfiguration
    ) throws {
        guard currentCall == nil, pendingCall == nil else {
            throw TelnyxCallServiceError.callAlreadyInProgress
        }

        pendingCall = PendingCall(
            destinationNumber: destinationNumber,
            callerName: callerName.isEmpty ? "Ember" : callerName,
            callerNumber: configuration.callerNumber
        )

        let txConfig = TxConfig(
            sipUser: configuration.sipUser,
            password: configuration.password,
            reconnectClient: true,
            useTrickleIce: true
        )

        do {
            try client.connect(txConfig: txConfig)
        } catch {
            pendingCall = nil
            throw error
        }
    }

    func endCall() {
        pendingCall = nil
        if let currentCall {
            currentCall.hangup()
        } else {
            client.disconnect()
            notify { $0.telnyxService(self, didEndWith: nil) }
        }
    }

    func setSpeaker(enabled: Bool) {
        enabled ? client.setSpeaker() : client.setEarpiece()
    }

    private func placePendingCall() {
        guard let pendingCall else { return }
        self.pendingCall = nil
        let callID = UUID()

        do {
            let call = try client.newCall(
                callerName: pendingCall.callerName,
                callerNumber: pendingCall.callerNumber,
                destinationNumber: pendingCall.destinationNumber,
                callId: callID
            )
            currentCall = call
            activeCallID = callID
            notify { $0.telnyxServiceDidStartDialing(self) }
        } catch {
            finish(callID: callID)
            notify { $0.telnyxService(self, didFailWith: error) }
        }
    }

    private func activateAudioSession() -> Bool {
        guard !isAudioSessionActive else { return true }
        let audioSession = AVAudioSession.sharedInstance()

        // TelnyxRTC uses manual WebRTC audio. Without CallKit there is no system
        // callback to enable it, so the app must activate it once the call is live.
        client.enableAudioSession(audioSession: audioSession)
        currentCall?.unmuteAudio()
        isAudioSessionActive = client.isAudioDeviceEnabled

        let inputs = audioSession.currentRoute.inputs.map(\.portType.rawValue).joined(separator: ",")
        let outputs = audioSession.currentRoute.outputs.map(\.portType.rawValue).joined(separator: ",")
        audioLogger.info(
            "Audio activation: enabled=\(self.isAudioSessionActive, privacy: .public) category=\(audioSession.category.rawValue, privacy: .public) mode=\(audioSession.mode.rawValue, privacy: .public) inputs=\(inputs, privacy: .public) outputs=\(outputs, privacy: .public)"
        )

        return isAudioSessionActive
    }

    private func deactivateAudioSession() {
        guard isAudioSessionActive else { return }
        client.disableAudioSession(audioSession: AVAudioSession.sharedInstance())
        isAudioSessionActive = false
        audioLogger.info("Audio session deactivated")
    }

    @discardableResult
    private func finish(callID: UUID) -> Bool {
        guard !endedCallIDs.contains(callID) else { return false }
        endedCallIDs.insert(callID)
        deactivateAudioSession()
        if activeCallID == callID {
            currentCall = nil
            activeCallID = nil
        }
        client.disconnect()
        return true
    }

    private func notify(_ action: @escaping @MainActor (any TelnyxCallServiceDelegate) -> Void) {
        Task { @MainActor [weak self] in
            guard let self, let delegate = self.delegate else { return }
            action(delegate)
        }
    }
}

extension TelnyxCallService: TxClientDelegate {
    func onSocketConnected() {}

    func onSocketDisconnected() {
        guard pendingCall != nil else { return }
        pendingCall = nil
        notify { $0.telnyxService(self, didFailWith: TelnyxCallServiceError.connectionLost) }
    }

    func onClientError(error: Error) {
        pendingCall = nil
        if let activeCallID {
            guard finish(callID: activeCallID) else { return }
        } else {
            client.disconnect()
        }
        notify { $0.telnyxService(self, didFailWith: error) }
    }

    func onClientReady() {
        placePendingCall()
    }

    func onPushDisabled(success: Bool, message: String) {}
    func onSessionUpdated(sessionId: String) {}

    func onCallStateUpdated(callState: TelnyxRTC.CallState, callId: UUID) {
        guard callId == activeCallID else { return }

        switch callState {
        case .NEW, .CONNECTING, .RINGING, .RECONNECTING:
            notify { $0.telnyxServiceDidStartDialing(self) }
        case .ACTIVE:
            guard activateAudioSession() else {
                if finish(callID: callId) {
                    notify { $0.telnyxService(self, didFailWith: TelnyxCallServiceError.audioDeviceUnavailable) }
                }
                return
            }
            notify { $0.telnyxServiceDidConnect(self) }
        case .HELD:
            notify { $0.telnyxServiceDidConnect(self) }
        case .DONE(let reason):
            if finish(callID: callId) {
                notify { $0.telnyxService(self, didEndWith: reason?.displayText) }
            }
        case .DROPPED(let reason):
            if finish(callID: callId) {
                notify { $0.telnyxService(self, didFailWith: TelnyxCallServiceError.callDropped(reason.rawValue)) }
            }
        }
    }

    func onIncomingCall(call: Call) {
        call.hangup()
    }

    func onRemoteCallEnded(callId: UUID, reason: CallTerminationReason?) {
        guard callId == activeCallID, !endedCallIDs.contains(callId) else { return }
        if finish(callID: callId) {
            notify { $0.telnyxService(self, didEndWith: reason?.displayText) }
        }
    }

    func onPushCall(call: Call) {
        call.hangup()
    }
}

private struct PendingCall {
    let destinationNumber: String
    let callerName: String
    let callerNumber: String
}

private extension CallTerminationReason {
    var displayText: String? {
        if let sipReason, let sipCode { return "\(sipReason) (SIP \(sipCode))" }
        if let sipReason { return sipReason }
        return cause
    }
}

enum TelnyxCallServiceError: LocalizedError {
    case callAlreadyInProgress
    case connectionLost
    case callDropped(String)
    case audioDeviceUnavailable

    var errorDescription: String? {
        switch self {
        case .callAlreadyInProgress:
            "A call is already in progress."
        case .connectionLost:
            "The connection to Telnyx was lost."
        case .callDropped(let reason):
            "The call was dropped: \(reason)"
        case .audioDeviceUnavailable:
            "The iPhone audio session could not be activated."
        }
    }
}
