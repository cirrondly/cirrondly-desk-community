import Foundation

struct UsageSummary: Codable, Hashable {
    let worstPercentage: Double
    let worstProvider: String?
    let worstWindow: String?
    let totalCostTodayUSD: Double
    let totalTokensToday: Int
    let totalRequestsToday: Int
}

struct UsageSnapshot: Codable, Hashable {
    let generatedAt: Date
    let providers: [ProviderResult]
    let summary: UsageSummary

    static func build(generatedAt: Date = Date(), providers: [ProviderResult]) -> UsageSnapshot {
        let visibleProviders = providers.filter { $0.freshness != .distantPast }

        let primaryWindows = visibleProviders.compactMap { provider -> (ProviderResult, Window)? in
            guard let window = provider.primaryWindow else { return nil }
            return (provider, window)
        }

        let worst = primaryWindows.max { lhs, rhs in
            lhs.1.percentage < rhs.1.percentage
        }

        return UsageSnapshot(
            generatedAt: generatedAt,
            providers: visibleProviders.sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending },
            summary: UsageSummary(
                worstPercentage: worst?.1.percentage ?? 0,
                worstProvider: worst?.0.identifier,
                worstWindow: worst?.1.kind.reportingKey,
                totalCostTodayUSD: visibleProviders.reduce(0) { $0 + $1.today.costUSD },
                totalTokensToday: visibleProviders.reduce(0) { $0 + $1.today.tokens },
                totalRequestsToday: visibleProviders.reduce(0) { $0 + $1.today.requests }
            )
        )
    }
}