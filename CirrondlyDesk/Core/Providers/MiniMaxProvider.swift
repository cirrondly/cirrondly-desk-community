import Foundation

final class MiniMaxProvider: UsageProvider {
    static let identifier = "minimax"
    static let displayName = "MiniMax"
    static let category: ProviderCategory = .usageBased

    private let defaults = UserDefaults.standard
    private let session = URLSession(configuration: .ephemeral)
    private let globalPrimaryURL = URL(string: "https://api.minimax.io/v1/api/openplatform/coding_plan/remains")!
    private let globalFallbackURLs = [
        URL(string: "https://api.minimax.io/v1/coding_plan/remains")!,
        URL(string: "https://www.minimax.io/v1/api/openplatform/coding_plan/remains")!
    ]
    private let cnPrimaryURL = URL(string: "https://api.minimaxi.com/v1/api/openplatform/coding_plan/remains")!
    private let cnFallbackURLs = [URL(string: "https://api.minimaxi.com/v1/coding_plan/remains")!]
    private let codingPlanWindowMs: TimeInterval = 5 * 60 * 60 * 1000
    private let codingPlanToleranceMs: TimeInterval = 10 * 60 * 1000
    private let globalPromptLimits: [Int: String] = [100: "Starter", 300: "Plus", 1000: "Max", 2000: "Ultra"]
    private let cnPromptLimits: [Int: String] = [600: "Starter", 1500: "Plus", 4500: "Max"]
    private let modelCallsPerPrompt = 15.0

    var isEnabled: Bool {
        get { defaults.object(forKey: "provider.minimax.enabled") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "provider.minimax.enabled") }
    }

    var profiles: [ProviderProfile] { [ProviderProfile(name: "Default")] }
    var activeProfile: ProviderProfile? = ProviderProfile(name: "Default")

    func isAvailable() async -> Bool {
        endpointAttempts().contains { loadAPIKey(selection: $0) != nil }
    }

    func probe() async throws -> ProviderResult {
        var lastError: Error?

        for selection in endpointAttempts() {
            guard let apiKey = loadAPIKey(selection: selection) else { continue }
            do {
                let payload = try await fetchUsagePayload(apiKey: apiKey, selection: selection)
                guard let parsed = parsePayloadShape(payload, selection: selection) else {
                    lastError = NSError(domain: "MiniMaxProvider", code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not parse usage data."])
                    continue
                }

                let multiplier = selection == .cn ? (1 / modelCallsPerPrompt) : 1
                let used = round(parsed.used * multiplier)
                let limit = round(parsed.total * multiplier)
                let percentage = limit > 0 ? min(100, max(0, (used / limit) * 100)) : 0
                let window = Window(kind: .fiveHour, used: used, limit: limit, unit: .requests, percentage: percentage, resetAt: parsed.resetAt)
                let profile = parsed.planName.map { "\($0) (\(selection == .cn ? "CN" : "GLOBAL"))" } ?? activeProfile?.name ?? "Default"

                return ProviderResult(
                    identifier: Self.identifier,
                    displayName: Self.displayName,
                    category: Self.category,
                    profile: profile,
                    windows: [window],
                    today: .zero,
                    burnRate: nil,
                    dailyHeatmap: [],
                    models: [],
                    source: .api,
                    freshness: Date(),
                    warnings: []
                )
            } catch {
                lastError = error
            }
        }

        if let lastError {
            throw lastError
        }

        return .unavailable(
            identifier: Self.identifier,
            displayName: Self.displayName,
            category: Self.category,
            warning: "MiniMax API key missing. Set MINIMAX_API_KEY or MINIMAX_CN_API_KEY."
        )
    }

    private func endpointAttempts() -> [EndpointSelection] {
        if let cnKey = ProcessInfo.processInfo.environment["MINIMAX_CN_API_KEY"], !cnKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return [.cn, .global]
        }
        return [.global, .cn]
    }

    private func loadAPIKey(selection: EndpointSelection) -> String? {
        let names: [String]
        switch selection {
        case .global:
            names = ["MINIMAX_API_KEY", "MINIMAX_API_TOKEN"]
        case .cn:
            names = ["MINIMAX_CN_API_KEY", "MINIMAX_API_KEY", "MINIMAX_API_TOKEN"]
        }

        for name in names {
            if let value = ProcessInfo.processInfo.environment[name]?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty {
                return value
            }
        }
        return nil
    }

    private func usageURLs(for selection: EndpointSelection) -> [URL] {
        switch selection {
        case .global:
            return [globalPrimaryURL] + globalFallbackURLs
        case .cn:
            return [cnPrimaryURL] + cnFallbackURLs
        }
    }

    private func fetchUsagePayload(apiKey: String, selection: EndpointSelection) async throws -> [String: Any] {
        var sawNetworkError = false
        var lastStatusCode: Int?
        var authFailure = false

        for url in usageURLs(for: selection) {
            do {
                var request = URLRequest(url: url)
                request.httpMethod = "GET"
                request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.setValue("application/json", forHTTPHeaderField: "Accept")

                let (data, response) = try await session.data(for: request)
                guard let http = response as? HTTPURLResponse else { continue }

                if http.statusCode == 401 || http.statusCode == 403 {
                    authFailure = true
                    continue
                }

                if !(200...299).contains(http.statusCode) {
                    lastStatusCode = http.statusCode
                    continue
                }

                if let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                    return payload
                }
            } catch {
                sawNetworkError = true
            }
        }

        if authFailure && lastStatusCode == nil && !sawNetworkError {
            throw NSError(domain: "MiniMaxProvider", code: 401, userInfo: [NSLocalizedDescriptionKey: "Session expired. Check your MiniMax API key."])
        }
        if let lastStatusCode {
            throw NSError(domain: "MiniMaxProvider", code: lastStatusCode, userInfo: [NSLocalizedDescriptionKey: "Request failed (HTTP \(lastStatusCode)). Try again later."])
        }
        if sawNetworkError {
            throw NSError(domain: "MiniMaxProvider", code: 0, userInfo: [NSLocalizedDescriptionKey: "Request failed. Check your connection."])
        }
        throw NSError(domain: "MiniMaxProvider", code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not parse usage data."])
    }

    private func parsePayloadShape(_ payload: [String: Any], selection: EndpointSelection) -> ParsedUsage? {
        let data = (payload["data"] as? [String: Any]) ?? payload
        let baseResp = (data["base_resp"] as? [String: Any]) ?? (payload["base_resp"] as? [String: Any])
        let statusCode = Self.intValue(baseResp?["status_code"])
        let statusMessage = Self.stringValue(baseResp?["status_msg"])?.lowercased()

        if let statusCode, statusCode != 0 {
            if statusCode == 1004 || statusMessage?.contains("cookie") == true || statusMessage?.contains("login") == true || statusMessage?.contains("log in") == true {
                return nil
            }
        }

        let modelRemains = (data["model_remains"] as? [[String: Any]])
            ?? (payload["model_remains"] as? [[String: Any]])
            ?? (data["modelRemains"] as? [[String: Any]])
            ?? (payload["modelRemains"] as? [[String: Any]])
            ?? []
        guard !modelRemains.isEmpty else { return nil }

        let chosen = modelRemains.first(where: {
            guard let total = Self.doubleValue($0["current_interval_total_count"] ?? $0["currentIntervalTotalCount"]) else { return false }
            return total > 0
        }) ?? modelRemains[0]

        guard let total = Self.doubleValue(chosen["current_interval_total_count"] ?? chosen["currentIntervalTotalCount"]), total > 0 else {
            return nil
        }

        let usageFieldCount = Self.doubleValue(chosen["current_interval_usage_count"] ?? chosen["currentIntervalUsageCount"])
        let remainingCountCandidates: [Any?] = [
            chosen["current_interval_remaining_count"],
            chosen["currentIntervalRemainingCount"],
            chosen["current_interval_remains_count"],
            chosen["currentIntervalRemainsCount"],
            chosen["current_interval_remain_count"],
            chosen["currentIntervalRemainCount"],
            chosen["remaining_count"],
            chosen["remainingCount"],
            chosen["remains_count"],
            chosen["remainsCount"],
            chosen["remaining"],
            chosen["remains"],
            chosen["left_count"],
            chosen["leftCount"]
        ]
        let remainingCount = Self.firstDoubleValue(remainingCountCandidates)
        let explicitUsed = Self.doubleValue(chosen["current_interval_used_count"] ?? chosen["currentIntervalUsedCount"] ?? chosen["used_count"] ?? chosen["used"])
        let inferredRemaining = remainingCount ?? usageFieldCount
        let used = max(0, min(total, explicitUsed ?? (inferredRemaining.map { total - $0 } ?? -1)))
        guard used >= 0 else { return nil }

        let now = Date()
        let endDate = epochDate(chosen["end_time"] ?? chosen["endTime"])
        let remainsRaw = Self.doubleValue(chosen["remains_time"] ?? chosen["remainsTime"])
        let inferredReset = inferRemainsDate(remainsRaw: remainsRaw, endDate: endDate, now: now)
        let resetAt = endDate ?? inferredReset

        let explicitPlanName = normalizePlanName(
            Self.firstNonEmptyString([
                data["current_subscribe_title"],
                data["plan_name"],
                data["plan"],
                data["current_plan_title"],
                data["combo_title"],
                payload["current_subscribe_title"],
                payload["plan_name"],
                payload["plan"]
            ])
        )
        let inferredPlanName = inferPlanName(totalCount: total, selection: selection)

        return ParsedUsage(planName: explicitPlanName ?? inferredPlanName, used: used, total: total, resetAt: resetAt)
    }

    private func normalizePlanName(_ value: String?) -> String? {
        guard let value else { return nil }
        let compact = value.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines)
        let withoutPrefix = compact.replacingOccurrences(of: #"^minimax\s+coding\s+plan\b[:\-]?\s*"#, with: "", options: [.regularExpression, .caseInsensitive])
        if !withoutPrefix.isEmpty { return withoutPrefix }
        return compact.range(of: "coding plan", options: .caseInsensitive) != nil ? "Coding Plan" : compact
    }

    private func inferPlanName(totalCount: Double, selection: EndpointSelection) -> String? {
        let rounded = Int(totalCount.rounded())
        if selection == .cn {
            return cnPromptLimits[rounded]
        }
        if let direct = globalPromptLimits[rounded] { return direct }
        let prompts = Double(rounded) / modelCallsPerPrompt
        if floor(prompts) == prompts {
            return globalPromptLimits[Int(prompts)]
        }
        return nil
    }

    private func epochDate(_ value: Any?) -> Date? {
        guard let numeric = Self.doubleValue(value) else { return nil }
        return Date(timeIntervalSince1970: abs(numeric) < 10_000_000_000 ? numeric : numeric / 1000)
    }

    private func inferRemainsDate(remainsRaw: Double?, endDate: Date?, now: Date) -> Date? {
        guard let remainsRaw, remainsRaw > 0 else { return nil }
        let asSeconds = remainsRaw * 1000
        let asMilliseconds = remainsRaw

        if let endDate {
            let toEndMs = endDate.timeIntervalSince(now) * 1000
            if toEndMs > 0 {
                let secDelta = abs(asSeconds - toEndMs)
                let msDelta = abs(asMilliseconds - toEndMs)
                return now.addingTimeInterval((secDelta <= msDelta ? asSeconds : asMilliseconds) / 1000)
            }
        }

        let maxExpectedMs = codingPlanWindowMs + codingPlanToleranceMs
        let secondsLooksValid = asSeconds <= maxExpectedMs
        let millisecondsLooksValid = asMilliseconds <= maxExpectedMs
        let chosen: Double
        switch (secondsLooksValid, millisecondsLooksValid) {
        case (true, false):
            chosen = asSeconds
        case (false, true):
            chosen = asMilliseconds
        case (true, true):
            chosen = asSeconds
        default:
            chosen = abs(asSeconds - maxExpectedMs) <= abs(asMilliseconds - maxExpectedMs) ? asSeconds : asMilliseconds
        }
        return now.addingTimeInterval(chosen / 1000)
    }

    private static func stringValue(_ value: Any?) -> String? {
        guard let value = value as? String else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func firstNonEmptyString(_ values: [Any?]) -> String? {
        for value in values {
            if let string = stringValue(value) { return string }
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

    private static func firstDoubleValue(_ values: [Any?]) -> Double? {
        for value in values {
            if let parsed = doubleValue(value) { return parsed }
        }
        return nil
    }

    private static func intValue(_ value: Any?) -> Int? {
        if let value = value as? Int { return value }
        if let value = value as? NSNumber { return value.intValue }
        if let value = value as? String { return Int(value.trimmingCharacters(in: .whitespacesAndNewlines)) }
        return nil
    }

    private enum EndpointSelection {
        case global
        case cn
    }

    private struct ParsedUsage {
        let planName: String?
        let used: Double
        let total: Double
        let resetAt: Date?
    }
}