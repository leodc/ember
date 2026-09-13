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
        #if DEBUG
        // Keep fixture errors and prompts in the gallery language without changing saved settings.
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("--visual-review") {
            if let index = arguments.firstIndex(of: "--review-language"), arguments.indices.contains(index + 1) {
                return AppLanguage(rawValue: arguments[index + 1]) ?? .spanish
            }
            return .spanish
        }
        #endif
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
    /// Snapshot of the editable profile for this session.
    var userIdentity = UserIdentity()
    var contactName = ""
    var phoneNumber = ""
    var objective = ""
    var agentLanguage = "Japanese"
    var availability = ""
    var additionalInstructions = ""

    var canReview: Bool {
        !objective.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !agentLanguage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Rehearsal needs an objective and language; dialing additionally needs a valid destination.
    var canPlaceCall: Bool { canReview && PhoneNumberInput.isPlausible(phoneNumber) }

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
        let raw = trimmed.lowercased().hasPrefix("tel:")
            ? String(trimmed.dropFirst(4)).trimmingCharacters(in: .whitespacesAndNewlines) : trimmed
        let isInternational = raw.hasPrefix("+") || raw.hasPrefix("＋")
            || raw.hasPrefix("00") || raw.hasPrefix(japanCountryCode)
        let digits = digitsOnly(isInternational ? e164(raw) : raw)

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
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let raw = trimmed.lowercased().hasPrefix("tel:") ? String(trimmed.dropFirst(4)) : trimmed
        let allowed = CharacterSet(charactersIn: "0123456789０１２３４５６７８９+＋()- .").union(.whitespaces)
        let plusCount = raw.filter { $0 == "+" || $0 == "＋" }.count
        let startsWithPlus = raw.trimmingCharacters(in: .whitespaces).hasPrefix("+")
            || raw.trimmingCharacters(in: .whitespaces).hasPrefix("＋")
        guard raw.unicodeScalars.allSatisfy(allowed.contains),
              plusCount == 0 || (plusCount == 1 && startsWithPlus) else { return false }
        let value = e164(input)
        guard value.hasPrefix("+"), value.dropFirst().first != "0" else { return false }
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

func appLocalized(_ key: String.LocalizationValue) -> String {
    let language = AppLanguage.selected
    let bundle = Bundle.main.path(forResource: language.rawValue, ofType: "lproj")
        .flatMap { Bundle(path: $0) } ?? .main
    return String(localized: key, bundle: bundle, locale: language.locale)
}


struct UserIdentity: Codable, Equatable, Sendable {
    var givenName = ""
    var familyName = ""
    var preferredName = ""
    var age = ""
    var languages = ""
    var occupation = ""
    var nationality = ""
    var address = ""
    var sex = ""

    static let storageKey = "userIdentity.v1"
    static let initial = UserIdentity(
        givenName: "Leonel David", familyName: "Castañeda Mendoza", preferredName: "Leo",
        age: "36", languages: "Inglés y español", occupation: "Programador",
        nationality: "Mexicano",
        address: "240-0026, Kanagawa, Yokohama, Hodogaya, Gontazaka 2-11-0, Japón",
        sex: "Hombre"
    )

    static func load(from defaults: UserDefaults = .standard) -> Self {
        guard let data = defaults.data(forKey: storageKey) else { return .initial }
        // Migrate existing profiles without losing edits or restoring intentionally cleared fields.
        guard var fields = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return Self() }
        if fields["sex"] == nil { fields["sex"] = initial.sex }
        guard let migrated = try? JSONSerialization.data(withJSONObject: fields) else { return Self() }
        return (try? JSONDecoder().decode(Self.self, from: migrated)) ?? Self()
    }

    func save(to defaults: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(self) { defaults.set(data, forKey: Self.storageKey) }
    }

    var agentContext: String {
        let fields = [("Given name", givenName), ("Family name", familyName),
                      ("Preferred name", preferredName), ("Age in years (manually maintained)", age),
                      ("Languages the user speaks", languages), ("Occupation", occupation),
                      ("Nationality", nationality), ("Address", address), ("Sex", sex)]
        // JSON keeps arbitrary field values distinct from the instruction text.
        let values = Dictionary(uniqueKeysWithValues: fields.map {
            ($0.0, $0.1.trimmingCharacters(in: .whitespacesAndNewlines))
        })
        guard let data = try? JSONSerialization.data(withJSONObject: values, options: [.sortedKeys]),
              let text = String(data: data, encoding: .utf8) else { return "{}" }
        return text
    }
}
