import SwiftUI

struct DisplayTab: View {
    @AppStorage("general.menuBarMode") private var menuBarMode = MenuBarMode.minimal.rawValue
    @AppStorage("general.theme") private var theme = "auto"

    var body: some View {
        SettingsPaneScroll {
            SettingsSectionCard(title: "Menu Bar", subtitle: "Tune the signal you keep visible all day.", eyebrow: "Display") {
                VStack(alignment: .leading, spacing: 16) {
                    SettingsSectionHeader(
                        title: "Menu bar presentation",
                        subtitle: "Switch between a minimal icon, raw percentage, burn-rate hint, or provider plus percentage.",
                        eyebrow: "Display"
                    )

                    SettingsSplitRow(
                        title: "Display mode",
                        subtitle: currentModeDescription
                    ) {
                        Menu {
                            ForEach(MenuBarMode.allCases) { mode in
                                Button {
                                    menuBarMode = mode.rawValue
                                } label: {
                                    if menuBarMode == mode.rawValue {
                                        Label(mode.title, systemImage: "checkmark")
                                    } else {
                                        Text(mode.title)
                                    }
                                }
                            }
                        } label: {
                            HStack(spacing: 8) {
                                Text(selectedModeTitle)
                                    .font(Typography.body(13, weight: .semibold))
                                    .foregroundStyle(Color.cirrondlyBlueDark)
                                    .lineLimit(1)

                                Image(systemName: "chevron.up.chevron.down")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(Color.cirrondlyBlueDark.opacity(0.62))
                            }
                            .frame(width: 180, alignment: .leading)
                        }
                        .menuStyle(.borderlessButton)
                        .buttonStyle(.plain)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 9)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(Color.white.opacity(0.96))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(Color.cirrondlyBlueLight.opacity(0.9), lineWidth: 1)
                        )
                    }

                    Divider()

                    modePreviewGrid
                }
            }

            SettingsSectionCard(title: "Appearance", subtitle: "Keep the preferences window consistent with the rest of your desktop.", eyebrow: "Theme") {
                VStack(alignment: .leading, spacing: 16) {
                    SettingsSectionHeader(
                        title: "Theme",
                        subtitle: "The current build keeps the settings surface light and adapts the app theme selection for future appearance controls.",
                        eyebrow: "Theme"
                    )

                    Picker("Theme", selection: $theme) {
                        Text("Auto").tag("auto")
                        Text("Light").tag("light")
                        Text("Dark").tag("dark")
                    }
                    .pickerStyle(.segmented)

                    Text("Cirrondly's menu bar and settings visuals continue using the app's blue and mint palette regardless of the theme choice.")
                        .font(Typography.body(11))
                        .foregroundStyle(Color.cirrondlyBlueDark.opacity(0.68))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var currentModeDescription: String {
        guard let mode = MenuBarMode(rawValue: menuBarMode) else { return "Show the status item in the menu bar." }

        switch mode {
        case .minimal:
            return "Shows only the icon and health dot."
        case .percentage:
            return "Shows the highest usage percentage across enabled providers."
        case .burnRate:
            return "Shows estimated time remaining when burn-rate data exists."
        case .providerPercentage:
            return "Shows the leading provider icon with its current percentage."
        }
    }

    private var selectedModeTitle: String {
        MenuBarMode(rawValue: menuBarMode)?.title ?? MenuBarMode.minimal.title
    }

    private var modePreviewGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 12)], spacing: 12) {
            ForEach(MenuBarMode.allCases) { mode in
                let isSelected = menuBarMode == mode.rawValue

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(mode.title)
                            .font(Typography.body(13, weight: .semibold))
                        Spacer(minLength: 8)
                        if isSelected {
                            SettingsBadge(title: "Active", tint: .cirrondlyGreenAccent)
                        }
                    }

                    Text(modeSummary(mode))
                        .font(Typography.body(11))
                        .foregroundStyle(Color.cirrondlyBlueDark.opacity(0.68))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(isSelected ? Color.cirrondlyBlueLightest.opacity(0.95) : Color.white.opacity(0.58))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(isSelected ? Color.cirrondlyBlueDark.opacity(0.34) : Color.cirrondlyBlueLight.opacity(0.58), lineWidth: 1)
                )
            }
        }
    }

    private func modeSummary(_ mode: MenuBarMode) -> String {
        switch mode {
        case .minimal:
            return "Quiet default for a low-noise menu bar."
        case .percentage:
            return "Best when you want a plain quota readout at a glance."
        case .burnRate:
            return "Useful when local history can estimate how fast a session is consuming budget."
        case .providerPercentage:
            return "Best when you want to see which provider icon is currently closest to its limit."
        }
    }
}