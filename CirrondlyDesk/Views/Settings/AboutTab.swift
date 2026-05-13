import SwiftUI

struct AboutTab: View {
    @EnvironmentObject private var container: DependencyContainer
    @Environment(\.openURL) private var openURL

    var body: some View {
        SettingsPaneScroll {
            SettingsSectionCard(title: L10n.tr("settings.about.app.cardTitle"), subtitle: L10n.tr("settings.about.app.cardSubtitle"), eyebrow: L10n.tr("settings.tab.about")) {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 14) {
                        Image("CloudLogo")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 58, height: 38)

                        VStack(alignment: .leading, spacing: 5) {
                            Text(L10n.tr("settings.about.app.cardTitle"))
                                .font(Typography.body(24, weight: .semibold))
                            Text(versionString)
                                .font(Typography.body(12))
                                .foregroundStyle(Color.cirrondlyBlueDark.opacity(0.72))
                        }

                        Spacer(minLength: 12)

                        SettingsBadge(title: "macOS", tint: .cirrondlyBlueDark)
                    }

                    Text(L10n.tr("settings.about.app.body"))
                        .font(Typography.body(12))
                        .foregroundStyle(Color.cirrondlyBlueDark.opacity(0.72))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            SettingsSectionCard(title: L10n.tr("settings.about.updates.cardTitle"), subtitle: L10n.tr("settings.about.updates.cardSubtitle"), eyebrow: L10n.tr("settings.about.updates.eyebrow")) {
                VStack(alignment: .leading, spacing: 14) {
                    SettingsSectionHeader(
                        title: L10n.tr("settings.about.updates.headerTitle"),
                        subtitle: L10n.tr("settings.about.updates.headerSubtitle"),
                        eyebrow: L10n.tr("settings.about.updates.eyebrow")
                    )

                    Button(L10n.tr("settings.about.updates.button")) {
                        Task { await container.updateChecker.checkForUpdatesIfNeeded() }
                    }
                }
            }

            SettingsSectionCard(title: L10n.tr("settings.about.credits.cardTitle"), subtitle: L10n.tr("settings.about.credits.cardSubtitle"), eyebrow: L10n.tr("settings.about.credits.eyebrow")) {
                VStack(alignment: .leading, spacing: 14) {
                    SettingsSectionHeader(
                        title: L10n.tr("settings.about.credits.headerTitle"),
                        subtitle: L10n.tr("settings.about.credits.headerSubtitle"),
                        eyebrow: L10n.tr("settings.about.credits.eyebrow")
                    )

                    attributionLink(title: "robinebers/openusage", url: "https://github.com/robinebers/openusage")
                    attributionLink(title: "Maciek-roboblog/Claude-Code-Usage-Monitor", url: "https://github.com/Maciek-roboblog/Claude-Code-Usage-Monitor")
                    attributionLink(title: "eddmann/ClaudeMeter", url: "https://github.com/eddmann/ClaudeMeter")
                    attributionLink(title: "theDanButuc/Claude-Usage-Monitor", url: "https://github.com/theDanButuc/Claude-Usage-Monitor")
                }
            }

            SettingsSectionCard(title: L10n.tr("settings.about.community.cardTitle"), subtitle: L10n.tr("settings.about.community.cardSubtitle"), eyebrow: L10n.tr("settings.about.community.eyebrow")) {
                VStack(alignment: .leading, spacing: 14) {
                    SettingsSectionHeader(
                        title: L10n.tr("settings.about.community.headerTitle"),
                        subtitle: L10n.tr("settings.about.community.headerSubtitle"),
                        eyebrow: L10n.tr("settings.about.community.eyebrow")
                    )

                    HStack(spacing: 10) {
                        Button(L10n.tr("settings.about.community.openRepository")) {
                            openURL(URL(string: "https://github.com/cirrondly/cirrondly-desk-community")!)
                        }

                        Button(L10n.tr("settings.about.community.reportIssue")) {
                            openURL(URL(string: "https://github.com/cirrondly/cirrondly-desk-community/issues")!)
                        }

                        Button(L10n.tr("settings.about.community.joinSlack")) {
                            openURL(URL(string: "https://join.slack.com/t/cirrondly/shared_invite/zt-3vvu6usdh-BCKprBTcOj0BiL~QAZNMBw")!)
                        }
                    }

                    Divider()

                    Button(L10n.tr("settings.about.community.teamAnalytics")) {
                        openURL(URL(string: "https://cirrondly.com/desk")!)
                    }
                    .font(Typography.body(11, weight: .semibold))
                }
            }
        }
    }

    private var versionString: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return L10n.tr("settings.about.version", short, build)
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