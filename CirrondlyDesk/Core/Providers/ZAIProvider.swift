import Foundation

final class ZAIProvider: UsageProvider {
    static let identifier = "zai"
    static let displayName = "Z.ai"
    static let category: ProviderCategory = .usageBased

    private let defaults = UserDefaults.standard
    private let session = URLSession(configuration: .ephemeral)
    private let subscriptionURL = URL(string: "https://api.z.ai/api/biz/subscription/list")!
    private let quotaURL = URL(string: "https://api.z.ai/api/monitor/usage/quota/limit")!

    var isEnabled: Bool {
        get { defaults.object(forKey: "provider.zai.enabled") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "provider.zai.enabled") }
    }

    var profiles: [ProviderProfile] { [ProviderProfile(name: "Default")] }
    var activeProfile: ProviderProfile? = ProviderProfile(name: "Default")

    func isAvailable() async -> Bool {
        loadAPIKey() != nil
    }

    func probe() async throws -> ProviderResult {
        guard let apiKey = loadAPIKey() else {
            return .unavailable(
                identifier: Self.identifier,
                displayName: Self.displayName,
                category: Self.category,
                warning: "No ZAI_API_KEY found. Set up the environment variable first."
            )
        }

        let plan = try? await fetchSubscription(apiKey: apiKey)
        let quota = try await fetchQuota(apiKey: apiKey)

        let container = (quota["data"] as? [String: Any]) ?? quota
        let limits = (container["limits"] as? [[String: Any]]) ?? (quota as? [[String: Any]]) ?? []
        guard !limits.isEmpty else {
            return ProviderResult(
                identifier: Self.identifier,
                displayName: Self.displayName,
                category: Self.category,
                profile: plan ?? activeProfile?.name ?? "Default",
                windows: [],
                today: .zero,
                burnRate: nil,
                dailyHeatmap: [],
                models: [],
                source: .api,
                freshness: Date(),
                warnings: [ProviderWarning(level: .info, message: "Z.ai returned no usage data.")]
            )
        }

        guard let sessionLimit = findLimit(in: limits, type: "TOKENS_LIMIT", unit: 3) else {
            return ProviderResult(
                identifier: Self.identifier,
                displayName: Self.displayName,
                category: Self.category,
                profile: plan ?? activeProfile?.name ?? "Default",
                windows: [],
                today: .zero,
                burnRate: nil,
                dailyHeatmap: [],
                models: [],
                source: .api,
                freshness: Date(),
                warnings: [ProviderWarning(level: .info, message: "Z.ai returned no session quota data.")]
            )
        }

        var windows: [Window] = []
        let sessionUsed = Self.doubleValue(sessionLimit["percentage"]) ?? 0
        windows.append(Window(kind: .fiveHour, used: sessionUsed, limit: 100, unit: .requests, percentage: min(100, max(0, sessionUsed)), resetAt: Self.dateValue(sessionLimit["nextResetTime"])))

        if let weeklyLimit = findLimit(in: limits, type: "TOKENS_LIMIT", unit: 6) {
            let weeklyUsed = Self.doubleValue(weeklyLimit["percentage"]) ?? 0
            windows.append(Window(kind: .weekly, used: weeklyUsed, limit: 100, unit: .requests, percentage: min(100, max(0, weeklyUsed)), resetAt: Self.dateValue(weeklyLimit["nextResetTime"])))
        }

        if let webLimit = findLimit(in: limits, type: "TIME_LIMIT", unit: nil),
           let total = Self.doubleValue(webLimit["usage"]),
           total > 0 {
            let used = Self.doubleValue(webLimit["currentValue"]) ?? 0
            let percentage = min(100, max(0, (used / total) * 100))
            let resetAt = Self.dateValue(webLimit["nextResetTime"]) ?? nextMonthBoundary()
            windows.append(Window(kind: .custom("Web Searches"), used: used, limit: total, unit: .requests, percentage: percentage, resetAt: resetAt, windowStart: previousMonthBoundary(for: resetAt)))
        }

        return ProviderResult(
            identifier: Self.identifier,
            displayName: Self.displayName,
            category: Self.category,
            profile: plan ?? activeProfile?.name ?? "Default",
            windows: windows,
            today: .zero,
            burnRate: nil,
            dailyHeatmap: [],
            models: [],
            source: .api,
            freshness: Date(),
            warnings: []
        )
    }

    private func loadAPIKey() -> String? {
        for name in ["ZAI_API_KEY", "GLM_API_KEY"] {
            if let value = ProcessInfo.processInfo.environment[name]?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty {
                return value
            }
        }
        return nil
    }

    private func fetchSubscription(apiKey: String) async throws -> String? {
        var request = URLRequest(url: subscriptionURL)
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse,
              (200...299).contains(http.statusCode),
              let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let list = payload["data"] as? [[String: Any]],
              let first = list.first else {
            return nil
        }
        return Self.stringValue(first["productName"])
    }

    private func fetchQuota(apiKey: String) async throws -> [String: Any] {
        var request = URLRequest(url: quotaURL)
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: request)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 500
        if statusCode == 401 || statusCode == 403 {
            throw NSError(domain: "ZAIProvider", code: statusCode, userInfo: [NSLocalizedDescriptionKey: "API key invalid. Check your Z.ai API key."])
        }
        guard (200...299).contains(statusCode),
              let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NSError(domain: "ZAIProvider", code: statusCode, userInfo: [NSLocalizedDescriptionKey: "Usage response invalid. Try again later."])
        }
        return payload
    }

    private func findLimit(in limits: [[String: Any]], type: String, unit: Int?) -> [String: Any]? {
        var fallback: [String: Any]?
        for limit in limits {
            let limitType = Self.stringValue(limit["type"] ?? limit["name"])
            guard limitType == type else { continue }
            if let unit {
                if Self.intValue(limit["unit"]) == unit { return limit }
                if fallback == nil && limit["unit"] == nil { fallback = limit }
            } else {
                return limit
            }
        }
        return fallback
    }

    private func nextMonthBoundary() -> Date {
        let calendar = Calendar(identifier: .gregorian)
        let now = Date()
        let components = calendar.dateComponents([.year, .month], from: now)
        return calendar.date(from: DateComponents(timeZone: TimeZone(secondsFromGMT: 0), year: components.year, month: (components.month ?? 1) + 1, day: 1)) ?? now
    }

    private func previousMonthBoundary(for resetDate: Date?) -> Date? {
        guard let resetDate else { return nil }
        let calendar = Calendar(identifier: .gregorian)
        return calendar.date(byAdding: .month, value: -1, to: resetDate)
    }

    private static func stringValue(_ value: Any?) -> String? {
        guard let value = value as? String else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func doubleValue(_ value: Any?) -> Double? {
        if let value = value as? Double { return value }
        if let value = value as? Int { return Double(value) }
        if let value = value as? NSNumber { return value.doubleValue }
        if let value = value as? String { return Double(value.trimmingCharacters(in: .whitespacesAndNewlines)) }
        return nil
    }

    private static func intValue(_ value: Any?) -> Int? {
        if let value = value as? Int { return value }
        if let value = value as? NSNumber { return value.intValue }
        if let value = value as? String { return Int(value.trimmingCharacters(in: .whitespacesAndNewlines)) }
        return nil
    }

    private static func dateValue(_ value: Any?) -> Date? {
        if let value = value as? String { return TimeHelpers.parseISODate(value) }
        guard let numeric = doubleValue(value) else { return nil }
        return Date(timeIntervalSince1970: numeric > 10_000_000_000 ? numeric / 1000 : numeric)
    }
}