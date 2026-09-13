import SwiftUI
import Observation

@MainActor
@Observable
final class AppSettings {
    private let defaults: UserDefaults
    var userIdentity: UserIdentity {
        didSet { userIdentity.save(to: defaults) }
    }

    var language: AppLanguage {
        didSet {
            defaults.set(language.rawValue, forKey: AppLanguage.storageKey)
        }
    }

    init(language: AppLanguage = .selected, identity: UserIdentity? = nil, defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.userIdentity = identity ?? UserIdentity.load(from: defaults)
        self.language = language
    }
}

@main
struct AIPhoneAgentApp: App {
    @State private var callController = CallController()
    @State private var appSettings = AppSettings()

    var body: some Scene {
        WindowGroup {
            Group {
                #if DEBUG
                if ProcessInfo.processInfo.arguments.contains("--visual-review") {
                    VisualReviewGallery()
                } else {
                    ContentView()
                }
                #else
                ContentView()
                #endif
            }
                .environment(callController)
                .environment(appSettings)
                .environment(\.locale, appSettings.language.locale)
                .id(appSettings.language.rawValue)
        }
    }
}
