import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let container = DependencyContainer.shared

    private var statusBarController: StatusBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        statusBarController = StatusBarController(container: container)
        statusBarController?.install()

        container.notificationService.requestAuthorizationIfNeeded()
        container.pollingManager.start()

        Task {
            await container.usageAggregator.refresh(force: true)
            await container.serviceStatusMonitor.refreshIfNeeded(force: true)
            await container.updateChecker.checkForUpdatesIfNeeded()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        container.pollingManager.stop()
    }
}