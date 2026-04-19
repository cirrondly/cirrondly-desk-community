import Foundation

final class BurnRateCalculator {
    func buildHeuristicResult(
        identifier: String,
        displayName: String,
        category: ProviderCategory,
        profile: String,
        sessions: [RawSession],
        source: DataSource,
        warnings: [ProviderWarning] = []
    ) -> ProviderResult {
        let fiveHour = makeHeuristicWindow(kind: .fiveHour, duration: SessionWindowPreset.lastFiveHours.duration, sessions: sessions, unit: .tokens)
        let weekly = makeHeuristicWindow(kind: .weekly, duration: SessionWindowPreset.lastSevenDays.duration, sessions: sessions, unit: .tokens)
        let monthly = makeHeuristicWindow(kind: .monthly, duration: SessionWindowPreset.lastThirtyDays.duration, sessions: sessions, unit: .tokens)

        return ProviderResult(
            identifier: identifier,
            displayName: displayName,
            category: category,
            profile: profile,
            windows: [fiveHour, weekly, monthly].compactMap { $0 },
            today: todayUsage(from: sessions),
            burnRate: burnRate(from: sessions, activeWindow: fiveHour),
            dailyHeatmap: heatmap(from: sessions),
            models: modelBreakdown(from: sessions),
            source: source,
            freshness: Date(),
            warnings: warnings
        )
    }

    func todayUsage(from sessions: [RawSession]) -> DailyUsage {
        let todayStart = TimeHelpers.startOfDay(for: Date())
        let todaySessions = sessions.filter { $0.startedAt >= todayStart }
        return DailyUsage(
            costUSD: todaySessions.reduce(0) { $0 + $1.costUSD },
            tokens: todaySessions.reduce(0) { $0 + $1.totalTokens },
            requests: todaySessions.reduce(0) { $0 + max(1, $1.requestCount) }
        )
    }

    func modelBreakdown(from sessions: [RawSession]) -> [ModelBreakdown] {
        let grouped = Dictionary(grouping: sessions, by: \.model)
        return grouped.map { model, rows in
            ModelBreakdown(
                model: model,
                tokens: rows.reduce(0) { $0 + $1.totalTokens },
                requests: rows.reduce(0) { $0 + $1.requestCount },
                costUSD: rows.reduce(0) { $0 + $1.costUSD }
            )
        }
        .sorted { $0.tokens > $1.tokens }
    }

    func heatmap(from sessions: [RawSession], days: Int = 90) -> [DailyCell] {
        let calendar = Calendar.current
        let startDate = calendar.date(byAdding: .day, value: -(days - 1), to: TimeHelpers.startOfDay(for: Date())) ?? Date()
        let grouped = Dictionary(grouping: sessions.filter { $0.startedAt >= startDate }) {
            TimeHelpers.dayFormatter.string(from: TimeHelpers.startOfDay(for: $0.startedAt))
        }

        let totals = grouped.mapValues { rows in
            rows.reduce(0.0) { $0 + max($1.costUSD, Double($1.totalTokens)) }
        }
        let maxValue = totals.values.max() ?? 0

        return (0..<days).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: offset, to: startDate) else { return nil }
            let key = TimeHelpers.dayFormatter.string(from: date)
            let value = totals[key] ?? 0
            return DailyCell(date: date, value: value, intensity: DailyCell.intensity(for: value, max: maxValue))
        }
    }

    func heatmap(fromDailyValues values: [(date: Date, value: Double)], days: Int = 90) -> [DailyCell] {
        let calendar = Calendar.current
        let startDate = calendar.date(byAdding: .day, value: -(days - 1), to: TimeHelpers.startOfDay(for: Date())) ?? Date()
        let grouped = Dictionary(grouping: values.filter { $0.date >= startDate }) {
            TimeHelpers.dayFormatter.string(from: TimeHelpers.startOfDay(for: $0.date))
        }

        let totals = grouped.mapValues { rows in
            rows.reduce(0.0) { $0 + max(0, $1.value) }
        }
        let maxValue = totals.values.max() ?? 0

        return (0..<days).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: offset, to: startDate) else { return nil }
            let key = TimeHelpers.dayFormatter.string(from: date)
            let value = totals[key] ?? 0
            return DailyCell(date: date, value: value, intensity: DailyCell.intensity(for: value, max: maxValue))
        }
    }

    func burnRate(from sessions: [RawSession], activeWindow: Window?) -> BurnRate? {
        let since = Date().addingTimeInterval(-SessionWindowPreset.lastThirtyMinutes.duration)
        let recent = sessions.filter { $0.startedAt >= since }
        guard !recent.isEmpty else { return nil }

        let tokens = recent.reduce(0) { $0 + $1.totalTokens }
        guard tokens > 0 else { return nil }

        let cost = recent.reduce(0) { $0 + $1.costUSD }
        let minutes = max(1, min(30, Int(Date().timeIntervalSince(recent.map(\.startedAt).min() ?? Date()) / 60)))
        let tokensPerMinute = Double(tokens) / Double(minutes)
        let costPerHour = (cost / Double(minutes)) * 60

        var projectedTokens: Int?
        var projectedCost: Double?
        var remainingMinutes: Int?

        if let resetAt = activeWindow?.resetAt {
            let remaining = max(0, Int(resetAt.timeIntervalSinceNow / 60))
            remainingMinutes = remaining
            if let used = activeWindow?.used {
                projectedTokens = Int(used + (tokensPerMinute * Double(remaining)))
            }
            projectedCost = cost + ((costPerHour / 60) * Double(remaining))
        }

        return BurnRate(
            tokensPerMinute: tokensPerMinute,
            costPerHour: costPerHour,
            projectedTotalTokens: projectedTokens,
            projectedTotalCost: projectedCost,
            remainingMinutes: remainingMinutes
        )
    }

    private func makeHeuristicWindow(kind: WindowKind, duration: TimeInterval, sessions: [RawSession], unit: UsageUnit) -> Window? {
        let now = Date()
        let since = now.addingTimeInterval(-duration)
        let currentSessions = sessions.filter { $0.startedAt >= since }
        guard !sessions.isEmpty else { return nil }

        let currentUsed = Double(currentSessions.reduce(0) { $0 + $1.totalTokens })
        let historicalSamples = rollingSamples(for: sessions, duration: duration)
        let inferredLimit = percentile90(historicalSamples) ?? max(currentUsed * 1.25, 1)
        let percentage = min(100, inferredLimit > 0 ? (currentUsed / inferredLimit) * 100 : 0)
        let resetAt = currentSessions.map(\ .startedAt).min()?.addingTimeInterval(duration)
            ?? now.addingTimeInterval(duration)

        return Window(
            kind: kind,
            used: currentUsed,
            limit: inferredLimit,
            unit: unit,
            percentage: percentage,
            resetAt: resetAt
        )
    }

    private func rollingSamples(for sessions: [RawSession], duration: TimeInterval) -> [Double] {
        let sorted = sessions.sorted { $0.startedAt < $1.startedAt }
        guard !sorted.isEmpty else { return [] }

        return sorted.map { anchor in
            let rangeStart = anchor.startedAt.addingTimeInterval(-duration)
            return Double(sorted.filter { $0.startedAt >= rangeStart && $0.startedAt <= anchor.startedAt }.reduce(0) { $0 + $1.totalTokens })
        }
    }

    private func percentile90(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let index = Int(Double(sorted.count - 1) * 0.9)
        return max(sorted[index], 1)
    }
}