import SwiftUI

struct FooterActionsView: View {
    @EnvironmentObject private var container: DependencyContainer
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        HStack(spacing: 10) {
            Button {
                Task { await container.pollingManager.forceRefresh() }
            } label: {
                if container.usageAggregator.isRefreshing {
                    Label("Refreshing", systemImage: "arrow.triangle.2.circlepath")
                } else {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
            }
            .footerActionStyle()
            .disabled(container.usageAggregator.isRefreshing)

            Button {
                openSettingsReliably()
            } label: {
                Label("Settings", systemImage: "gearshape")
            }
            .footerActionStyle()

            Button {
                NSApp.terminate(nil)
            } label: {
                Label("Quit", systemImage: "xmark.circle")
            }
            .footerActionStyle()
        }
        .font(Typography.body(12, weight: .semibold))
    }

    @MainActor
    private func openSettingsReliably() {
        NSApp.activate(ignoringOtherApps: true)

        if focusExistingSettingsWindow() {
            return
        }

        openSettings()

        DispatchQueue.main.async {
            NSApp.activate(ignoringOtherApps: true)
            _ = focusExistingSettingsWindow()
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            NSApp.activate(ignoringOtherApps: true)
            _ = focusExistingSettingsWindow()
        }
    }

    @MainActor
    @discardableResult
    private func focusExistingSettingsWindow() -> Bool {
        guard let window = settingsWindow else { return false }
        if window.isMiniaturized {
            window.deminiaturize(nil)
        }
        window.orderFrontRegardless()
        window.makeKeyAndOrderFront(nil)
        return true
    }

    private var settingsWindow: NSWindow? {
        NSApp.windows.first(where: { $0.identifier == settingsWindowIdentifier })
            ?? NSApp.windows.first(where: { window in
                window.frame.width >= 700
                    && window.frame.height >= 500
                    && window.styleMask.contains(.titled)
            })
    }
}

private struct FooterActionStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .buttonStyle(.plain)
            .foregroundStyle(Color.cirrondlyBlueDark)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.white.opacity(0.88))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.cirrondlyBlueLight.opacity(0.65), lineWidth: 1)
            )
    }
}

private extension View {
    func footerActionStyle() -> some View {
        modifier(FooterActionStyle())
    }
}