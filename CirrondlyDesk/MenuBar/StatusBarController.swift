import AppKit
import Combine

@MainActor
final class StatusBarController {
    private let container: DependencyContainer
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let popoverHost: PopoverHost
    private var cancellables = Set<AnyCancellable>()

    init(container: DependencyContainer) {
        self.container = container
        self.popoverHost = PopoverHost(container: container)
    }

    func install() {
        if let button = statusItem.button {
            button.target = self
            button.action = #selector(togglePopover(_:))
            button.image = StatusIconRenderer.image(for: nil)
            button.imagePosition = .imageLeading
        }

        observeSnapshot()
    }

    @objc private func togglePopover(_ sender: Any?) {
        guard let button = statusItem.button else { return }
        popoverHost.toggle(
            relativeTo: button,
            onOpen: {
                self.container.pollingManager.onPopoverOpen()
                Task { await self.container.pollingManager.forceRefresh() }
            },
            onClose: {
                self.container.pollingManager.onPopoverClose()
            }
        )
    }

    private func observeSnapshot() {
        container.usageAggregator.$snapshot
            .receive(on: RunLoop.main)
            .sink { [weak self] snapshot in
                guard let self, let button = self.statusItem.button else { return }
                button.image = StatusIconRenderer.image(for: snapshot)
                button.title = StatusIconRenderer.title(for: snapshot)
                button.toolTip = StatusIconRenderer.toolTip(for: snapshot)
            }
            .store(in: &cancellables)
    }
}