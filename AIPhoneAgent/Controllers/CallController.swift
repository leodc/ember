import Foundation
import Observation

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

    func goHome() { route = .home }
    func startCall() { route = .definition }

    func reviewCall() {
        guard definition.canReview else { return }
        route = .review
    }

    func editCall() {
        route = .definition
    }

    func executeCallPlaceholder() {
        callState = .calling
        route = .active
        print("[CALL] placeholder call started")
    }

    func endPlaceholderCall() {
        callState = .idle
        route = .definition
        print("[CALL] placeholder call ended")
    }
}
