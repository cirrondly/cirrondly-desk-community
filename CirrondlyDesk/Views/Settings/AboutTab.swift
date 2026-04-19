import SwiftUI

struct AboutTab: View {
    @EnvironmentObject private var container: DependencyContainer
    @Environment(\.openURL) private var openURL

    var body: some View {
        SettingsPaneScroll {
            SettingsSectionCard(title: "Cirrondly Desk", subtitle: "Native macOS usage tracking for AI tools across your desktop.", eyebrow: "About") {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 14) {
                        Image("CloudLogo")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 58, height: 38)

                        VStack(alignment: .leading, spacing: 5) {
                            Text("Cirrondly Desk")
                                .font(Typography.body(24, weight: .semibold))
                            Text(versionString)
                                .font(Typography.body(12))
                                .foregroundStyle(Color.cirrondlyBlueDark.opacity(0.72))
                        }

                        Spacer(minLength: 12)

                        SettingsBadge(title: "macOS", tint: .cirrondlyBlueDark)
                    }

                    Text("Track provider limits, burn rate, and credits in the menu bar without sending your local usage anywhere unless you explicitly connect a workspace.")
                        .font(Typography.body(12))
                        .foregroundStyle(Color.cirrondlyBlueDark.opacity(0.72))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            SettingsSectionCard(title: "Updates", subtitle: "Manual update checks stay available from inside settings.", eyebrow: "Release") {
                VStack(alignment: .leading, spacing: 14) {
                    SettingsSectionHeader(
                        title: "Release channel",
                        subtitle: "Use a manual check when you want to pull the latest build without waiting for the background updater.",
                        eyebrow: "Release"
                    )

                    Button("Check for updates") {
                        Task { await container.updateChecker.checkForUpdatesIfNeeded() }
                    }
                }
            }

            SettingsSectionCard(title: "Inspired by Open Source", subtitle: "Provider support in Cirrondly Desk builds on ideas, research, and prior open source work from these projects.", eyebrow: "Credits") {
                VStack(alignment: .leading, spacing: 14) {
                    SettingsSectionHeader(
                        title: "Inspired by Open Source",
                        subtitle: "Provider support in Cirrondly Desk builds on ideas, research, and prior open source work from these projects.",
                        eyebrow: "Credits"
                    )

                    attributionLink(title: "robinebers/openusage", url: "https://github.com/robinebers/openusage")
                    attributionLink(title: "Maciek-roboblog/Claude-Code-Usage-Monitor", url: "https://github.com/Maciek-roboblog/Claude-Code-Usage-Monitor")
                    attributionLink(title: "eddmann/ClaudeMeter", url: "https://github.com/eddmann/ClaudeMeter")
                    attributionLink(title: "theDanButuc/Claude-Usage-Monitor", url: "https://github.com/theDanButuc/Claude-Usage-Monitor")
                }
            }

            SettingsSectionCard(title: "Community", subtitle: "Cirrondly Desk Community is open source and maintained in public.", eyebrow: "Open Source") {
                VStack(alignment: .leading, spacing: 14) {
                    SettingsSectionHeader(
                        title: "Contribute or report issues",
                        subtitle: "Open an issue, review the code, or send a pull request in the public repository.",
                        eyebrow: "Open Source"
                    )

                    HStack(spacing: 10) {
                        Button("Open repository") {
                            openURL(URL(string: "https://github.com/cirrondly/cirrondly-desk-community")!)
                        }

                        Button("Report issue") {
                            openURL(URL(string: "https://github.com/cirrondly/cirrondly-desk-community/issues")!)
                        }
                    }
                }
            }
        }
    }

    private var versionString: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "Version \(short) (\(build))"
    }

    private func attributionLink(title: String, url: String) -> some View {
        Button {
            openURL(URL(string: url)!)
        } label: {
            HStack {
                Text(title)
                    .font(Typography.body(12, weight: .semibold))
                Spacer(minLength: 10)
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 11, weight: .semibold))
            }
            .foregroundStyle(Color.cirrondlyBlueDark)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white.opacity(0.65), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.cirrondlyBlueLight.opacity(0.72), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}