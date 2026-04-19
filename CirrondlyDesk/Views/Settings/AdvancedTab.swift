import AppKit
import SwiftUI

struct AdvancedTab: View {
    @AppStorage("advanced.statusline.enabled") private var statuslineEnabled = true

    var body: some View {
        SettingsPaneScroll {
            SettingsSectionCard(title: "Integrations", subtitle: "Exports and local maintenance tools live here.", eyebrow: "Advanced") {
                VStack(alignment: .leading, spacing: 16) {
                    SettingsSectionHeader(
                        title: "Integrations",
                        subtitle: "These controls affect secondary integrations rather than local usage collection itself.",
                        eyebrow: "Advanced"
                    )

                    SettingsSplitRow(
                        title: "Statusline export",
                        subtitle: "Continuously write the latest usage snapshot to the shell-friendly statusline payload."
                    ) {
                        Toggle("Statusline export", isOn: $statuslineEnabled)
                            .labelsHidden()
                    }
                }
            }

            SettingsSectionCard(title: "Storage", subtitle: "Local state, credentials, and exported data stay on disk here.", eyebrow: "Data") {
                VStack(alignment: .leading, spacing: 14) {
                    SettingsSectionHeader(
                        title: "Local storage",
                        subtitle: "Use this folder if you need to inspect cached usage or reset the local app state.",
                        eyebrow: "Data"
                    )

                    Text(storagePath)
                        .font(Typography.mono(11))
                        .foregroundStyle(Color.cirrondlyBlueDark)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.cirrondlyBlueLightest.opacity(0.9), in: RoundedRectangle(cornerRadius: 16, style: .continuous))

                    Button("Open Folder") {
                        NSWorkspace.shared.open(URL(fileURLWithPath: storagePath))
                    }
                }
            }

            SettingsSectionCard(title: "Reset", subtitle: "Use only when you want to clear local preferences and start over.", eyebrow: "Danger Zone") {
                VStack(alignment: .leading, spacing: 14) {
                    SettingsSectionHeader(
                        title: "Reset local settings",
                        subtitle: "This clears UserDefaults for the app. Provider credentials stored outside the app are not removed.",
                        eyebrow: "Danger Zone"
                    )

                    Button("Reset local settings", role: .destructive) {
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