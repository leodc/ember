import SwiftUI

@main
struct AIPhoneAgentApp: App {
    @State private var callController = CallController()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(callController)
        }
    }
}

