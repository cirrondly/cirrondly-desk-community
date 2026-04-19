import Foundation

final class SyntheticProvider: UsageProvider {
    static let identifier = "synthetic"
    static let displayName = "Synthetic"
    static let category: ProviderCategory = .usageBased

    private let defaults = UserDefaults.standard
    private let session = URLSession(configuration: .ephemeral)
    private let apiURL = URL(string: "https://api.synthetic.new/v2/quotas")!
    private let providerNames = ["synthetic", "synthetic.new", "syn"]
    private let defaultPiAgentDirectory = FileManager.default.homeDirectoryForCurrentUser.appending(path: ".pi/agent", directoryHint: .isDirectory)
    private let factorySettingsURL = FileManager.default.homeDirectoryForCurrentUser.appending(path: ".factory/settings.json")
    private let openCodeAuthURL = FileManager.default.homeDirectoryForCurrentUser.appending(path: ".local/share/opencode/auth.json")

    var isEnabled: Bool {
        get { defaults.object(forKey: "provider.synthetic.enabled") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "provider.synthetic.enabled") }
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
                warning: "Synthetic API key not found. Set SYNTHETIC_API_KEY or add key to ~/.pi/agent/auth.json."
            )
        }

        let (data, response) = try await requestQuotas(apiKey: apiKey)
        if response.statusCode == 401 || response.statusCode == 403 {
            return .unavailable(
                identifier: Self.identifier,
                displayName: Self.displayName,
                category: Self.category,
                warning: "API key invalid or expired. Check your Synthetic API key."
            )
        }
        guard (200...299).contains(response.statusCode),
              let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            let message = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]).flatMap { normalizeApiErrorMessage($0, statusCode: response.statusCode) }
            throw NSError(domain: "SyntheticProvider", code: response.statusCode, userInfo: [NSLocalizedDescriptionKey: message ?? "Request failed. Check your connection."])
        }

        let onV3 = hasRollingLimit(payload["rollingFiveHourLimit"]) || hasWeeklyLimit(payload["weeklyTokenLimit"])
        var windows: [Window] = []
        var warnings: [ProviderWarning] = []

        if let rolling = payload["rollingFiveHourLimit"] as? [String: Any],
           let limit = Self.doubleValue(rolling["max"]),
           let remaining = Self.doubleValue(rolling["remaining"]),
           limit > 0 {
            let used = Swift.max(0, limit - remaining)
            windows.append(makeWindow(kind: .fiveHour, used: used, limit: limit, resetAt: nil, unit: .requests))
            if rolling["limited"] as? Bool == true {
                warnings.append(ProviderWarning(level: .critical, message: "Synthetic is currently rate limited."))
            }
        }

        if let weekly = payload["weeklyTokenLimit"] as? [String: Any],
           let percentRemaining = Self.doubleValue(weekly["percentRemaining"]) {
            let used = max(0, round(100 - percentRemaining))
            windows.append(Window(kind: .weekly, used: used, limit: 100, unit: .requests, percentage: used, resetAt: nil))
        }

        if !onV3,
           let subscription = payload["subscription"] as? [String: Any],
           let limit = Self.doubleValue(subscription["limit"]),
           limit > 0 {
            let used = Self.doubleValue(subscription["requests"]) ?? 0
            windows.append(makeWindow(kind: .custom("Subscription"), used: used, limit: limit, resetAt: Self.dateValue(subscription["renewsAt"]), unit: .requests))
        }

        if !onV3,
           let freeToolCalls = payload["freeToolCalls"] as? [String: Any],
           let limit = Self.doubleValue(freeToolCalls["limit"]),
           limit > 0 {
            let used = Self.doubleValue(freeToolCalls["requests"]) ?? 0
            windows.append(makeWindow(kind: .custom("Free Tool Calls"), used: used, limit: limit, resetAt: Self.dateValue(freeToolCalls["renewsAt"]), unit: .requests))
        }

        if let search = payload["search"] as? [String: Any],
           let hourly = search["hourly"] as? [String: Any],
           let limit = Self.doubleValue(hourly["limit"]),
           limit > 0 {
            let used = Self.doubleValue(hourly["requests"]) ?? 0
            windows.append(makeWindow(kind: .custom("Search"), used: used, limit: limit, resetAt: Self.dateValue(hourly["renewsAt"]), unit: .requests))
        }

        if windows.isEmpty {
            warnings.append(ProviderWarning(level: .info, message: "Synthetic returned no quota data."))
        }

        return ProviderResult(
            identifier: Self.identifier,
            displayName: Self.displayName,
            category: Self.category,
            profile: activeProfile?.name ?? "Default",
            windows: windows,
            today: .zero,
            burnRate: nil,
            dailyHeatmap: [],
            models: [],
            source: .api,
            freshness: Date(),
            warnings: warnings
        )
    }

    private func loadAPIKey() -> String? {
        if let auth = tryReadJSON(at: piAgentDirectory().appending(path: "auth.json")),
           let key = findKeyInProviderMap(auth) {
            return key
        }

        if let models = tryReadJSON(at: piAgentDirectory().appending(path: "models.json")),
           let providers = models["providers"] as? [String: Any],
           let key = findKeyInProviderMap(providers) {
            return key
        }

        if let settings = tryReadJSON(at: factorySettingsURL),
           let customModels = settings["customModels"] as? [[String: Any]] {
            for model in customModels {
                guard let baseURL = Self.stringValue(model["baseUrl"]), baseURL.contains("synthetic.new") else { continue }
                if let key = Self.stringValue(model["apiKey"]) { return key }
            }
        }

        if let auth = tryReadJSON(at: openCodeAuthURL),
           let key = findKeyInProviderMap(auth) {
            return key
        }

        if let envKey = ProcessInfo.processInfo.environment["SYNTHETIC_API_KEY"]?.trimmingCharacters(in: .whitespacesAndNewlines), !envKey.isEmpty {
            return envKey
        }

        return nil
    }

    private func requestQuotas(apiKey: String) async throws -> (Data, HTTPURLResponse) {
        var request = URLRequest(url: apiURL)
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw NSError(domain: "SyntheticProvider", code: 0, userInfo: [NSLocalizedDescriptionKey: "Request failed. Check your connection."])
        }
        return (data, http)
    }

    private func piAgentDirectory() -> URL {
        if let value = ProcessInfo.processInfo.environment["PI_CODING_AGENT_DIR"]?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty {
            return URL(fileURLWithPath: NSString(string: value).expandingTildeInPath, isDirectory: true)
        }
        return defaultPiAgentDirectory
    }

    private func tryReadJSON(at url: URL) -> [String: Any]? {
        guard let data = try? Data(contentsOf: url),
              let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return payload
    }

    private func findKeyInProviderMap(_ payload: [String: Any]) -> String? {
        for name in providerNames {
            guard let entry = payload[name] else { continue }
            if let entry = entry as? [String: Any] {
                if let key = Self.stringValue(entry["key"]) { return key }
                if let key = Self.stringValue(entry["apiKey"]) { return key }
            }
        }
        return nil
    }

    private func hasRollingLimit(_ value: Any?) -> Bool {
        guard let payload = value as? [String: Any] else { return false }
        return Self.doubleValue(payload["max"]) != nil && Self.doubleValue(payload["remaining"]) != nil
    }

    private func hasWeeklyLimit(_ value: Any?) -> Bool {
        guard let payload = value as? [String: Any] else { return false }
        return Self.doubleValue(payload["percentRemaining"]) != nil
    }

    private func normalizeApiErrorMessage(_ payload: [String: Any], statusCode: Int) -> String {
        if let error = Self.stringValue(payload["error"]) { return error }
        if let error = payload["error"] as? [String: Any], let message = Self.stringValue(error["message"]) { return message }
        if let message = Self.stringValue(payload["message"]) { return message }
        return "Request failed (HTTP \(statusCode))."
    }

    private func makeWindow(kind: WindowKind, used: Double, limit: Double, resetAt: Date?, unit: UsageUnit) -> Window {
        let percentage = limit > 0 ? min(100, max(0, (used / limit) * 100)) : 0
        return Window(kind: kind, used: used, limit: limit, unit: unit, percentage: percentage, resetAt: resetAt)
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

    private static func dateValue(_ value: Any?) -> Date? {
        if let value = value as? String { return TimeHelpers.parseISODate(value) }
        guard let numeric = doubleValue(value) else { return nil }
        return Date(timeIntervalSince1970: numeric > 10_000_000_000 ? numeric / 1000 : numeric)
    }
}