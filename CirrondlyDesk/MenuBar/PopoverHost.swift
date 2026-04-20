import AppKit
import SwiftUI

@MainActor
final class PopoverHost: NSObject, NSPopoverDelegate {
    private let popover = NSPopover()
    private var localKeyMonitor: Any?
    private var globalClickMonitor: Any?
    private var appDeactivateMonitor: NSObjectProtocol?

    init(container: DependencyContainer) {
        super.init()

        popover.behavior = .applicationDefined
        popover.animates = true
        popover.delegate = self
        popover.appearance = NSAppearance(named: .aqua)
        popover.contentSize = NSSize(width: 420, height: 600)
        popover.contentViewController = NSHostingController(
            rootView: PopoverRootView()
                .environmentObject(container)
                .preferredColorScheme(.light)
        )
    }

    func toggle(relativeTo button: NSStatusBarButton, onOpen: @escaping () -> Void, onClose: @escaping () -> Void) {
        if popover.isShown {
            close(onClose: onClose)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.appearance = NSAppearance(named: .aqua)
            installEventMonitors(onClose: onClose)
            onOpen()
        }
    }

    func popoverDidClose(_ notification: Notification) {
        removeEventMonitors()
    }

    private func close(onClose: @escaping () -> Void) {
        guard popover.isShown else { return }
        popover.performClose(nil)
        onClose()
    }

    private func installEventMonitors(onClose: @escaping () -> Void) {
        removeEventMonitors()

        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            guard let self else { return event }

            if event.keyCode == 53 {
                self.close(onClose: onClose)
                return nil
            }

            return event
        }

        globalClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.close(onClose: onClose)
            }
        }

        appDeactivateMonitor = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.close(onClose: onClose)
            }
        }
    }

    private func removeEventMonitors() {
        if let localKeyMonitor {
            NSEvent.removeMonitor(localKeyMonitor)
            self.localKeyMonitor = nil
        }

        if let globalClickMonitor {
            NSEvent.removeMonitor(globalClickMonitor)
            self.globalClickMonitor = nil
        }

        if let appDeactivateMonitor {
            NotificationCenter.default.removeObserver(appDeactivateMonitor)
            self.appDeactivateMonitor = nil
        }
    }
}