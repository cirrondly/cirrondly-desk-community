import Foundation

final class AmpProvider: UsageProvider {
    static let identifier = "amp"
    static let displayName = "Amp"
    static let category: ProviderCategory = .usageBased

    private let defaults = UserDefaults.standard
    private let session = URLSession(configuration: .ephemeral)
    private let secretsURL = FileManager.default.homeDirectoryForCurrentUser.appending(path: ".local/share/amp/secrets.json")
    private let secretsKey = "apiKey@https://ampcode.com/"
    private let apiURL = URL(string: "https://ampcode.com/api/internal")!

    var isEnabled: Bool {
        get { defaults.object(forKey: "provider.amp.enabled") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "provider.amp.enabled") }
    }

    var profiles: [ProviderProfile] { [ProviderProfile(name: "Default")] }
    var activeProfile: ProviderProfile? = ProviderProfile(name: "Default")

    func isAvailable() async -> Bool {
        FileManager.default.fileExists(atPath: secretsURL.path)
    }

    func probe() async throws -> ProviderResult {
        guard let apiKey = loadAPIKey() else {
            return .unavailable(
                identifier: Self.identifier,
                displayName: Self.displayName,
                category: Self.category,
                warning: "Amp not installed. Install Amp Code to get started."
            )
        }

        let (data, response) = try await fetchBalanceInfo(apiKey: apiKey)
        guard (200...299).contains(response.statusCode) else {
            if response.statusCode == 401 || response.statusCode == 403 {
                return .unavailable(
                    identifier: Self.identifier,
                    displayName: Self.displayName,
                    category: Self.category,
                    warning: "Session expired. Re-authenticate in Amp Code."
                )
            }

            let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            let detail = Self.stringValue((payload?["error"] as? [String: Any])?["message"])
            throw NSError(
                domain: "AmpProvider",
                code: response.statusCode,
                userInfo: [NSLocalizedDescriptionKey: detail ?? "Request failed (HTTP \(response.statusCode)). Try again later."]
            )
        }

        guard let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let result = payload["result"] as? [String: Any],
              let displayText = Self.stringValue(result["displayText"]),
              payload["ok"] as? Bool == true else {
            throw NSError(domain: "AmpProvider", code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not parse usage data."])
        }

        let balance = parseBalanceText(displayText)
        let plan = balance.total == nil && balance.credits != nil ? "Credits" : "Free"
        var windows: [Window] = []
        var warnings: [ProviderWarning] = []

        if let total = balance.total, let remaining = balance.remaining, total > 0 {
            let used = max(0, total - remaining)
            let resetAt: Date?
            if used > 0, balance.hourlyRate > 0 {
                resetAt = Date().addingTimeInterval((used / balance.hourlyRate) * 3600)
            } else {
                resetAt = nil
            }

            windows.append(
                Window(
                    kind: .custom("Free"),
                    used: used,
                    limit: total,
                    unit: .dollars,
                    percentage: min(100, max(0, (used / total) * 100)),
                    resetAt: resetAt
                )
            )
        }

        if let bonusPct = balance.bonusPct, let bonusDays = balance.bonusDays {
            warnings.append(ProviderWarning(level: .info, message: "+\(bonusPct)% bonus for \(bonusDays)d."))
        }

        if let credits = balance.credits {
            warnings.append(ProviderWarning(level: .info, message: String(format: "Credits remaining: $%.2f", credits)))
        }

        if windows.isEmpty {
            warnings.append(ProviderWarning(level: .info, message: "Amp returned no quota window data."))
        }

        return ProviderResult(
            identifier: Self.identifier,
            displayName: Self.displayName,
            category: Self.category,
            profile: plan,
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
        guard let data = try? Data(contentsOf: secretsURL),
              let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return Self.stringValue(payload[secretsKey])
    }

    private func fetchBalanceInfo(apiKey: String) async throws -> (Data, HTTPURLResponse) {
        var request = URLRequest(url: apiURL)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["method": "userDisplayBalanceInfo", "params": [:]])

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw NSError(domain: "AmpProvider", code: 0, userInfo: [NSLocalizedDescriptionKey: "Request failed. Check your connection."])
        }
        return (data, http)
    }

    private func parseBalanceText(_ text: String) -> BalanceInfo {
        var result = BalanceInfo()

        if let match = firstMatch(in: text, pattern: #"\$([0-9][0-9,]*(?:\.[0-9]+)?)\/\$([0-9][0-9,]*(?:\.[0-9]+)?) remaining"#),
           match.count >= 3,
           let remaining = parseMoney(match[1]),
           let total = parseMoney(match[2]) {
            result.remaining = remaining
            result.total = total
        }

        if let match = firstMatch(in: text, pattern: #"replenishes \+\$([0-9][0-9,]*(?:\.[0-9]+)?)\/hour"#),
           match.count >= 2,
           let rate = parseMoney(match[1]) {
            result.hourlyRate = rate
        }

        if let match = firstMatch(in: text, pattern: #"\+(\d+)% bonus for (\d+) more days?"#),
           match.count >= 3,
           let pct = Int(match[1]),
           let days = Int(match[2]) {
            result.bonusPct = pct
            result.bonusDays = days
        }

        if let match = firstMatch(in: text, pattern: #"Individual credits: \$([0-9][0-9,]*(?:\.[0-9]+)?) remaining"#),
           match.count >= 2,
           let credits = parseMoney(match[1]) {
            result.credits = credits
        }

        return result
    }

    private func firstMatch(in text: String, pattern: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else {
            return nil
        }

        return (0..<match.numberOfRanges).compactMap { index in
            guard let range = Range(match.range(at: index), in: text) else { return nil }
            return String(text[range])
        }
    }

    private func parseMoney(_ value: String) -> Double? {
        Double(value.replacingOccurrences(of: ",", with: ""))
    }

    private static func stringValue(_ value: Any?) -> String? {
        guard let value = value as? String else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private struct BalanceInfo {
        var remaining: Double?
        var total: Double?
        var hourlyRate: Double = 0
        var bonusPct: Int?
        var bonusDays: Int?
        var credits: Double?
    }
}