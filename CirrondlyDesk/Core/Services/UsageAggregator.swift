import Foundation

@MainActor
final class UsageAggregator: ObservableObject {
    @Published private(set) var snapshot: UsageSnapshot?
    @Published private(set) var isRefreshing = false
    @Published private(set) var lastRefreshedAt: Date?

    private let providerRegistry: ProviderRegistry

    init(providerRegistry: ProviderRegistry) {
        self.providerRegistry = providerRegistry
    }

    func syncEnabledProviders() {
        let enabledProviders = providerRegistry.enabledProviders()
        let enabledIdentifiers = Set(enabledProviders.map(\.identifier))

        guard let snapshot else {
            self.snapshot = enabledProviders.isEmpty
                ? nil
                : UsageSnapshot.build(providers: enabledProviders.map(placeholderResult(for:)))
            self.lastRefreshedAt = self.snapshot?.generatedAt
            return
        }

        var visibleProviders = snapshot.providers.filter { enabledIdentifiers.contains($0.identifier) }
        let existingIdentifiers = Set(visibleProviders.map(\.identifier))
        let pendingProviders = enabledProviders.filter { !existingIdentifiers.contains($0.identifier) }
        visibleProviders.append(contentsOf: pendingProviders.map(placeholderResult(for:)))

        self.snapshot = UsageSnapshot.build(
            generatedAt: snapshot.generatedAt,
            providers: visibleProviders
        )
        self.lastRefreshedAt = self.snapshot?.generatedAt
    }

    func refresh(force: Bool = false) async {
        if isRefreshing && !force { return }
        isRefreshing = true
        defer { isRefreshing = false }

        let providers = providerRegistry.enabledProviders()
        let results = await withTaskGroup(of: ProviderResult?.self) { group in
            for provider in providers {
                group.addTask {
                    do {
                        guard await provider.isAvailable() else { return nil }
                        return try await provider.probe()
                    } catch {
                        return ProviderResult.unavailable(
                            identifier: provider.identifier,
                            displayName: provider.displayName,
                            category: provider.category,
                            profile: provider.activeProfile?.name ?? "Default",
                            warning: error.localizedDescription
                        )
                    }
                }
            }

            var partials: [ProviderResult] = []
            for await result in group {
                if let result {
                    partials.append(result)
                }
            }
            return partials
        }

        snapshot = UsageSnapshot.build(providers: results)
        lastRefreshedAt = snapshot?.generatedAt
    }

    func providerResult(for id: String) -> ProviderResult? {
        snapshot?.providers.first { $0.identifier == id }
    }

    private func placeholderResult(for provider: any UsageProvider) -> ProviderResult {
        ProviderResult(
            identifier: provider.identifier,
            displayName: provider.displayName,
            category: provider.category,
            profile: provider.activeProfile?.name ?? "Default",
            windows: [],
            today: .zero,
            burnRate: nil,
            dailyHeatmap: [],
            models: [],
            source: .local,
            freshness: Date(),
            warnings: [ProviderWarning(level: .info, message: "Enabled. Refreshing usage data now.")]
        )
    }
}