import Foundation

final class WindsurfProvider: UsageProvider {
    static let identifier = "windsurf"
    static let displayName = "Windsurf"
    static let category: ProviderCategory = .usageBased

    private let defaults = UserDefaults.standard
    private let sqlite = SQLiteReader()
    private let session = URLSession(configuration: .ephemeral)
    private let cloudURL = URL(string: "https://server.self-serve.windsurf.com/exa.seat_management_pb.SeatManagementService/GetUserStatus")!
    private let compatVersion = "1.108.2"
    private let dayInterval: TimeInterval = 24 * 60 * 60
    private let weekInterval: TimeInterval = 7 * 24 * 60 * 60

    var isEnabled: Bool {
        get { defaults.object(forKey: "provider.windsurf.enabled") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "provider.windsurf.enabled") }
    }

    var profiles: [ProviderProfile] { [ProviderProfile(name: "Default")] }
    var activeProfile: ProviderProfile? = ProviderProfile(name: "Default")

    func isAvailable() async -> Bool {
        variants.contains { FileManager.default.fileExists(atPath: $0.stateDB.path) }
    }

    func probe() async throws -> ProviderResult {
        var sawAPIKey = false
        var sawAuthFailure = false

        for variant in variants {
            guard let apiKey = loadAPIKey(for: variant) else { continue }
            sawAPIKey = true

            do {
                guard let status = try await fetchUserStatus(apiKey: apiKey, variant: variant) else { continue }
                return try buildResult(from: status, variant: variant)
            } catch let error as WindsurfError {
                if case .auth = error {
                    sawAuthFailure = true
                    continue
                }
                if case .quotaUnavailable = error {
                    continue
                }
                throw error
            }
        }

        let message: String
        if sawAuthFailure {
            message = "Start Windsurf or sign in and try again."
        } else if sawAPIKey {
            message = "Windsurf quota data unavailable. Try again later."
        } else {
            message = "Start Windsurf or sign in and try again."
        }

        return ProviderResult.unavailable(identifier: Self.identifier, displayName: Self.displayName, category: Self.category, warning: message)
    }

    private var variants: [WindsurfVariant] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return [
            WindsurfVariant(marker: "windsurf", ideName: "windsurf", stateDB: home.appending(path: "Library/Application Support/Windsurf/User/globalStorage/state.vscdb")),
            WindsurfVariant(marker: "windsurf-next", ideName: "windsurf-next", stateDB: home.appending(path: "Library/Application Support/Windsurf - Next/User/globalStorage/state.vscdb"))
        ]
    }

    private func loadAPIKey(for variant: WindsurfVariant) -> String? {
        guard let row = try? sqlite.query(databaseURL: variant.stateDB, sql: "SELECT value FROM ItemTable WHERE key = 'windsurfAuthStatus' LIMIT 1").first,
              let rawValue = row["value"],
              let data = rawValue.data(using: .utf8),
              let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        return stringValue(payload["apiKey"])
    }

    private func fetchUserStatus(apiKey: String, variant: WindsurfVariant) async throws -> [String: Any]? {
        var request = URLRequest(url: cloudURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("1", forHTTPHeaderField: "Connect-Protocol-Version")

        let body: [String: Any] = [
            "metadata": [
                "apiKey": apiKey,
                "ideName": variant.ideName,
                "ideVersion": compatVersion,
                "extensionName": variant.ideName,
                "extensionVersion": compatVersion,
                "locale": "en"
            ]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { return nil }
        if http.statusCode == 401 || http.statusCode == 403 {
            throw WindsurfError.auth
        }
        guard (200...299).contains(http.statusCode),
              let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return payload["userStatus"] as? [String: Any]
    }

    private func buildResult(from userStatus: [String: Any], variant: WindsurfVariant) throws -> ProviderResult {
        let planStatus = userStatus["planStatus"] as? [String: Any] ?? [:]
        guard let dailyRemaining = numberValue(planStatus["dailyQuotaRemainingPercent"]),
              let weeklyRemaining = numberValue(planStatus["weeklyQuotaRemainingPercent"]),
              let dailyResetUnix = numberValue(planStatus["dailyQuotaResetAtUnix"]),
              let weeklyResetUnix = numberValue(planStatus["weeklyQuotaResetAtUnix"]) else {
            throw WindsurfError.quotaUnavailable
        }

        let dailyReset = Date(timeIntervalSince1970: dailyResetUnix)
        let weeklyReset = Date(timeIntervalSince1970: weeklyResetUnix)
        let planInfo = planStatus["planInfo"] as? [String: Any]
        let planName = stringValue(planInfo?["planName"]) ?? "Unknown"

        let extraBalance = numberValue(planStatus["overageBalanceMicros"]).map {
            String(format: "$%.2f", max(0, $0) / 1_000_000)
        }

        return ProviderResult(
            identifier: Self.identifier,
            displayName: Self.displayName,
            category: Self.category,
            profile: planName,
            windows: [
                Window(kind: .custom("Daily quota"), used: 100 - dailyRemaining, limit: 100, unit: .requests, percentage: min(100, max(0, 100 - dailyRemaining)), resetAt: dailyReset),
                Window(kind: .weekly, used: 100 - weeklyRemaining, limit: 100, unit: .requests, percentage: min(100, max(0, 100 - weeklyRemaining)), resetAt: weeklyReset)
            ],
            today: .zero,
            burnRate: nil,
            dailyHeatmap: [],
            models: [],
            source: .api,
            freshness: Date(),
            warnings: [extraBalance.map { ProviderWarning(level: .info, message: "Extra usage balance: \($0)") }].compactMap { $0 }
        )
    }

    private func numberValue(_ value: Any?) -> Double? {
        if let double = value as? Double, double.isFinite { return double }
        if let int = value as? Int { return Double(int) }
        if let string = value as? String, let double = Double(string), double.isFinite { return double }
        return nil
    }
}

private struct WindsurfVariant {
    let marker: String
    let ideName: String
    let stateDB: URL
}

private enum WindsurfError: Error {
    case auth
    case quotaUnavailable
}