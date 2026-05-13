import AppKit
import SwiftUI

struct AdvancedTab: View {
    @AppStorage("advanced.statusline.enabled") private var statuslineEnabled = true

    var body: some View {
        SettingsPaneScroll {
            SettingsSectionCard(title: L10n.tr("settings.advanced.integrations.cardTitle"), subtitle: L10n.tr("settings.advanced.integrations.cardSubtitle"), eyebrow: L10n.tr("settings.tab.advanced")) {
                VStack(alignment: .leading, spacing: 16) {
                    SettingsSectionHeader(
                        title: L10n.tr("settings.advanced.integrations.headerTitle"),
                        subtitle: L10n.tr("settings.advanced.integrations.headerSubtitle"),
                        eyebrow: L10n.tr("settings.tab.advanced")
                    )

                    SettingsSplitRow(
                        title: L10n.tr("settings.advanced.statusline.title"),
                        subtitle: L10n.tr("settings.advanced.statusline.subtitle")
                    ) {
                        Toggle(L10n.tr("settings.advanced.statusline.title"), isOn: $statuslineEnabled)
                            .labelsHidden()
                    }
                }
            }

            SettingsSectionCard(title: L10n.tr("settings.advanced.storage.cardTitle"), subtitle: L10n.tr("settings.advanced.storage.cardSubtitle"), eyebrow: L10n.tr("settings.advanced.storage.eyebrow")) {
                VStack(alignment: .leading, spacing: 14) {
                    SettingsSectionHeader(
                        title: L10n.tr("settings.advanced.storage.headerTitle"),
                        subtitle: L10n.tr("settings.advanced.storage.headerSubtitle"),
                        eyebrow: L10n.tr("settings.advanced.storage.eyebrow")
                    )

                    Text(storagePath)
                        .font(Typography.mono(11))
                        .foregroundStyle(Color.cirrondlyBlueDark)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.cirrondlyBlueLightest.opacity(0.9), in: RoundedRectangle(cornerRadius: 16, style: .continuous))

                    Button(L10n.tr("settings.advanced.storage.openFolder")) {
                        NSWorkspace.shared.open(URL(fileURLWithPath: storagePath))
                    }
                }
            }

            SettingsSectionCard(title: L10n.tr("settings.advanced.reset.cardTitle"), subtitle: L10n.tr("settings.advanced.reset.cardSubtitle"), eyebrow: L10n.tr("settings.advanced.reset.eyebrow")) {
                VStack(alignment: .leading, spacing: 14) {
                    SettingsSectionHeader(
                        title: L10n.tr("settings.advanced.reset.headerTitle"),
                        subtitle: L10n.tr("settings.advanced.reset.headerSubtitle"),
                        eyebrow: L10n.tr("settings.advanced.reset.eyebrow")
                    )

                    Button(L10n.tr("settings.advanced.reset.button"), role: .destructive) {
                        if let bundle = Bundle.main.bundleIdentifier {
                            UserDefaults.standard.removePersistentDomain(forName: bundle)
                        }
                    }
                }
            }
        }
    }

    private var storagePath: String {
        FileManager.default.homeDirectoryForCurrentUser.appending(path: ".cirrondly").path
    }
}