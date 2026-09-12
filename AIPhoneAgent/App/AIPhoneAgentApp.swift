import SwiftUI
import Observation

@MainActor
@Observable
final class AppSettings {
    var language: AppLanguage {
        didSet {
            UserDefaults.standard.set(language.rawValue, forKey: AppLanguage.storageKey)
        }
    }

    init(language: AppLanguage = .selected) {
        self.language = language
    }
}

@main
struct AIPhoneAgentApp: App {
    @State private var callController = CallController()
    @State private var appSettings = AppSettings()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(callController)
                .environment(appSettings)
                .environment(\.locale, appSettings.language.locale)
                .id(appSettings.language.rawValue)
        }
    }
}
