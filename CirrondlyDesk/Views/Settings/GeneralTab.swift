import SwiftUI

struct GeneralTab: View {
    @EnvironmentObject private var container: DependencyContainer

    @AppStorage("general.refreshInterval") private var refreshInterval = 300.0
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
            SettingsSectionCard(title: "System", subtitle: "Choose how Cirrondly Desk runs day to day.", eyebrow: "General") {
                VStack(alignment: .leading, spacing: 16) {
                    SettingsSectionHeader(
                        title: "System",
                        subtitle: "Startup and background polling defaults for the menu bar app.",
                        eyebrow: "General"
                    )

                    SettingsSplitRow(
                        title: "Launch at login",
                        subtitle: "Automatically open Cirrondly Desk when your Mac session starts."
                    ) {
                        Toggle("Launch at login", isOn: Binding(
                            get: { container.launchAtLoginService.isEnabled },
                            set: { container.launchAtLoginService.setEnabled($0) }
                        ))
                        .labelsHidden()
                        .toggleStyle(.switch)
                    }

                    Divider()

                    SettingsSplitRow(
                        title: "Refresh cadence",
                        subtitle: "Controls how often enabled providers are checked in the background."
                    ) {
                        Picker("Refresh cadence", selection: $refreshInterval) {
                            Text("30 seconds").tag(30.0)
                            Text("1 minute").tag(60.0)
                            Text("2 minutes").tag(120.0)
                            Text("5 minutes").tag(300.0)
                            Text("10 minutes").tag(600.0)
                        }
                        .pickerStyle(.menu)
                        .labelsHidden()
                        .frame(width: 170)
                    }
                }
            }

            SettingsSectionCard(title: "Alerts", subtitle: "Pick when quota warnings should interrupt you.", eyebrow: "Notifications") {
                VStack(alignment: .leading, spacing: 16) {
                    SettingsSectionHeader(
                        title: "Quota alerts",
                        subtitle: "Notification thresholds are evaluated against each provider's strongest usage window.",
                        eyebrow: "Notifications"
                    )

                    HStack(spacing: 10) {
                        thresholdToggle(title: "75%", binding: $notify75)
                        thresholdToggle(title: "90%", binding: $notify90)
                        thresholdToggle(title: "95%", binding: $notify95)
                        thresholdToggle(title: "100%", binding: $notify100)
                    }

                    Divider()

                    SettingsSplitRow(
                        title: "Play sound",
                        subtitle: "Attach the system notification sound when a provider crosses an enabled threshold."
                    ) {
                        Toggle("Play sound", isOn: $soundEnabled)
                            .labelsHidden()
                    }

                    Divider()

                    SettingsSplitRow(
                        title: "Quiet hours",
                        subtitle: "Pause notifications overnight while background tracking continues."
                    ) {
                        Toggle("Quiet hours", isOn: $quietEnabled)
                            .labelsHidden()
                    }

                    if quietEnabled {
                        HStack(spacing: 12) {
                            Picker("Starts", selection: $quietStart) {
                                ForEach(0..<24, id: \.self) { hour in
                                    Text(String(format: "%02d:00", hour)).tag(hour)
                                }
                            }
                            .pickerStyle(.menu)

                            Picker("Ends", selection: $quietEnd) {
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