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

    private var telnyxService: (any CallingService)?
    private let makeService: () -> any CallingService
    private let loadConfiguration: () throws -> TelnyxConfiguration
    private let requestPermission: (@escaping @Sendable (Bool) -> Void) -> Void
    private var attemptID: UUID?

    init(
        makeService: @escaping () -> any CallingService = { TelnyxCallService() },
        loadConfiguration: @escaping () throws -> TelnyxConfiguration = { try TelnyxConfiguration.load() },
        requestPermission: @escaping (@escaping @Sendable (Bool) -> Void) -> Void = {
            AVAudioApplication.requestRecordPermission(completionHandler: $0)
        }
    ) {
        self.makeService = makeService
        self.loadConfiguration = loadConfiguration
        self.requestPermission = requestPermission
        self.userLanguage = .selected
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
        guard definition.canPlaceCall, callState == .idle else { return }
        attemptID = UUID()
        callState = .preparing
        route = .active
        connectedAt = nil
        completedDuration = 0
        terminationReason = nil
        isSpeakerEnabled = false
        userLanguage = .selected

        do {
            let configuration = try loadConfiguration()
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
        guard attemptID != nil, callState != .ending else { return }
        attemptID = nil
        callState = .ending
        if let telnyxService { telnyxService.endCall() }
        else { finish(reason: nil) }
    }

    func closeCall() {
        guard callState == .completed || isFailure else { return }
        resetAfterCall()
    }

    func toggleSpeaker() {
        guard callState == .connected else { return }
        isSpeakerEnabled.toggle()
        telnyxService?.setSpeaker(enabled: isSpeakerEnabled)
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
        let attempt = attemptID
        let destination = definition.dialablePhoneNumber
        requestPermission { [weak self] granted in
            Task { @MainActor in
                guard let self, self.attemptID == attempt, self.callState == .preparing else { return }
                guard granted else {
                    self.fail(TelnyxCallControllerError.microphonePermissionDenied)
                    return
                }
                do {
                    let service = self.makeService()
                    self.telnyxService = service
                    service.delegate = self
                    try service.startCall(
                        destinationNumber: destination,
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
        releaseService()
        if let connectedAt {
            completedDuration = Date().timeIntervalSince(connectedAt)
        }
        terminationReason = reason
        callState = .completed
    }

    private func fail(_ error: Error) {
        releaseService()
        if let connectedAt {
            completedDuration = Date().timeIntervalSince(connectedAt)
        }
        callState = .failed(error.localizedDescription)
    }

    private func releaseService() {
        attemptID = nil
        telnyxService?.delegate = nil
        telnyxService = nil
    }

    private func resetAfterCall() {
        releaseService()
        callState = .idle
        connectedAt = nil
        completedDuration = 0
        terminationReason = nil
        isSpeakerEnabled = false
        route = .definition
    }
}

extension CallController: TelnyxCallServiceDelegate {
    func telnyxServiceDidStartDialing(_ service: any CallingService) {
        guard service === telnyxService, callState != .ending else { return }
        callState = .calling
    }

    func telnyxServiceDidConnect(_ service: any CallingService) {
        guard service === telnyxService, callState != .ending else { return }
        if connectedAt == nil { connectedAt = .now }
        callState = .connected
    }

    func telnyxService(_ service: any CallingService, didEndWith reason: String?) {
        guard service === telnyxService else { return }
        finish(reason: reason)
    }

    func telnyxService(_ service: any CallingService, didFailWith error: Error) {
        guard service === telnyxService else { return }
        fail(error)
    }
}

enum TelnyxCallControllerError: LocalizedError {
    case microphonePermissionDenied

    var errorDescription: String? {
        appLocalized("Microphone access is required for this test call. Enable it in Settings and try again.")
    }
}
