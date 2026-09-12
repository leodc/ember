import Foundation

enum AppLanguage: String, CaseIterable, Identifiable, Sendable {
    case english = "en"
    case spanish = "es"

    static let storageKey = "appLanguage"

    var id: String { rawValue }
    var locale: Locale { Locale(identifier: rawValue) }

    /// Language the Realtime agent must use whenever it addresses the app user.
    var agentInstructionName: String {
        switch self {
        case .english: "English"
        case .spanish: "Spanish"
        }
    }

    static var selected: AppLanguage {
        guard let value = UserDefaults.standard.string(forKey: storageKey) else {
            return defaultLanguage(for: Locale.preferredLanguages.first)
        }
        return AppLanguage(rawValue: value) ?? defaultLanguage(for: Locale.preferredLanguages.first)
    }

    static func defaultLanguage(for preferredLanguage: String?) -> AppLanguage {
        let languageCode = preferredLanguage?
            .lowercased()
            .split(whereSeparator: { $0 == "-" || $0 == "_" })
            .first
        return languageCode == "es" ? .spanish : .english
    }
}

struct CallDefinition: Equatable, Sendable {
    var contactName = ""
    var phoneNumber = ""
    var objective = ""
    var agentLanguage = "Japanese"
    var availability = ""
    var additionalInstructions = ""

    var canReview: Bool {
        PhoneNumberInput.isPlausible(phoneNumber)
            && !objective.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !agentLanguage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var dialablePhoneNumber: String {
        PhoneNumberInput.e164(phoneNumber)
    }

    var hasInvalidPhoneNumber: Bool {
        guard !phoneNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        return !PhoneNumberInput.isPlausible(phoneNumber)
    }
}

enum PhoneNumberInput {
    private static let japanCountryCode = "81"

    static func e164(_ input: String) -> String {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let withoutScheme = trimmed.lowercased().hasPrefix("tel:")
            ? String(trimmed.dropFirst(4)).trimmingCharacters(in: .whitespacesAndNewlines)
            : trimmed
        let hasPlus = withoutScheme.hasPrefix("+") || withoutScheme.hasPrefix("＋")
        let digits = digitsOnly(withoutScheme)

        if hasPlus {
            return "+" + removeJapaneseTrunkPrefixIfNeeded(digits)
        }
        if digits.hasPrefix("00") {
            return "+" + removeJapaneseTrunkPrefixIfNeeded(String(digits.dropFirst(2)))
        }
        if digits.hasPrefix("0") {
            return "+\(japanCountryCode)" + digits.dropFirst()
        }
        if digits.hasPrefix(japanCountryCode) {
            return "+" + digits
        }
        return digits
    }

    static func display(_ input: String) -> String {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = e164(trimmed)
        let digits = digitsOnly(normalized)
        let isInternational = trimmed.hasPrefix("+")
            || trimmed.hasPrefix("＋")
            || trimmed.hasPrefix("00")
            || (!trimmed.hasPrefix("0") && digits.hasPrefix(japanCountryCode))

        if isInternational, digits.count == 12, digits.hasPrefix("81") {
            let national = String(digits.dropFirst(2))
            return "+81 \(national.prefix(2)) \(national.dropFirst(2).prefix(4)) \(national.suffix(4))"
        }
        if !isInternational, digits.count == 11,
           ["070", "080", "090"].contains(where: digits.hasPrefix) {
            return "\(digits.prefix(3)) \(digits.dropFirst(3).prefix(4)) \(digits.suffix(4))"
        }
        return isInternational ? "+" + digits : digits
    }

    static func isPlausible(_ input: String) -> Bool {
        let value = e164(input)
        guard value.hasPrefix("+") else { return false }
        let count = digitsOnly(value).count
        return (8...15).contains(count)
    }

    private static func digitsOnly(_ input: String) -> String {
        input.compactMap(\.wholeNumberValue).map(String.init).joined()
    }

    private static func removeJapaneseTrunkPrefixIfNeeded(_ digits: String) -> String {
        guard digits.hasPrefix("810") else { return digits }
        return "81" + digits.dropFirst(3)
    }
}
