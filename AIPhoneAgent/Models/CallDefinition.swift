import Foundation

struct CallDefinition: Equatable, Sendable {
    var contactName = ""
    var phoneNumber = ""
    var objective = ""
    var agentLanguage = "Japanese"
    var availability = ""
    var additionalInstructions = ""

    var canReview: Bool {
        !phoneNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !objective.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !agentLanguage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

