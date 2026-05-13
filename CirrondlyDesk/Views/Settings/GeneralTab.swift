import SwiftUI

struct GeneralTab: View {
    @EnvironmentObject private var container: DependencyContainer

    @AppStorage("general.refreshInterval") private var refreshInterval = 300.0
    @AppStorage("notify.serviceStatus") private var notifyServiceStatus = true
    @AppStorage("notify.threshold.75") private var notify75 = true
    @AppStorage("notify.threshold.90") private var notify90 = true
    @AppStorage("notify.threshold.95") private var notify95 = false
    @AppStorage("notify.threshold.100") private var notify100 = true
    @AppStorage("notify.sound") private var soundEnabled = true
    @AppStorage("notify.quiet.enabled") private var quietEnabled = false
    @AppStorage("notify.quiet.startHour") private var quietStart = 22
    @AppStorage("notify.quiet.endHour") private var quietEnd = 8

    var body: some View {
        SettingsPaneScroll {
            SettingsSectionCard(title: L10n.tr("settings.general.system.cardTitle"), subtitle: L10n.tr("settings.general.system.cardSubtitle"), eyebrow: L10n.tr("settings.tab.general")) {
                VStack(alignment: .leading, spacing: 16) {
                    SettingsSectionHeader(
                        title: L10n.tr("settings.general.system.headerTitle"),
                        subtitle: L10n.tr("settings.general.system.headerSubtitle"),
                        eyebrow: L10n.tr("settings.tab.general")
                    )

                    SettingsSplitRow(
                        title: L10n.tr("settings.general.launchAtLogin.title"),
                        subtitle: L10n.tr("settings.general.launchAtLogin.subtitle")
                    ) {
                        Toggle(L10n.tr("settings.general.launchAtLogin.title"), isOn: Binding(
                            get: { container.launchAtLoginService.isEnabled },
                            set: { container.launchAtLoginService.setEnabled($0) }
                        ))
                        .labelsHidden()
                        .toggleStyle(.switch)
                    }

                    Divider()

                    SettingsSplitRow(
                        title: L10n.tr("settings.general.refreshCadence.title"),
                        subtitle: L10n.tr("settings.general.refreshCadence.subtitle")
                    ) {
                        Picker(L10n.tr("settings.general.refreshCadence.title"), selection: $refreshInterval) {
                            Text(L10n.tr("settings.general.refreshCadence.30s")).tag(30.0)
                            Text(L10n.tr("settings.general.refreshCadence.1m")).tag(60.0)
                            Text(L10n.tr("settings.general.refreshCadence.2m")).tag(120.0)
                            Text(L10n.tr("settings.general.refreshCadence.5m")).tag(300.0)
                            Text(L10n.tr("settings.general.refreshCadence.10m")).tag(600.0)
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                        .frame(width: 170)
                    }
                }
            }

            SettingsSectionCard(title: L10n.tr("settings.general.alerts.cardTitle"), subtitle: L10n.tr("settings.general.alerts.cardSubtitle"), eyebrow: L10n.tr("settings.general.alerts.eyebrow")) {
                VStack(alignment: .leading, spacing: 16) {
                    SettingsSectionHeader(
                        title: L10n.tr("settings.general.alerts.headerTitle"),
                        subtitle: L10n.tr("settings.general.alerts.headerSubtitle"),
                        eyebrow: L10n.tr("settings.general.alerts.eyebrow")
                    )

                    HStack(spacing: 10) {
                        thresholdToggle(title: "75%", binding: $notify75)
                        thresholdToggle(title: "90%", binding: $notify90)
                        thresholdToggle(title: "95%", binding: $notify95)
                        thresholdToggle(title: "100%", binding: $notify100)
                    }

                    Divider()

                    SettingsSplitRow(
                        title: L10n.tr("settings.general.serviceOutages.title"),
                        subtitle: L10n.tr("settings.general.serviceOutages.subtitle")
                    ) {
                        Toggle(L10n.tr("settings.general.serviceOutages.title"), isOn: $notifyServiceStatus)
                            .labelsHidden()
                    }

                    Divider()

                    SettingsSplitRow(
                        title: L10n.tr("settings.general.playSound.title"),
                        subtitle: L10n.tr("settings.general.playSound.subtitle")
                    ) {
                        Toggle(L10n.tr("settings.general.playSound.title"), isOn: $soundEnabled)
                            .labelsHidden()
                    }

                    Divider()

                    SettingsSplitRow(
                        title: L10n.tr("settings.general.quietHours.title"),
                        subtitle: L10n.tr("settings.general.quietHours.subtitle")
                    ) {
                        Toggle(L10n.tr("settings.general.quietHours.title"), isOn: $quietEnabled)
                            .labelsHidden()
                    }

                    if quietEnabled {
                        HStack(spacing: 12) {
                            Picker(L10n.tr("settings.general.quietHours.starts"), selection: $quietStart) {
                                ForEach(0..<24, id: \.self) { hour in
                                    Text(String(format: "%02d:00", hour)).tag(hour)
                                }
                            }
                            .pickerStyle(.menu)

                            Picker(L10n.tr("settings.general.quietHours.ends"), selection: $quietEnd) {
                                ForEach(0..<24, id: \.self) { hour in
                                    Text(String(format: "%02d:00", hour)).tag(hour)
                                }
                            }
                            .pickerStyle(.menu)
                        }
                    }
                }
            }
        }
        .onChange(of: refreshInterval) {
            container.pollingManager.baseInterval = refreshInterval
        }
    }

    private func thresholdToggle(title: String, binding: Binding<Bool>) -> some View {
        Toggle(isOn: binding) {
            Text(title)
                .font(Typography.body(11, weight: .semibold))
                .foregroundStyle(binding.wrappedValue ? Color.cirrondlyBlueDark : Color.cirrondlyBlueDark.opacity(0.7))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    Capsule()
                        .fill(binding.wrappedValue ? Color.cirrondlyGreenAccent.opacity(0.22) : Color.cirrondlyBlueLightest.opacity(0.9))
                )
                .overlay(
                    Capsule()
                        .stroke(binding.wrappedValue ? Color.cirrondlyGreenAccent.opacity(0.55) : Color.cirrondlyBlueLight.opacity(0.8), lineWidth: 1)
                )
        }
        .toggleStyle(.button)
    }
}