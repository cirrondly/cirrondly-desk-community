import Foundation

final class ClaudeSubscriptionProvider: UsageProvider {
    static let identifier = "claude-subscription"
    static let displayName = "Claude Subscription"
    static let category: ProviderCategory = .subscription

    private let defaults = UserDefaults.standard
    private let keychainService: KeychainService
    private let session = URLSession(configuration: .ephemeral)
    private let defaultClaudeHome = ".claude"
    private let credentialsFile = ".credentials.json"
    private let keychainServicePrefix = "Claude Code"
    private let prodBaseAPIURL = "https://api.anthropic.com"
    private let prodRefreshURL = "https://platform.claude.com/v1/oauth/token"
    private let prodClientID = "9d1c250a-e61b-44d9-88ed-5944d1962f5e"
    private let nonProdClientID = "22422756-60c9-4084-8eb7-27705fd5cf9a"
    private let promoClockURL = URL(string: "https://promoclock.co/api/status")!
    private let scopes = "user:profile user:inference user:sessions:claude_code user:mcp_servers user:file_upload"
    private let refreshBuffer: TimeInterval = 5 * 60

    init(keychainService: KeychainService) {
        self.keychainService = keychainService
    }

    var isEnabled: Bool {
        get { defaults.object(forKey: "provider.claude-subscription.enabled") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "provider.claude-subscription.enabled") }
    }

    var profiles: [ProviderProfile] { [ProviderProfile(name: "Claude.ai") ] }
    var activeProfile: ProviderProfile? = ProviderProfile(name: "Claude.ai")

    func isAvailable() async -> Bool {
        loadCredentials(suppressMissingWarn: true) != nil || sessionKey() != nil
    }

    func probe() async throws -> ProviderResult {
        if var credentials = loadCredentials(suppressMissingWarn: true), let oauth = credentials.oauth, let token = oauth.accessToken, !token.isEmpty {
            return try await probeOAuth(credentials: &credentials)
        }

        guard let sessionKey = sessionKey() else {
            return .unavailable(identifier: Self.identifier, displayName: Self.displayName, category: Self.category, warning: "Provide a Claude session key in Sources or sign in with Claude Code.")
        }

        let orgID = try await fetchOrganizationID(sessionKey: sessionKey)
        let usagePayload = try await fetchJSON(url: URL(string: "https://claude.ai/api/organizations/\(orgID)/usage")!, sessionKey: sessionKey, organizationID: orgID)
        let routinePayload = try? await fetchJSON(url: URL(string: "https://claude.ai/v1/code/routines/run-budget")!, sessionKey: sessionKey, organizationID: orgID)

        let fiveHour = makePercentWindow(kind: .fiveHour, payload: usagePayload["five_hour"] as? [String: Any])
        let weekly = makePercentWindow(kind: .weekly, payload: usagePayload["seven_day"] as? [String: Any])
        let sonnet = makePercentWindow(kind: .custom("Sonnet"), payload: usagePayload["seven_day_sonnet"] as? [String: Any])
        let extra = makeCreditsWindow(payload: usagePayload["extra_usage"] as? [String: Any])
        let routines = makeRoutineWindow(payload: routinePayload)

        return ProviderResult(
            identifier: Self.identifier,
            displayName: Self.displayName,
            category: Self.category,
            profile: activeProfile?.name ?? "Claude.ai",
            windows: [fiveHour, weekly, sonnet, extra, routines].compactMap { $0 },
            today: .zero,
            burnRate: nil,
            dailyHeatmap: [],
            models: [],
            source: .api,
            freshness: Date(),
            warnings: [ProviderWarning(level: .info, message: "Uses Claude.ai internal APIs. Anthropic may change these endpoints without notice.")]
        )
    }

    private func probeOAuth(credentials: inout ClaudeStoredCredentials) async throws -> ProviderResult {
        guard var oauth = credentials.oauth, var accessToken = oauth.accessToken, !accessToken.isEmpty else {
            throw NSError(domain: "ClaudeSubscriptionProvider", code: 401, userInfo: [NSLocalizedDescriptionKey: "Not logged in. Run claude to authenticate."])
        }

        let canFetchLiveUsage = hasProfileScope(credentials)
        var windows: [Window] = []
        var warnings: [ProviderWarning] = []
        var plan = planName(from: oauth)

        if canFetchLiveUsage {
            if needsRefresh(oauth) {
                if let refreshed = try await refreshOAuthToken(credentials: &credentials) {
                    accessToken = refreshed
                    oauth = credentials.oauth ?? oauth
                    plan = planName(from: oauth)
                }
            }

            var usageResponse = try await fetchUsage(accessToken: accessToken)
            if usageResponse.statusCode == 401 || usageResponse.statusCode == 403,
               let refreshed = try await refreshOAuthToken(credentials: &credentials) {
                accessToken = refreshed
                oauth = credentials.oauth ?? oauth
                plan = planName(from: oauth)
                usageResponse = try await fetchUsage(accessToken: accessToken)
            }

            if usageResponse.statusCode == 401 || usageResponse.statusCode == 403 {
                throw NSError(domain: "ClaudeSubscriptionProvider", code: usageResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "Token expired. Run claude to log in again."])
            }
            guard (200...299).contains(usageResponse.statusCode), let payload = usageResponse.payload else {
                throw NSError(domain: "ClaudeSubscriptionProvider", code: usageResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: "Usage request failed. Try again later."])
            }

            if let sessionWindow = makePercentWindow(kind: .fiveHour, payload: payload["five_hour"] as? [String: Any]) {
                windows.append(sessionWindow)
            }
            if let weekly = makePercentWindow(kind: .weekly, payload: payload["seven_day"] as? [String: Any]) {
                windows.append(weekly)
            }
            if let sonnet = makePercentWindow(kind: .custom("Sonnet"), payload: payload["seven_day_sonnet"] as? [String: Any]) {
                windows.append(sonnet)
            }
            if let extra = makeCreditsWindow(payload: payload["extra_usage"] as? [String: Any]) {
                windows.append(extra)
            }
        } else {
            warnings.append(ProviderWarning(level: .info, message: "Claude is using an inference-only token, so live subscription usage is unavailable."))
        }

        if let promo = try? await fetchPromoClockWarning() {
            warnings.append(promo)
        }

        if windows.isEmpty {
            warnings.append(ProviderWarning(level: .info, message: "Claude returned no usage windows."))
        }

        return ProviderResult(
            identifier: Self.identifier,
            displayName: Self.displayName,
            category: Self.category,
            profile: plan ?? activeProfile?.name ?? "Claude.ai",
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

    private func sessionKey() -> String? {
        let storedValue = defaults.string(forKey: "sources.claude.sessionKey")?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if let storedValue, !storedValue.isEmpty {
            return storedValue
        }

        let keychainValue = keychainService.read(service: "com.anthropic.claude-code", account: "sessionKey")?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let keychainValue, !keychainValue.isEmpty else { return nil }
        return keychainValue
    }

    private func loadCredentials(suppressMissingWarn: Bool) -> ClaudeStoredCredentials? {
        let envToken = readEnvText("CLAUDE_CODE_OAUTH_TOKEN")
        let stored = loadStoredCredentials(suppressMissingWarn: envToken != nil || suppressMissingWarn)
        if let envToken {
            var oauth = stored?.oauth ?? ClaudeOAuth()
            oauth.accessToken = envToken
            return ClaudeStoredCredentials(oauth: oauth, source: stored?.source, fullData: stored?.fullData, inferenceOnly: true)
        }
        return stored
    }

    private func loadStoredCredentials(suppressMissingWarn: Bool) -> ClaudeStoredCredentials? {
        let fileURL = claudeCredentialsPath()
        if FileManager.default.fileExists(atPath: fileURL.path),
           let data = try? Data(contentsOf: fileURL),
           let parsed = parseCredentialJSON(data: data),
           let oauth = parseOAuth(from: parsed),
           oauth.accessToken != nil {
            return ClaudeStoredCredentials(oauth: oauth, source: .file(fileURL), fullData: parsed, inferenceOnly: false)
        }

        if let raw = keychainService.readAny(service: claudeKeychainServiceName()),
              let parsed = parseCredentialJSON(raw: raw),
           let oauth = parseOAuth(from: parsed),
           oauth.accessToken != nil {
            return ClaudeStoredCredentials(oauth: oauth, source: .keychain, fullData: parsed, inferenceOnly: false)
        }

        if !suppressMissingWarn {
            _ = suppressMissingWarn
        }
        return nil
    }

    private func claudeCredentialsPath() -> URL {
        if let override = readEnvText("CLAUDE_CONFIG_DIR") {
            return URL(fileURLWithPath: override).appending(path: credentialsFile)
        }
        return FileManager.default.homeDirectoryForCurrentUser.appending(path: defaultClaudeHome).appending(path: credentialsFile)
    }

    private func claudeKeychainServiceName() -> String {
        let suffix = oauthConfig().oauthFileSuffix
        return keychainServicePrefix + suffix + "-credentials"
    }

    private func oauthConfig() -> ClaudeOAuthConfig {
        var baseAPIURL = prodBaseAPIURL
        var refreshURL = prodRefreshURL
        var clientID = prodClientID
        var oauthFileSuffix = ""

        let userType = readEnvText("USER_TYPE")
        let useLocalOAuth = readEnvFlag("USE_LOCAL_OAUTH")
        let useStagingOAuth = readEnvFlag("USE_STAGING_OAUTH")

        if userType == "ant", useLocalOAuth {
            let localAPIBase = readEnvText("CLAUDE_LOCAL_OAUTH_API_BASE") ?? "http://localhost:8000"
            baseAPIURL = localAPIBase.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            refreshURL = baseAPIURL + "/v1/oauth/token"
            clientID = nonProdClientID
            oauthFileSuffix = "-local-oauth"
        } else if userType == "ant", useStagingOAuth {
            baseAPIURL = "https://api-staging.anthropic.com"
            refreshURL = "https://platform.staging.ant.dev/v1/oauth/token"
            clientID = nonProdClientID
            oauthFileSuffix = "-staging-oauth"
        }

        if let customOAuthBase = readEnvText("CLAUDE_CODE_CUSTOM_OAUTH_URL") {
            let base = customOAuthBase.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            baseAPIURL = base
            refreshURL = base + "/v1/oauth/token"
            oauthFileSuffix = "-custom-oauth"
        }

        if let overrideClientID = readEnvText("CLAUDE_CODE_OAUTH_CLIENT_ID") {
            clientID = overrideClientID
        }

        return ClaudeOAuthConfig(baseAPIURL: baseAPIURL, usageURL: baseAPIURL + "/api/oauth/usage", refreshURL: refreshURL, clientID: clientID, oauthFileSuffix: oauthFileSuffix)
    }

    private func parseCredentialJSON(data: Data) -> [String: Any]? {
        try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    private func parseCredentialJSON(raw: String) -> [String: Any]? {
        if let data = raw.data(using: .utf8), let parsed = parseCredentialJSON(data: data) {
            return parsed
        }

        guard let decoded = decodeHexData(raw) else { return nil }
        return parseCredentialJSON(data: decoded)
    }

    private func parseOAuth(from payload: [String: Any]) -> ClaudeOAuth? {
        let oauthPayload = payload["claudeAiOauth"] as? [String: Any]
        guard oauthPayload != nil else { return nil }
        return ClaudeOAuth(
            accessToken: stringValue(oauthPayload?["accessToken"]),
            refreshToken: stringValue(oauthPayload?["refreshToken"]),
            expiresAt: numberValue(oauthPayload?["expiresAt"]),
            scopes: oauthPayload?["scopes"] as? [String],
            subscriptionType: stringValue(oauthPayload?["subscriptionType"]),
            rateLimitTier: stringValue(oauthPayload?["rateLimitTier"])
        )
    }

    private func hasProfileScope(_ credentials: ClaudeStoredCredentials) -> Bool {
        if credentials.inferenceOnly { return false }
        guard let scopes = credentials.oauth?.scopes, !scopes.isEmpty else { return true }
        return scopes.contains("user:profile")
    }

    private func needsRefresh(_ oauth: ClaudeOAuth) -> Bool {
        guard let expiresAt = oauth.expiresAt else { return true }
        return Date().addingTimeInterval(refreshBuffer).timeIntervalSince1970 * 1000 >= expiresAt
    }

    private func refreshOAuthToken(credentials: inout ClaudeStoredCredentials) async throws -> String? {
        guard var oauth = credentials.oauth, let refreshToken = oauth.refreshToken else { return nil }
        let config = oauthConfig()
        guard let url = URL(string: config.refreshURL) else { return nil }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "client_id": config.clientID,
            "scope": scopes
        ])

        let (data, response) = try await session.data(for: request)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 500
        if statusCode == 400 || statusCode == 401 {
            let body = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            let errorCode = stringValue(body?["error"]) ?? stringValue(body?["error_description"])
            if errorCode == "invalid_grant" {
                throw NSError(domain: "ClaudeSubscriptionProvider", code: statusCode, userInfo: [NSLocalizedDescriptionKey: "Session expired. Run claude to log in again."])
            }
            throw NSError(domain: "ClaudeSubscriptionProvider", code: statusCode, userInfo: [NSLocalizedDescriptionKey: "Token expired. Run claude to log in again."])
        }

        guard (200...299).contains(statusCode),
              let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let newAccessToken = stringValue(payload["access_token"]) else {
            return nil
        }

        oauth.accessToken = newAccessToken
        if let newRefreshToken = stringValue(payload["refresh_token"]) { oauth.refreshToken = newRefreshToken }
        if let expiresIn = numberValue(payload["expires_in"]) { oauth.expiresAt = Date().timeIntervalSince1970 * 1000 + expiresIn * 1000 }
        credentials.oauth = oauth
        persistCredentials(&credentials)
        return newAccessToken
    }

    private func persistCredentials(_ credentials: inout ClaudeStoredCredentials) {
          guard var fullData = credentials.fullData,
              let oauth = credentials.oauth else { return }

        fullData["claudeAiOauth"] = [
            "accessToken": oauth.accessToken as Any,
            "refreshToken": oauth.refreshToken as Any,
            "expiresAt": oauth.expiresAt as Any,
            "scopes": oauth.scopes as Any,
            "subscriptionType": oauth.subscriptionType as Any,
            "rateLimitTier": oauth.rateLimitTier as Any
        ].compactMapValues { $0 }

        guard JSONSerialization.isValidJSONObject(fullData),
              let data = try? JSONSerialization.data(withJSONObject: fullData, options: []) else {
            return
        }
        credentials.fullData = fullData
        switch credentials.source {
        case .file(let url):
            try? data.write(to: url)
        case .keychain:
            if let text = String(data: data, encoding: .utf8) {
                try? keychainService.save(text, service: claudeKeychainServiceName(), account: "credentials")
            }
        case .none:
            break
        }
    }

    private func fetchUsage(accessToken: String) async throws -> ClaudeUsageResponse {
        let config = oauthConfig()
        guard let url = URL(string: config.usageURL) else {
            throw URLError(.badURL)
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 10
        request.setValue("Bearer \(accessToken.trimmingCharacters(in: .whitespacesAndNewlines))", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("claude-code/2.1.69", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await session.data(for: request)
        let http = response as? HTTPURLResponse
        let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        return ClaudeUsageResponse(statusCode: http?.statusCode ?? 500, payload: payload)
    }

    private func fetchPromoClockWarning() async throws -> ProviderWarning? {
        var request = URLRequest(url: promoClockURL)
        request.httpMethod = "GET"
        request.timeoutInterval = 2
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode),
              let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let badge = promoClockBadgeText(payload) else {
            return nil
        }

        return ProviderWarning(level: badge == "Peak" ? .warning : .info, message: "Peak Hours: \(badge)")
    }

    private func promoClockBadgeText(_ payload: [String: Any]) -> String? {
        if payload["isPeak"] as? Bool == true { return "Peak" }
        if payload["isOffPeak"] as? Bool == true || payload["isWeekend"] as? Bool == true { return "Off-Peak" }
        switch stringValue(payload["status"])?.lowercased() {
        case "peak": return "Peak"
        case "off_peak", "off-peak", "weekend": return "Off-Peak"
        default: return nil
        }
    }

    private func planName(from oauth: ClaudeOAuth) -> String? {
        guard let subscriptionType = oauth.subscriptionType else { return nil }
        let base: String
        switch subscriptionType.lowercased() {
        case "max": base = "Claude Max"
        case "pro": base = "Claude Pro"
        case "team": base = "Claude Team"
        default: base = subscriptionType.capitalized
        }
        if let tier = oauth.rateLimitTier?.lowercased(), let match = tier.range(of: "\\d+x", options: .regularExpression) {
            return base + " " + String(tier[match]).uppercased()
        }
        return base
    }

    private func readEnvText(_ name: String) -> String? {
        let value = ProcessInfo.processInfo.environment[name]?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (value?.isEmpty == false) ? value : nil
    }

    private func readEnvFlag(_ name: String) -> Bool {
        guard let value = readEnvText(name)?.lowercased() else { return false }
        return !["0", "false", "no", "off"].contains(value)
    }

    private func decodeHexData(_ raw: String) -> Data? {
        var hex = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if hex.hasPrefix("0x") || hex.hasPrefix("0X") { hex.removeFirst(2) }
        guard hex.count.isMultiple(of: 2) else { return nil }
        var data = Data(capacity: hex.count / 2)
        var index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 2)
            guard let byte = UInt8(hex[index..<next], radix: 16) else { return nil }
            data.append(byte)
            index = next
        }
        return data
    }

    private func numberValue(_ value: Any?) -> Double? {
        if let value = value as? Double, value.isFinite { return value }
        if let value = value as? Int { return Double(value) }
        if let value = value as? NSNumber { return value.doubleValue }
        return nil
    }

    private func fetchOrganizationID(sessionKey: String) async throws -> String {
        let payload = try await fetchJSONArray(url: URL(string: "https://claude.ai/api/organizations")!, sessionKey: sessionKey)
        guard let first = payload.first, let id = first["uuid"] as? String ?? first["id"] as? String else {
            throw URLError(.badServerResponse)
        }
        return id
    }

    private func fetchJSON(url: URL, sessionKey: String, organizationID: String? = nil) async throws -> [String: Any] {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("sessionKey=\(sessionKey)", forHTTPHeaderField: "Cookie")
        request.setValue("https://claude.ai/settings/usage", forHTTPHeaderField: "Referer")
        request.setValue("https://claude.ai", forHTTPHeaderField: "Origin")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        if let organizationID {
            request.setValue(organizationID, forHTTPHeaderField: "x-organization-uuid")
        }

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw URLError(.cannotParseResponse)
        }
        return json
    }

    private func fetchJSONArray(url: URL, sessionKey: String) async throws -> [[String: Any]] {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("sessionKey=\(sessionKey)", forHTTPHeaderField: "Cookie")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw URLError(.cannotParseResponse)
        }
        return json
    }

    private func makePercentWindow(kind: WindowKind, payload: [String: Any]?) -> Window? {
        guard let payload else { return nil }
        let utilization = intValue(payload["utilization"])
        let resetAt = TimeHelpers.parseISODate(stringValue(payload["resets_at"]))
        return Window(kind: kind, used: Double(utilization), limit: 100, unit: .requests, percentage: Double(utilization), resetAt: resetAt, windowStart: quotaWindowStart(for: kind, resetAt: resetAt))
    }

    private func makeCreditsWindow(payload: [String: Any]?) -> Window? {
        guard let payload else { return nil }
        let used = Double(intValue(payload["used_credits"]))
        let limit = Double(intValue(payload["monthly_limit"]))
        guard limit > 0 else { return nil }
        let resetAt = TimeHelpers.nextMonthBoundary()
        return Window(kind: .monthly, used: used, limit: limit, unit: .dollars, percentage: min(100, (used / limit) * 100), resetAt: resetAt)
    }

    private func makeRoutineWindow(payload: [String: Any]?) -> Window? {
        guard let payload else { return nil }
        let used = Double(intValue(payload["used"]))
        let limit = Double(intValue(payload["limit"]))
        guard limit > 0 else { return nil }
        let resetAt = TimeHelpers.nextMonthBoundary()
        let windowStart = resetAt.flatMap { ForecastCalculator.inferredWindowStart(kind: .monthly, resetAt: $0) }
        return Window(kind: .custom("Routines"), used: used, limit: limit, unit: .requests, percentage: min(100, (used / limit) * 100), resetAt: resetAt, windowStart: windowStart)
    }

    private func quotaWindowStart(for kind: WindowKind, resetAt: Date?) -> Date? {
        switch kind {
        case .fiveHour, .weekly, .monthly:
            return ForecastCalculator.inferredWindowStart(kind: kind, resetAt: resetAt)
        case .custom:
            return resetAt?.addingTimeInterval(-SessionWindowPreset.lastSevenDays.duration)
        }
    }
}

private struct ClaudeOAuth {
    var accessToken: String?
    var refreshToken: String?
    var expiresAt: Double?
    var scopes: [String]?
    var subscriptionType: String?
    var rateLimitTier: String?

    init(accessToken: String? = nil, refreshToken: String? = nil, expiresAt: Double? = nil, scopes: [String]? = nil, subscriptionType: String? = nil, rateLimitTier: String? = nil) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresAt = expiresAt
        self.scopes = scopes
        self.subscriptionType = subscriptionType
        self.rateLimitTier = rateLimitTier
    }
}

private struct ClaudeStoredCredentials {
    var oauth: ClaudeOAuth?
    let source: ClaudeCredentialSource?
    var fullData: [String: Any]?
    let inferenceOnly: Bool
}

private enum ClaudeCredentialSource {
    case file(URL)
    case keychain
}

private struct ClaudeOAuthConfig {
    let baseAPIURL: String
    let usageURL: String
    let refreshURL: String
    let clientID: String
    let oauthFileSuffix: String
}

private struct ClaudeUsageResponse {
    let statusCode: Int
    let payload: [String: Any]?
}