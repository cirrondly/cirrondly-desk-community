import SwiftUI

@main
struct CirrondlyDeskApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            SettingsScene()
                .environmentObject(appDelegate.container)
        }
    }
}