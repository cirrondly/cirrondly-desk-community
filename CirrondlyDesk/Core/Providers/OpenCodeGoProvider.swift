import Foundation

final class OpenCodeGoProvider: UsageProvider {
    static let identifier = "opencode-go"
    static let displayName = "OpenCode Go"
    static let category: ProviderCategory = .usageBased

    private let calculator = BurnRateCalculator()
    private let defaults = UserDefaults.standard
    private let sqlite = SQLiteReader()
    private let authURL = FileManager.default.homeDirectoryForCurrentUser.appending(path: ".local/share/opencode/auth.json")
    private let databaseURL = FileManager.default.homeDirectoryForCurrentUser.appending(path: ".local/share/opencode/opencode.db")
    private let fiveHours: TimeInterval = 5 * 60 * 60
    private let week: TimeInterval = 7 * 24 * 60 * 60
    private let limits = (session: 12.0, weekly: 30.0, monthly: 60.0)

    var isEnabled: Bool {
        get { defaults.object(forKey: "provider.opencode-go.enabled") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "provider.opencode-go.enabled") }
    }

    var profiles: [ProviderProfile] { [ProviderProfile(name: "Default")] }
    var activeProfile: ProviderProfile? = ProviderProfile(name: "Default")

    func isAvailable() async -> Bool {
        loadAuthKey() != nil || hasHistory().present
    }

    func probe() async throws -> ProviderResult {
        let authKey = loadAuthKey()
        let historyCheck = hasHistory()
        let detected = authKey != nil || historyCheck.present

        guard detected else {
            return .unavailable(
                identifier: Self.identifier,
                displayName: Self.displayName,
                category: Self.category,
                warning: "OpenCode Go not detected. Log in with OpenCode Go or use it locally first."
            )
        }

        if !historyCheck.ok {
            return emptyStateResult(message: "No usage data")
        }

        let historyResult = loadHistory()
        if !historyResult.ok {
            return emptyStateResult(message: "No usage data")
        }

        let rows = historyResult.rows
        let windows = buildWindows(rows: rows, now: Date())
        let sessions = rows.map { row in
            RawSession(
                providerIdentifier: Self.identifier,
                profile: activeProfile?.name ?? "Default",
                startedAt: row.createdAt,
                endedAt: row.createdAt,
                model: "opencode-go",
                inputTokens: 0,
                outputTokens: 0,
                requestCount: 1,
                costUSD: row.cost,
                projectHint: nil
            )
        }

        return ProviderResult(
            identifier: Self.identifier,
            displayName: Self.displayName,
            category: Self.category,
            profile: "Go",
            windows: windows,
            today: calculator.todayUsage(from: sessions),
            burnRate: calculator.burnRate(from: sessions, activeWindow: windows.first),
            dailyHeatmap: calculator.heatmap(from: sessions),
            models: calculator.modelBreakdown(from: sessions),
            source: .local,
            freshness: Date(),
            warnings: windows.isEmpty ? [ProviderWarning(level: .info, message: "No usage data")] : []
        )
    }

    func sessions(since: Date) async throws -> [RawSession] {
        loadHistory().rows
            .filter { $0.createdAt >= since }
            .map { row in
                RawSession(
                    providerIdentifier: Self.identifier,
                    profile: activeProfile?.name ?? "Default",
                    startedAt: row.createdAt,
                    endedAt: row.createdAt,
                    model: "opencode-go",
                    inputTokens: 0,
                    outputTokens: 0,
                    requestCount: 1,
                    costUSD: row.cost,
                    projectHint: nil
                )
            }
    }

    private func loadAuthKey() -> String? {
        guard let data = try? Data(contentsOf: authURL),
              let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let entry = payload[Self.identifier] as? [String: Any] else {
            return nil
        }
        return Self.stringValue(entry["key"])
    }

    private func hasHistory() -> (ok: Bool, present: Bool) {
        let sql = "SELECT 1 AS present FROM message WHERE json_valid(data) AND json_extract(data, '$.providerID') = 'opencode-go' AND json_extract(data, '$.role') = 'assistant' AND json_type(data, '$.cost') IN ('integer', 'real') LIMIT 1"
        do {
            let rows = try sqlite.query(databaseURL: databaseURL, sql: sql)
            return (true, !rows.isEmpty)
        } catch {
            return (false, false)
        }
    }

    private func loadHistory() -> (ok: Bool, rows: [OpenCodeGoRow]) {
        let sql = "SELECT CAST(COALESCE(json_extract(data, '$.time.created'), time_created) AS INTEGER) AS createdMs, CAST(json_extract(data, '$.cost') AS REAL) AS cost FROM message WHERE json_valid(data) AND json_extract(data, '$.providerID') = 'opencode-go' AND json_extract(data, '$.role') = 'assistant' AND json_type(data, '$.cost') IN ('integer', 'real')"
        do {
            let rows = try sqlite.query(databaseURL: databaseURL, sql: sql).compactMap { row -> OpenCodeGoRow? in
                guard let createdMs = Self.doubleValue(row["createdMs"]),
                      let cost = Self.doubleValue(row["cost"]),
                      createdMs > 0,
                      cost >= 0 else { return nil }
                return OpenCodeGoRow(createdAt: Date(timeIntervalSince1970: createdMs / 1000), cost: cost)
            }
            return (true, rows.sorted { $0.createdAt < $1.createdAt })
        } catch {
            return (false, [])
        }
    }

    private func buildWindows(rows: [OpenCodeGoRow], now: Date) -> [Window] {
        if rows.isEmpty {
            return [
                Window(kind: .fiveHour, used: 0, limit: 100, unit: .requests, percentage: 0, resetAt: now.addingTimeInterval(fiveHours)),
                Window(kind: .weekly, used: 0, limit: 100, unit: .requests, percentage: 0, resetAt: nextWeekBoundary(from: now)),
                Window(kind: .monthly, used: 0, limit: 100, unit: .requests, percentage: 0, resetAt: nextMonthBoundary(from: now, anchor: nil))
            ]
        }

        let sessionStart = now.addingTimeInterval(-fiveHours)
        let sessionCost = sumCost(rows: rows, from: sessionStart, to: now)
        let weeklyStart = startOfUTCWeek(from: now)
        let weeklyEnd = weeklyStart.addingTimeInterval(week)
        let weeklyCost = sumCost(rows: rows, from: weeklyStart, to: weeklyEnd)
        let earliest = rows.first?.createdAt
        let monthBounds = anchoredMonthBounds(now: now, anchor: earliest)
        let monthlyCost = sumCost(rows: rows, from: monthBounds.start, to: monthBounds.end)

        return [
            Window(kind: .fiveHour, used: clampPercent(used: sessionCost, limit: limits.session), limit: 100, unit: .requests, percentage: clampPercent(used: sessionCost, limit: limits.session), resetAt: nextRollingReset(rows: rows, now: now)),
            Window(kind: .weekly, used: clampPercent(used: weeklyCost, limit: limits.weekly), limit: 100, unit: .requests, percentage: clampPercent(used: weeklyCost, limit: limits.weekly), resetAt: weeklyEnd),
            Window(kind: .monthly, used: clampPercent(used: monthlyCost, limit: limits.monthly), limit: 100, unit: .requests, percentage: clampPercent(used: monthlyCost, limit: limits.monthly), resetAt: monthBounds.end)
        ]
    }

    private func emptyStateResult(message: String) -> ProviderResult {
        ProviderResult(
            identifier: Self.identifier,
            displayName: Self.displayName,
            category: Self.category,
            profile: "Go",
            windows: [],
            today: .zero,
            burnRate: nil,
            dailyHeatmap: [],
            models: [],
            source: .local,
            freshness: Date(),
            warnings: [ProviderWarning(level: .info, message: message)]
        )
    }

    private func sumCost(rows: [OpenCodeGoRow], from start: Date, to end: Date) -> Double {
        rows.reduce(0) { partial, row in
            guard row.createdAt >= start, row.createdAt < end else { return partial }
            return partial + row.cost
        }
    }

    private func clampPercent(used: Double, limit: Double) -> Double {
        guard limit > 0 else { return 0 }
        let percent = (used / limit) * 100
        return round(min(100, max(0, percent)) * 10) / 10
    }

    private func nextRollingReset(rows: [OpenCodeGoRow], now: Date) -> Date {
        let lowerBound = now.addingTimeInterval(-fiveHours)
        let oldestInWindow = rows.filter { $0.createdAt >= lowerBound && $0.createdAt < now }.map(\ .createdAt).min()
        return (oldestInWindow ?? now).addingTimeInterval(fiveHours)
    }

    private func startOfUTCWeek(from date: Date) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        let components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        return calendar.date(from: components) ?? date
    }

    private func nextWeekBoundary(from date: Date) -> Date {
        startOfUTCWeek(from: date).addingTimeInterval(week)
    }

    private func nextMonthBoundary(from date: Date, anchor: Date?) -> Date {
        anchoredMonthBounds(now: date, anchor: anchor).end
    }

    private func anchoredMonthBounds(now: Date, anchor: Date?) -> (start: Date, end: Date) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current

        guard let anchor else {
            let start = calendar.date(from: calendar.dateComponents([.year, .month], from: now)) ?? now
            let end = calendar.date(byAdding: DateComponents(month: 1), to: start) ?? now
            return (start, end)
        }

        var year = calendar.component(.year, from: now)
        var month = calendar.component(.month, from: now)
        var start = anchorMonth(year: year, month: month, anchor: anchor, calendar: calendar)

        if start > now {
            month -= 1
            if month == 0 {
                month = 12
                year -= 1
            }
            start = anchorMonth(year: year, month: month, anchor: anchor, calendar: calendar)
        }

        var nextMonth = month + 1
        var nextYear = year
        if nextMonth == 13 {
            nextMonth = 1
            nextYear += 1
        }

        return (start, anchorMonth(year: nextYear, month: nextMonth, anchor: anchor, calendar: calendar))
    }

    private func anchorMonth(year: Int, month: Int, anchor: Date, calendar: Calendar) -> Date {
        let maxDay = calendar.range(of: .day, in: .month, for: calendar.date(from: DateComponents(timeZone: calendar.timeZone, year: year, month: month)) ?? anchor)?.count ?? 28
        let anchorComponents = calendar.dateComponents([.day, .hour, .minute, .second, .nanosecond], from: anchor)
        return calendar.date(from: DateComponents(
            timeZone: calendar.timeZone,
            year: year,
            month: month,
            day: min(anchorComponents.day ?? 1, maxDay),
            hour: anchorComponents.hour,
            minute: anchorComponents.minute,
            second: anchorComponents.second,
            nanosecond: anchorComponents.nanosecond
        )) ?? anchor
    }

    private static func stringValue(_ value: Any?) -> String? {
        if let value = value as? String {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }
        return nil
    }

    private static func doubleValue(_ value: Any?) -> Double? {
        if let value = value as? Double { return value }
        if let value = value as? Int { return Double(value) }
        if let value = value as? NSNumber { return value.doubleValue }
        if let value = value as? String { return Double(value.trimmingCharacters(in: .whitespacesAndNewlines)) }
        return nil
    }
}

private struct OpenCodeGoRow {
    let createdAt: Date
    let cost: Double
}