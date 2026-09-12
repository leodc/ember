import Foundation
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
    private var currentCall: Call?
    private var pendingCall: PendingCall?
    private var activeCallID: UUID?
    private var endedCallIDs = Set<UUID>()

    override init() {
        super.init()
        client.delegate = self
    }

    deinit {
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

    @discardableResult
    private func finish(callID: UUID) -> Bool {
        guard !endedCallIDs.contains(callID) else { return false }
        endedCallIDs.insert(callID)
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
        case .ACTIVE, .HELD:
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

    var errorDescription: String? {
        switch self {
        case .callAlreadyInProgress:
            "A call is already in progress."
        case .connectionLost:
            "The connection to Telnyx was lost."
        case .callDropped(let reason):
            "The call was dropped: \(reason)"
        }
    }
}
