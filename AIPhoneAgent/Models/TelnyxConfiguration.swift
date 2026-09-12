import Foundation

struct TelnyxConfiguration: Equatable, Sendable {
    let sipUser: String
    let password: String
    let callerNumber: String

    static func load(from bundle: Bundle = .main) throws -> TelnyxConfiguration {
        let configuration = TelnyxConfiguration(
            sipUser: bundle.string(forInfoDictionaryKey: "TelnyxSIPUser"),
            password: bundle.string(forInfoDictionaryKey: "TelnyxPassword"),
            callerNumber: bundle.string(forInfoDictionaryKey: "TelnyxCallerNumber")
        )

        let missing = [
            ("TELNYX_SIP_USER", configuration.sipUser),
            ("TELNYX_PASSWORD", configuration.password),
            ("TELNYX_CALLER_NUMBER", configuration.callerNumber)
        ]
        .filter { $0.1.isEmpty }
        .map(\.0)

        guard missing.isEmpty else {
            throw TelnyxConfigurationError.missingValues(missing)
        }
        return configuration
    }
}

private extension Bundle {
    func string(forInfoDictionaryKey key: String) -> String {
        (object(forInfoDictionaryKey: key) as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }
}

enum TelnyxConfigurationError: LocalizedError, Equatable {
    case missingValues([String])

    var errorDescription: String? {
        switch self {
        case .missingValues(let names):
            "Configure \(names.joined(separator: ", ")) in Config.local.xcconfig."
        }
    }
}
