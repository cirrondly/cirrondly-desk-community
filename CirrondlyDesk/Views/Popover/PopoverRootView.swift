import SwiftUI

struct PopoverRootView: View {
    @EnvironmentObject private var container: DependencyContainer

    private var effectiveSnapshot: UsageSnapshot? {
        guard let snapshot = container.usageAggregator.snapshot else { return nil }
        let enabledIdentifiers = Set(container.providerRegistry.enabledProviders().map(\.identifier))
        let visibleProviders = snapshot.providers.filter { enabledIdentifiers.contains($0.identifier) }
        guard !visibleProviders.isEmpty else { return nil }
        return UsageSnapshot.build(generatedAt: snapshot.generatedAt, providers: visibleProviders)
    }

    var body: some View {
        ZStack {
            GradientBackground()

            VStack(spacing: 0) {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 16) {
                        HeaderView(lastUpdated: container.usageAggregator.lastRefreshedAt)

                        if let snapshot = effectiveSnapshot {
                            VStack(alignment: .leading, spacing: 12) {
                                TodayCostView(snapshot: snapshot)
                                BurnRateIndicator(burnRate: snapshot.providers.compactMap(\.burnRate).max { ($0.costPerHour) < ($1.costPerHour) })
                            }
                            .padding(16)
                            .background(Color.white.opacity(0.75), in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 22, style: .continuous)
                                    .stroke(Color.cirrondlyBlueLight.opacity(0.6), lineWidth: 1)
                            )

                            ForEach(snapshot.providers) { provider in
                                ProviderRowView(provider: provider)
                            }
                        } else if container.usageAggregator.isRefreshing {
                            ProgressView("Refreshing providers…")
                                .font(Typography.body(13))
                        } else {
                            Text("No providers have reported usage yet. Enable sources in Settings to start tracking locally.")
                                .font(Typography.body(13))
                                .foregroundStyle(Color.cirrondlyBlueDark.opacity(0.8))
                                .padding(16)
                                .background(Color.white.opacity(0.7), in: RoundedRectangle(cornerRadius: 18))
                        }
                    }
                    .padding(16)
                }
                .background(HiddenScrollerConfigurator())

                Divider()
                    .overlay(Color.cirrondlyBlueLight.opacity(0.45))

                FooterActionsView()
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
            }
            .frame(width: 420, height: 600)
        }
    }
}

private struct HiddenScrollerConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        view.postsFrameChangedNotifications = true
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            guard let scrollView = nsView.enclosingScrollView else { return }
            scrollView.hasVerticalScroller = false
            scrollView.hasHorizontalScroller = false
            scrollView.scrollerStyle = .overlay
            scrollView.drawsBackground = false
            scrollView.backgroundColor = .clear
            scrollView.contentView.drawsBackground = false
        }
    }
}