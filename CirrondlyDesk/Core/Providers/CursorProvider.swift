import Foundation

final class CursorProvider: UsageProvider {
    static let identifier = "cursor"
    static let displayName = "Cursor"
    static let category: ProviderCategory = .usageBased

    private let defaults = UserDefaults.standard
    private let sqlite = SQLiteReader()
    private let keychainService: KeychainService
    private let session = URLSession(configuration: .ephemeral)
    private let baseURL = URL(string: "https://api2.cursor.sh")!
    private let refreshURL = URL(string: "https://api2.cursor.sh/oauth/token")!
    private let restUsageURL = URL(string: "https://cursor.com/api/usage")!
    private let stripeURL = URL(string: "https://cursor.com/api/auth/stripe")!
    private let clientID = "KbZUR41cY7W6zRSdpSUJ7I7mLYBKOCmB"
    private let refreshBuffer: TimeInterval = 5 * 60

    init(keychainService: KeychainService) {
        self.keychainService = keychainService
    }

    var isEnabled: Bool {
        get { defaults.object(forKey: "provider.cursor.enabled") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "provider.cursor.enabled") }
    }

    var profiles: [ProviderProfile] { [ProviderProfile(name: "Default")] }
    var activeProfile: ProviderProfile? = ProviderProfile(name: "Default")

    func isAvailable() async -> Bool {
        FileManager.default.fileExists(atPath: dbURL.path)
    }

    func probe() async throws -> ProviderResult {
        let metadata = loadMetadata()
        var authState = loadAuthState(sqliteMembershipType: metadata.membershipType)
        guard authState.accessToken != nil || authState.refreshToken != nil else {
            return ProviderResult.unavailable(identifier: Self.identifier, displayName: Self.displayName, category: Self.category, warning: "Not logged in. Sign in via Cursor or run agent login.")
        }

        if needsRefresh(authState.accessToken) {
            if let refreshed = try await refreshToken(refreshTokenValue: authState.refreshToken, source: authState.source) {
                authState.accessToken = refreshed
            } else if authState.accessToken == nil {
                return ProviderResult.unavailable(identifier: Self.identifier, displayName: Self.displayName, category: Self.category, warning: "Not logged in. Sign in via Cursor or run agent login.")
            }
        }

        guard let accessToken = authState.accessToken else {
            return ProviderResult.unavailable(identifier: Self.identifier, displayName: Self.displayName, category: Self.category, warning: "Not logged in. Sign in via Cursor or run agent login.")
        }

        let usageResponse = try await connectPost(path: "/aiserver.v1.DashboardService/GetCurrentPeriodUsage", accessToken: accessToken, refreshTokenValue: authState.refreshToken, source: authState.source)
        guard let usage = usageResponse.payload else {
            return ProviderResult.unavailable(identifier: Self.identifier, displayName: Self.displayName, category: Self.category, warning: "Usage response invalid. Try again later.")
        }

        let planInfoResponse = try? await connectPost(path: "/aiserver.v1.DashboardService/GetPlanInfo", accessToken: accessToken, refreshTokenValue: authState.refreshToken, source: authState.source)
        let planName = stringValue((planInfoResponse?.payload?["planInfo"] as? [String: Any])?["planName"])
        let normalizedPlan = planName?.lowercased() ?? ""

        if usage["enabled"] as? Bool == false {
            return ProviderResult.unavailable(identifier: Self.identifier, displayName: Self.displayName, category: Self.category, warning: "No active Cursor subscription.")
        }

        let fallback = try await requestBasedFallbackIfNeeded(usage: usage, accessToken: accessToken, planName: planName)
        if let fallback { return fallback(metadata.email ?? planName ?? activeProfile?.name ?? "Default") }

        guard let planUsage = usage["planUsage"] as? [String: Any] else {
            return ProviderResult.unavailable(identifier: Self.identifier, displayName: Self.displayName, category: Self.category, warning: "Cursor usage data unavailable. Try again later.")
        }

        let creditGrants = try? await connectPost(path: "/aiserver.v1.DashboardService/GetCreditGrantsBalance", accessToken: accessToken, refreshTokenValue: authState.refreshToken, source: authState.source).payload
        let stripeBalanceCents = try? await fetchStripeBalance(accessToken: accessToken)

        var windows: [Window] = []
        if let creditsWindow = makeCreditsWindow(creditGrants: creditGrants, stripeBalanceCents: stripeBalanceCents) {
            windows.append(creditsWindow)
        }

        let billingCycleEnd = dateFromMilliseconds(usage["billingCycleEnd"])
        let isTeamAccount = normalizedPlan == "team"
            || stringValue((usage["spendLimitUsage"] as? [String: Any])?["limitType"]) == "team"
            || numberValue((usage["spendLimitUsage"] as? [String: Any])?["pooledLimit"]) != nil

        if let totalUsageWindow = makeTotalUsageWindow(planUsage: planUsage, resetAt: billingCycleEnd, isTeamAccount: isTeamAccount) {
            windows.append(totalUsageWindow)
        }
        if let auto = makePercentWindow(label: "Auto usage", value: planUsage["autoPercentUsed"], resetAt: billingCycleEnd) {
            windows.append(auto)
        }
        if let api = makePercentWindow(label: "API usage", value: planUsage["apiPercentUsed"], resetAt: billingCycleEnd) {
            windows.append(api)
        }
        if let onDemand = makeOnDemandWindow(spendLimitUsage: usage["spendLimitUsage"] as? [String: Any], resetAt: billingCycleEnd) {
            windows.append(onDemand)
        }

        return ProviderResult(
            identifier: Self.identifier,
            displayName: Self.displayName,
            category: Self.category,
            profile: metadata.email ?? planName ?? activeProfile?.name ?? "Default",
            windows: windows,
            today: .zero,
            burnRate: nil,
            dailyHeatmap: [],
            models: [],
            source: .api,
            freshness: Date(),
            warnings: windows.isEmpty ? [ProviderWarning(level: .info, message: "Cursor returned no quota data for this account.")] : []
        )
    }

    private var dbURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library/Application Support/Cursor/User/globalStorage/state.vscdb")
    }

    private func loadMetadata() -> CursorMetadata {
        let rows = (try? sqlite.query(databaseURL: dbURL, sql: "SELECT key, value FROM ItemTable WHERE key IN ('cursorAuth/stripeMembershipType', 'cursorAuth/cachedEmail')")) ?? []
        let membershipType = rows.first(where: { $0["key"] == "cursorAuth/stripeMembershipType" })?["value"]?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let email = rows.first(where: { $0["key"] == "cursorAuth/cachedEmail" })?["value"]
        return CursorMetadata(email: email, membershipType: membershipType)
    }

    private func loadAuthState(sqliteMembershipType: String?) -> CursorAuthState {
        let sqliteAccessToken = readStateValue("cursorAuth/accessToken")
        let sqliteRefreshToken = readStateValue("cursorAuth/refreshToken")
        let keychainAccessToken = keychainService.readAny(service: "cursor-access-token")
        let keychainRefreshToken = keychainService.readAny(service: "cursor-refresh-token")

        let sqliteSubject = tokenSubject(sqliteAccessToken)
        let keychainSubject = tokenSubject(keychainAccessToken)
        let hasDifferentSubjects = sqliteSubject != nil && keychainSubject != nil && sqliteSubject != keychainSubject
        let sqliteLooksFree = sqliteMembershipType == "free"

        if sqliteAccessToken != nil || sqliteRefreshToken != nil {
            if (keychainAccessToken != nil || keychainRefreshToken != nil) && sqliteLooksFree && hasDifferentSubjects {
                return CursorAuthState(accessToken: keychainAccessToken, refreshToken: keychainRefreshToken, source: .keychain)
            }
            return CursorAuthState(accessToken: sqliteAccessToken, refreshToken: sqliteRefreshToken, source: .sqlite)
        }

        if keychainAccessToken != nil || keychainRefreshToken != nil {
            return CursorAuthState(accessToken: keychainAccessToken, refreshToken: keychainRefreshToken, source: .keychain)
        }

        return CursorAuthState(accessToken: nil, refreshToken: nil, source: nil)
    }

    private func readStateValue(_ key: String) -> String? {
        guard let row = try? sqlite.query(databaseURL: dbURL, sql: "SELECT value FROM ItemTable WHERE key = '\(key)' LIMIT 1;").first else {
            return nil
        }
        return row["value"]
    }

    private func tokenSubject(_ token: String?) -> String? {
        guard let token, let payload = JWTUtilities.decodePayload(token) else { return nil }
        return stringValue(payload["sub"])
    }

    private func needsRefresh(_ accessToken: String?) -> Bool {
        guard let accessToken else { return true }
        guard let payload = JWTUtilities.decodePayload(accessToken), let exp = numberValue(payload["exp"]) else { return false }
        return Date().addingTimeInterval(refreshBuffer).timeIntervalSince1970 >= exp
    }

    private func refreshToken(refreshTokenValue: String?, source: CursorAuthSource?) async throws -> String? {
        guard let refreshTokenValue else { return nil }
        var request = URLRequest(url: refreshURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 15
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "grant_type": "refresh_token",
            "client_id": clientID,
            "refresh_token": refreshTokenValue
        ])

        let (data, response) = try await session.data(for: request)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 500
        if statusCode == 400 || statusCode == 401 {
            throw NSError(domain: "CursorProvider", code: statusCode, userInfo: [NSLocalizedDescriptionKey: "Session expired. Sign in via Cursor or run agent login."])
        }
        guard (200...299).contains(statusCode),
              let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let accessToken = stringValue(payload["access_token"]) else {
            return nil
        }

        persistAccessToken(accessToken, source: source)
        return accessToken
    }

    private func persistAccessToken(_ accessToken: String, source: CursorAuthSource?) {
        switch source {
        case .keychain:
            try? keychainService.save(accessToken, service: "cursor-access-token", account: "token")
        case .sqlite, .none:
            defaults.set(accessToken, forKey: "provider.cursor.cachedAccessToken")
        }
    }

    private func connectPost(path: String, accessToken: String, refreshTokenValue: String?, source: CursorAuthSource?) async throws -> CursorResponse {
        let url = baseURL.appending(path: path)
        var response = try await rawConnectPost(url: url, accessToken: accessToken)
        if response.statusCode == 401 || response.statusCode == 403, let refreshed = try await refreshToken(refreshTokenValue: refreshTokenValue, source: source) {
            response = try await rawConnectPost(url: url, accessToken: refreshed)
        }
        if response.statusCode == 401 || response.statusCode == 403 {
            throw NSError(domain: "CursorProvider", code: response.statusCode, userInfo: [NSLocalizedDescriptionKey: "Token expired. Sign in via Cursor or run agent login."])
        }
        return response
    }

    private func rawConnectPost(url: URL, accessToken: String) async throws -> CursorResponse {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 10
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("1", forHTTPHeaderField: "Connect-Protocol-Version")
        request.httpBody = Data("{}".utf8)

        let (data, response) = try await session.data(for: request)
        let http = response as? HTTPURLResponse
        let statusCode = http?.statusCode ?? 500
        let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        return CursorResponse(statusCode: statusCode, payload: payload)
    }

    private func requestBasedFallbackIfNeeded(usage: [String: Any], accessToken: String, planName: String?) async throws -> ((String) -> ProviderResult)? {
        let normalizedPlanName = planName?.lowercased() ?? ""
        let planUsage = usage["planUsage"] as? [String: Any]
        let hasPlanUsage = planUsage != nil
        let hasPlanUsageLimit = numberValue(planUsage?["limit"]) != nil
        let hasTotalUsagePercent = numberValue(planUsage?["totalPercentUsed"]) != nil
        let planUsageLimitMissing = hasPlanUsage && !hasPlanUsageLimit

        let needsRequestBasedFallback = (usage["enabled"] as? Bool != false) && (!hasPlanUsage || planUsageLimitMissing) && ["enterprise", "team"].contains(normalizedPlanName)
        let needsFallbackWithoutPlanInfo = (usage["enabled"] as? Bool != false) && (!hasPlanUsage || planUsageLimitMissing) && !hasTotalUsagePercent && normalizedPlanName.isEmpty

        if needsRequestBasedFallback || needsFallbackWithoutPlanInfo || (planUsageLimitMissing && !hasTotalUsagePercent) {
            if let requestUsage = try await fetchRequestBasedUsage(accessToken: accessToken),
               let gpt4 = requestUsage["gpt-4"] as? [String: Any],
               let used = numberValue(gpt4["numRequests"]),
               let limit = numberValue(gpt4["maxRequestUsage"]), limit > 0 {
                let cycleStart = firstDate(gpt4["startOfMonth"], requestUsage["startOfMonth"])
                let resetAt = cycleStart?.addingTimeInterval(30 * 24 * 60 * 60)
                return { profile in
                    ProviderResult(
                        identifier: Self.identifier,
                        displayName: Self.displayName,
                        category: Self.category,
                        profile: profile,
                        windows: [Window(kind: .monthly, used: used, limit: limit, unit: .requests, percentage: min(100, (used / limit) * 100), resetAt: resetAt)],
                        today: .zero,
                        burnRate: nil,
                        dailyHeatmap: [],
                        models: [],
                        source: .api,
                        freshness: Date(),
                        warnings: []
                    )
                }
            }
        }

        return nil
    }

    private func fetchRequestBasedUsage(accessToken: String) async throws -> [String: Any]? {
        guard let payload = JWTUtilities.decodePayload(accessToken), let sub = stringValue(payload["sub"]) else { return nil }
        let userID = sub.split(separator: "|").last.map(String.init) ?? sub
        guard !userID.isEmpty else { return nil }

        var components = URLComponents(url: restUsageURL, resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "user", value: userID)]
        guard let url = components?.url else { return nil }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 10
        request.setValue("WorkosCursorSessionToken=\(userID)%3A%3A\(accessToken)", forHTTPHeaderField: "Cookie")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    private func fetchStripeBalance(accessToken: String) async throws -> Double? {
        guard let payload = JWTUtilities.decodePayload(accessToken), let sub = stringValue(payload["sub"]) else { return nil }
        let userID = sub.split(separator: "|").last.map(String.init) ?? sub
        guard !userID.isEmpty else { return nil }

        var request = URLRequest(url: stripeURL)
        request.httpMethod = "GET"
        request.timeoutInterval = 10
        request.setValue("WorkosCursorSessionToken=\(userID)%3A%3A\(accessToken)", forHTTPHeaderField: "Cookie")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode),
              let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let customerBalance = numberValue(payload["customerBalance"]) else { return nil }

        return customerBalance < 0 ? abs(customerBalance) : 0
    }

    private func makeCreditsWindow(creditGrants: [String: Any]?, stripeBalanceCents: Double?) -> Window? {
        let hasCreditGrants = creditGrants?["hasCreditGrants"] as? Bool == true
        let totalCents = hasCreditGrants ? numberValue(creditGrants?["totalCents"]) ?? 0 : 0
        let usedCents = hasCreditGrants ? numberValue(creditGrants?["usedCents"]) ?? 0 : 0
        let combinedTotal = totalCents + (stripeBalanceCents ?? 0)
        guard combinedTotal > 0 else { return nil }

        return Window(kind: .custom("Credits"), used: usedCents / 100, limit: combinedTotal / 100, unit: .dollars, percentage: min(100, max(0, (usedCents / max(combinedTotal, 1)) * 100)), resetAt: nil)
    }

    private func makeTotalUsageWindow(planUsage: [String: Any], resetAt: Date?, isTeamAccount: Bool) -> Window? {
        let limit = numberValue(planUsage["limit"])
        let totalSpend = numberValue(planUsage["totalSpend"])
        let remaining = numberValue(planUsage["remaining"])
        let totalPercentUsed = numberValue(planUsage["totalPercentUsed"])
        let windowStart = billingCycleStart(for: resetAt)

        if isTeamAccount, let limit, limit > 0 {
            let used = totalSpend ?? (remaining.map { limit - $0 } ?? 0)
            return Window(kind: .custom("Total usage"), used: used, limit: limit, unit: .dollars, percentage: min(100, max(0, (used / limit) * 100)), resetAt: resetAt, windowStart: windowStart)
        }

        if let totalPercentUsed {
            return Window(kind: .custom("Total usage"), used: totalPercentUsed, limit: 100, unit: .requests, percentage: min(100, max(0, totalPercentUsed)), resetAt: resetAt, windowStart: windowStart)
        }

        if let limit, let used = totalSpend ?? (remaining.map { limit - $0 }), limit > 0 {
            let percentage = min(100, max(0, (used / limit) * 100))
            return Window(kind: .custom("Total usage"), used: percentage, limit: 100, unit: .requests, percentage: percentage, resetAt: resetAt, windowStart: windowStart)
        }

        return nil
    }

    private func makePercentWindow(label: String, value: Any?, resetAt: Date?) -> Window? {
        guard let percent = numberValue(value) else { return nil }
        return Window(kind: .custom(label), used: percent, limit: 100, unit: .requests, percentage: min(100, max(0, percent)), resetAt: resetAt, windowStart: billingCycleStart(for: resetAt))
    }

    private func makeOnDemandWindow(spendLimitUsage: [String: Any]?, resetAt: Date?) -> Window? {
        guard let spendLimitUsage else { return nil }
        let limit = numberValue(spendLimitUsage["individualLimit"]) ?? numberValue(spendLimitUsage["pooledLimit"]) ?? 0
        let remaining = numberValue(spendLimitUsage["individualRemaining"]) ?? numberValue(spendLimitUsage["pooledRemaining"]) ?? 0
        guard limit > 0 else { return nil }
        let used = limit - remaining
        return Window(kind: .custom("On-demand"), used: used, limit: limit, unit: .dollars, percentage: min(100, max(0, (used / limit) * 100)), resetAt: resetAt, windowStart: billingCycleStart(for: resetAt))
    }

    private func billingCycleStart(for resetAt: Date?) -> Date? {
        guard let resetAt else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        return calendar.date(byAdding: .month, value: -1, to: resetAt)
    }

    private func numberValue(_ value: Any?) -> Double? {
        if let double = value as? Double, double.isFinite { return double }
        if let int = value as? Int { return Double(int) }
        if let string = value as? String, let double = Double(string), double.isFinite { return double }
        return nil
    }

    private func dateFromMilliseconds(_ value: Any?) -> Date? {
        guard let milliseconds = numberValue(value) else { return nil }
        return Date(timeIntervalSince1970: milliseconds / 1000)
    }

    private func firstDate(_ values: Any?...) -> Date? {
        for value in values {
            if let milliseconds = numberValue(value) {
                if milliseconds > 10_000_000_000 {
                    return Date(timeIntervalSince1970: milliseconds / 1000)
                }
                return Date(timeIntervalSince1970: milliseconds)
            }
            if let string = stringValue(value), let date = TimeHelpers.parseISODate(string) {
                return date
            }
        }
        return nil
    }

}

private struct CursorMetadata {
    let email: String?
    let membershipType: String?
}

private struct CursorAuthState {
    var accessToken: String?
    var refreshToken: String?
    let source: CursorAuthSource?
}

private enum CursorAuthSource {
    case sqlite
    case keychain
}

private struct CursorResponse {
    let statusCode: Int
    let payload: [String: Any]?
}