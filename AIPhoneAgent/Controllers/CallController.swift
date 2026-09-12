import Foundation
import Observation
import AVFoundation

@MainActor
@Observable
final class CallController {
    enum Route: Sendable {
        case home
        case definition
        case review
        case active
    }

    var definition = CallDefinition()
    private(set) var callState: CallState = .idle
    private(set) var route: Route = .home
    private(set) var connectedAt: Date?
    private(set) var completedDuration: TimeInterval = 0
    private(set) var terminationReason: String?
    private(set) var isSpeakerEnabled = false
    private(set) var userLanguage: AppLanguage

    private let telnyxService: TelnyxCallService

    init(telnyxService: TelnyxCallService = TelnyxCallService()) {
        self.telnyxService = telnyxService
        self.userLanguage = .selected
        telnyxService.delegate = self
    }

    func goHome() { route = .home }
    func startCall() { route = .definition }

    func reviewCall() {
        guard definition.canReview else { return }
        route = .review
    }

    func editCall() {
        route = .definition
    }

    func executeCall() {
        guard definition.canReview else { return }
        callState = .preparing
        route = .active
        connectedAt = nil
        completedDuration = 0
        terminationReason = nil
        isSpeakerEnabled = false
        userLanguage = .selected

        do {
            let configuration = try TelnyxConfiguration.load()
            requestMicrophoneAndStart(using: configuration)
        } catch {
            fail(error)
        }
    }

    func endCall() {
        guard callState != .completed else {
            resetAfterCall()
            return
        }
        callState = .ending
        telnyxService.endCall()
    }

    func closeCall() {
        resetAfterCall()
    }

    func toggleSpeaker() {
        isSpeakerEnabled.toggle()
        telnyxService.setSpeaker(enabled: isSpeakerEnabled)
    }

    func elapsedTime(at date: Date = .now) -> TimeInterval {
        if callState == .completed || isFailure {
            return completedDuration
        }
        guard let connectedAt else { return 0 }
        return max(0, date.timeIntervalSince(connectedAt))
    }

    private var isFailure: Bool {
        if case .failed = callState { return true }
        return false
    }

    private func requestMicrophoneAndStart(using configuration: TelnyxConfiguration) {
        AVAudioApplication.requestRecordPermission { [weak self] granted in
            Task { @MainActor in
                guard let self else { return }
                guard granted else {
                    self.fail(TelnyxCallControllerError.microphonePermissionDenied)
                    return
                }
                do {
                    try self.telnyxService.startCall(
                        destinationNumber: self.definition.dialablePhoneNumber,
                        callerName: "Ember",
                        configuration: configuration
                    )
                } catch {
                    self.fail(error)
                }
            }
        }
    }

    private func finish(reason: String?) {
        if let connectedAt {
            completedDuration = Date().timeIntervalSince(connectedAt)
        }
        terminationReason = reason
        callState = .completed
    }

    private func fail(_ error: Error) {
        if let connectedAt {
            completedDuration = Date().timeIntervalSince(connectedAt)
        }
        callState = .failed(error.localizedDescription)
    }

    private func resetAfterCall() {
        callState = .idle
        connectedAt = nil
        completedDuration = 0
        terminationReason = nil
        isSpeakerEnabled = false
        route = .definition
    }
}

extension CallController: TelnyxCallServiceDelegate {
    func telnyxServiceDidStartDialing(_ service: TelnyxCallService) {
        callState = .calling
    }

    func telnyxServiceDidConnect(_ service: TelnyxCallService) {
        if connectedAt == nil { connectedAt = .now }
        callState = .connected
    }

    func telnyxService(_ service: TelnyxCallService, didEndWith reason: String?) {
        finish(reason: reason)
    }

    func telnyxService(_ service: TelnyxCallService, didFailWith error: Error) {
        fail(error)
    }
}

enum TelnyxCallControllerError: LocalizedError {
    case microphonePermissionDenied

    var errorDescription: String? {
        "Microphone access is required for this test call. Enable it in Settings and try again."
    }
}
