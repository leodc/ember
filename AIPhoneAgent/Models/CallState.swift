import Foundation

enum CallState: Equatable, Sendable {
    case idle
    case preparing
    case calling
    case connected
    case listening
    case speaking
    case waitingForUser
    case ending
    case completed
    case failed(String)

    var displayName: String {
        switch self {
        case .idle: "Ready"
        case .preparing: "Preparing"
        case .calling: "Connecting"
        case .connected: "Connected"
        case .listening: "Agent listening"
        case .speaking: "Agent speaking"
        case .waitingForUser: "Waiting for user"
        case .ending: "Ending"
        case .completed: "Ended"
        case .failed(let message): "Failed: \(message)"
        }
    }
}

