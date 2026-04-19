import Foundation

final class KimiProvider: UsageProvider {
    static let identifier = "kimi"
    static let displayName = "Kimi"
    static let category: ProviderCategory = .usageBased

    private let defaults = UserDefaults.standard
    private let session = URLSession(configuration: .ephemeral)
    private let credentialsURL = FileManager.default.homeDirectoryForCurrentUser.appending(path: ".kimi/credentials/kimi-code.json")
    private let usageURL = URL(string: "https://api.kimi.com/coding/v1/usages")!
    private let refreshURL = URL(string: "https://auth.kimi.com/api/oauth/token")!
    private let clientID = "17e5f671-d194-4dfb-9706-5516cb48c098"
    private let refreshBuffer: TimeInterval = 5 * 60

    var isEnabled: Bool {
        get { defaults.object(forKey: "provider.kimi.enabled") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "provider.kimi.enabled") }
    }

    var profiles: [ProviderProfile] { [ProviderProfile(name: "Default")] }
    var activeProfile: ProviderProfile? = ProviderProfile(name: "Default")

    func isAvailable() async -> Bool {
        FileManager.default.fileExists(atPath: credentialsURL.path)
    }

    func probe() async throws -> ProviderResult {
        guard var credentials = loadCredentials() else {
            return .unavailable(
                identifier: Self.identifier,
                displayName: Self.displayName,
                category: Self.category,
                warning: "Not logged in. Run kimi login to authenticate."
            )
        }

        var accessToken = credentials.accessToken
        if needsRefresh(credentials) {
            if let refreshed = try await refreshToken(&credentials) {
                accessToken = refreshed
            } else if accessToken == nil {
                return .unavailable(
                    identifier: Self.identifier,
                    displayName: Self.displayName,
                    category: Self.category,
                    warning: "Not logged in. Run kimi login to authenticate."
                )
            }
        }

        guard let currentToken = accessToken else {
            return .unavailable(
                identifier: Self.identifier,
                displayName: Self.displayName,
                category: Self.category,
                warning: "Not logged in. Run kimi login to authenticate."
            )
        }

        let payload = try await fetchUsage(accessToken: currentToken, credentials: &credentials)
        let candidates = collectCandidates(payload)
        let sessionCandidate = pickSessionCandidate(candidates)
        let weeklyCandidate = pickWeeklyCandidate(payload: payload, candidates: candidates, sessionCandidate: sessionCandidate)

        var windows: [Window] = []
        if let sessionCandidate,
           let window = makePercentWindow(kind: .fiveHour, from: sessionCandidate.quota) {
            windows.append(window)
        }
        if let weeklyCandidate,
           !sameQuota(lhs: weeklyCandidate, rhs: sessionCandidate),
           let window = makePercentWindow(kind: .weekly, from: weeklyCandidate.quota) {
            windows.append(window)
        }

        let warnings = windows.isEmpty ? [ProviderWarning(level: .info, message: "Kimi returned no usage data.")] : []

        return ProviderResult(
            identifier: Self.identifier,
            displayName: Self.displayName,
            category: Self.category,
            profile: parsePlanLabel(payload) ?? activeProfile?.name ?? "Default",
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

    private func loadCredentials() -> Credentials? {
        guard let data = try? Data(contentsOf: credentialsURL),
              let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        let accessToken = Self.stringValue(payload["access_token"])
        let refreshToken = Self.stringValue(payload["refresh_token"])
        guard accessToken != nil || refreshToken != nil else { return nil }
        return Credentials(
            accessToken: accessToken,
            refreshToken: refreshToken,
            expiresAt: Self.doubleValue(payload["expires_at"]),
            scope: Self.stringValue(payload["scope"]),
            tokenType: Self.stringValue(payload["token_type"])
        )
    }

    private func saveCredentials(_ credentials: Credentials) {
        var payload: [String: Any] = [:]
        if let accessToken = credentials.accessToken { payload["access_token"] = accessToken }
        if let refreshToken = credentials.refreshToken { payload["refresh_token"] = refreshToken }
        if let expiresAt = credentials.expiresAt { payload["expires_at"] = expiresAt }
        if let scope = credentials.scope { payload["scope"] = scope }
        if let tokenType = credentials.tokenType { payload["token_type"] = tokenType }
        guard JSONSerialization.isValidJSONObject(payload),
              let data = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys]) else {
            return
        }
        try? FileManager.default.createDirectory(at: credentialsURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: credentialsURL)
    }

    private func needsRefresh(_ credentials: Credentials) -> Bool {
        guard credentials.accessToken != nil else { return true }
        guard let expiresAt = credentials.expiresAt else { return true }
        return Date().timeIntervalSince1970 + refreshBuffer >= expiresAt
    }

    private func refreshToken(_ credentials: inout Credentials) async throws -> String? {
        guard let refreshTokenValue = credentials.refreshToken else { return nil }

        var request = URLRequest(url: refreshURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = "client_id=\(Self.urlEncode(clientID))&grant_type=refresh_token&refresh_token=\(Self.urlEncode(refreshTokenValue))".data(using: .utf8)

        let (data, response) = try await session.data(for: request)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 500
        if statusCode == 401 || statusCode == 403 {
            throw NSError(domain: "KimiProvider", code: statusCode, userInfo: [NSLocalizedDescriptionKey: "Session expired. Run kimi login to authenticate."])
        }
        guard (200...299).contains(statusCode),
              let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let accessToken = Self.stringValue(payload["access_token"]) else {
            return nil
        }

        credentials.accessToken = accessToken
        if let refreshToken = Self.stringValue(payload["refresh_token"]) { credentials.refreshToken = refreshToken }
        if let expiresIn = Self.doubleValue(payload["expires_in"]) {
            credentials.expiresAt = Date().timeIntervalSince1970 + expiresIn
        }
        if let scope = Self.stringValue(payload["scope"]) { credentials.scope = scope }
        if let tokenType = Self.stringValue(payload["token_type"]) { credentials.tokenType = tokenType }
        saveCredentials(credentials)
        return accessToken
    }

    private func fetchUsage(accessToken: String, credentials: inout Credentials) async throws -> [String: Any] {
        var currentToken = accessToken
        var response = try await usageResponse(accessToken: currentToken)
        if response.http.statusCode == 401 || response.http.statusCode == 403,
           let refreshed = try await refreshToken(&credentials) {
            currentToken = refreshed
            response = try await usageResponse(accessToken: currentToken)
        }

        if response.http.statusCode == 401 || response.http.statusCode == 403 {
            throw NSError(domain: "KimiProvider", code: response.http.statusCode, userInfo: [NSLocalizedDescriptionKey: "Token expired. Run kimi login to authenticate."])
        }
        guard (200...299).contains(response.http.statusCode),
              let payload = try? JSONSerialization.jsonObject(with: response.data) as? [String: Any] else {
            throw NSError(domain: "KimiProvider", code: response.http.statusCode, userInfo: [NSLocalizedDescriptionKey: "Usage response invalid. Try again later."])
        }
        return payload
    }

    private func usageResponse(accessToken: String) async throws -> (data: Data, http: HTTPURLResponse) {
        var request = URLRequest(url: usageURL)
        request.httpMethod = "GET"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("OpenUsage", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw NSError(domain: "KimiProvider", code: 0, userInfo: [NSLocalizedDescriptionKey: "Usage request failed. Check your connection."])
        }
        return (data, http)
    }

    private func collectCandidates(_ payload: [String: Any]) -> [Candidate] {
        let limits = payload["limits"] as? [Any] ?? []
        return limits.compactMap { item in
            guard let row = item as? [String: Any] else { return nil }
            let detail = (row["detail"] as? [String: Any]) ?? row
            guard let quota = parseQuota(detail) else { return nil }
            return Candidate(quota: quota, periodMs: parseWindowPeriodMs(row["window"]))
        }
    }

    private func pickSessionCandidate(_ candidates: [Candidate]) -> Candidate? {
        candidates.sorted { lhs, rhs in
            switch (lhs.periodMs, rhs.periodMs) {
            case let (left?, right?):
                return left < right
            case (_?, nil):
                return true
            case (nil, _?):
                return false
            default:
                return false
            }
        }.first
    }

    private func pickWeeklyCandidate(payload: [String: Any], candidates: [Candidate], sessionCandidate: Candidate?) -> Candidate? {
        if let usage = payload["usage"] as? [String: Any], let quota = parseQuota(usage) {
            return Candidate(quota: quota, periodMs: nil)
        }

        return candidates
            .filter { candidate in !sameQuota(lhs: candidate, rhs: sessionCandidate) }
            .max { lhs, rhs in (lhs.periodMs ?? -1) < (rhs.periodMs ?? -1) }
    }

    private func parseQuota(_ payload: [String: Any]) -> Quota? {
        guard let limit = Self.doubleValue(payload["limit"]), limit > 0 else { return nil }
        var used = Self.doubleValue(payload["used"])
        if used == nil, let remaining = Self.doubleValue(payload["remaining"]) {
            used = limit - remaining
        }
        guard let used else { return nil }

        return Quota(
            used: max(0, used),
            limit: limit,
            resetAt: Self.dateValue(payload["resetTime"] ?? payload["reset_at"] ?? payload["resetAt"] ?? payload["reset_time"])
        )
    }

    private func parseWindowPeriodMs(_ value: Any?) -> TimeInterval? {
        guard let payload = value as? [String: Any],
              let duration = Self.doubleValue(payload["duration"]),
              duration > 0 else {
            return nil
        }

        let unit = (Self.stringValue(payload["timeUnit"] ?? payload["time_unit"]) ?? "").uppercased()
        if unit.contains("MINUTE") { return duration * 60 * 1000 }
        if unit.contains("HOUR") { return duration * 60 * 60 * 1000 }
        if unit.contains("DAY") { return duration * 24 * 60 * 60 * 1000 }
        if unit.contains("SECOND") { return duration * 1000 }
        return nil
    }

    private func makePercentWindow(kind: WindowKind, from quota: Quota) -> Window? {
        guard quota.limit > 0 else { return nil }
        let usedPercent = min(100, max(0, (quota.used / quota.limit) * 100))
        return Window(kind: kind, used: usedPercent, limit: 100, unit: .requests, percentage: usedPercent, resetAt: quota.resetAt)
    }

    private func parsePlanLabel(_ payload: [String: Any]) -> String? {
        guard let user = payload["user"] as? [String: Any],
              let membership = user["membership"] as? [String: Any],
              let level = Self.stringValue(membership["level"]) else {
            return nil
        }

        let cleaned = level.replacingOccurrences(of: "LEVEL_", with: "").replacingOccurrences(of: "_", with: " ").lowercased()
        return cleaned.split(separator: " ").map { $0.capitalized }.joined(separator: " ")
    }

    private func sameQuota(lhs: Candidate?, rhs: Candidate?) -> Bool {
        guard let lhs, let rhs else { return false }
        return lhs.quota.used == rhs.quota.used && lhs.quota.limit == rhs.quota.limit && lhs.quota.resetAt == rhs.quota.resetAt
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

    private static func urlEncode(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? value
    }

    private struct Credentials {
        var accessToken: String?
        var refreshToken: String?
        var expiresAt: TimeInterval?
        var scope: String?
        var tokenType: String?
    }

    private struct Quota {
        let used: Double
        let limit: Double
        let resetAt: Date?
    }

    private struct Candidate {
        let quota: Quota
        let periodMs: TimeInterval?
    }
}