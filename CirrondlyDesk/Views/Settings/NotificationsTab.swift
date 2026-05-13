import SwiftUI

struct DisplayTab: View {
    @AppStorage("general.menuBarMode") private var menuBarMode = MenuBarMode.minimal.rawValue
    @AppStorage("general.theme") private var theme = "auto"

    var body: some View {
        SettingsPaneScroll {
            SettingsSectionCard(title: L10n.tr("settings.display.menuBar.cardTitle"), subtitle: L10n.tr("settings.display.menuBar.cardSubtitle"), eyebrow: L10n.tr("settings.tab.display")) {
                VStack(alignment: .leading, spacing: 16) {
                    SettingsSectionHeader(
                        title: L10n.tr("settings.display.menuBar.headerTitle"),
                        subtitle: L10n.tr("settings.display.menuBar.headerSubtitle"),
                        eyebrow: L10n.tr("settings.tab.display")
                    )

                    SettingsSplitRow(
                        title: L10n.tr("settings.display.menuBar.displayMode"),
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

            SettingsSectionCard(title: L10n.tr("settings.display.appearance.cardTitle"), subtitle: L10n.tr("settings.display.appearance.cardSubtitle"), eyebrow: L10n.tr("settings.display.appearance.eyebrow")) {
                VStack(alignment: .leading, spacing: 16) {
                    SettingsSectionHeader(
                        title: L10n.tr("settings.display.appearance.headerTitle"),
                        subtitle: L10n.tr("settings.display.appearance.headerSubtitle"),
                        eyebrow: L10n.tr("settings.display.appearance.eyebrow")
                    )

                    Picker(L10n.tr("settings.display.appearance.headerTitle"), selection: $theme) {
                        Text(L10n.tr("settings.display.theme.auto")).tag("auto")
                        Text(L10n.tr("settings.display.theme.light")).tag("light")
                        Text(L10n.tr("settings.display.theme.dark")).tag("dark")
                    }
                    .pickerStyle(.segmented)

                    Text(L10n.tr("settings.display.appearance.body"))
                        .font(Typography.body(11))
                        .foregroundStyle(Color.cirrondlyBlueDark.opacity(0.68))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var currentModeDescription: String {
        guard let mode = MenuBarMode(rawValue: menuBarMode) else { return L10n.tr("settings.display.mode.unknown") }

        switch mode {
        case .minimal:
            return L10n.tr("settings.display.mode.minimal")
        case .percentage:
            return L10n.tr("settings.display.mode.percentage")
        case .burnRate:
            return L10n.tr("settings.display.mode.burnRate")
        case .providerPercentage:
            return L10n.tr("settings.display.mode.providerPercentage")
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
                            SettingsBadge(title: L10n.tr("settings.profiles.button.active"), tint: .cirrondlyGreenAccent)
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
            return L10n.tr("settings.display.modeSummary.minimal")
        case .percentage:
            return L10n.tr("settings.display.modeSummary.percentage")
        case .burnRate:
            return L10n.tr("settings.display.modeSummary.burnRate")
        case .providerPercentage:
            return L10n.tr("settings.display.modeSummary.providerPercentage")
        }
    }
}