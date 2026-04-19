import Foundation

final class PerplexityProvider: UsageProvider {
    static let identifier = "perplexity"
    static let displayName = "Perplexity"
    static let category: ProviderCategory = .subscription

    private let defaults = UserDefaults.standard
    private let sqlite = SQLiteReader()
    private let session = URLSession(configuration: .ephemeral)
    private let localUserEndpoint = "https://www.perplexity.ai/api/user"
    private let restAPIBase = "https://www.perplexity.ai/rest/pplx-api/v2"
    private let rateLimitEndpoint = URL(string: "https://www.perplexity.ai/rest/rate-limit/all")!
    private let localCacheDBPaths = [
        FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library/Containers/ai.perplexity.mac/Data/Library/Caches/ai.perplexity.mac/Cache.db"),
        FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library/Caches/ai.perplexity.mac/Cache.db")
    ]
    private let rateLimitCategories = [
        ("remaining_pro", "Queries"),
        ("remaining_research", "Deep Research"),
        ("remaining_labs", "Labs"),
        ("remaining_agentic_research", "Agentic Research")
    ]
    private let bearerHexPrefix = "42656172657220"
    private let askUAHexPrefix = "41736B2F"
    private let macOSDeviceIDHexPrefix = "6D61636F733A"
    private let maxRequestFieldLength = 220

    var isEnabled: Bool {
        get { defaults.object(forKey: "provider.perplexity.enabled") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "provider.perplexity.enabled") }
    }

    var profiles: [ProviderProfile] { [ProviderProfile(name: "Default")] }
    var activeProfile: ProviderProfile? = ProviderProfile(name: "Default")

    func isAvailable() async -> Bool {
        localCacheDBPaths.contains { FileManager.default.fileExists(atPath: $0.path) }
    }

    func probe() async throws -> ProviderResult {
        guard let sessionState = loadLocalSession() else {
            return .unavailable(
                identifier: Self.identifier,
                displayName: Self.displayName,
                category: Self.category,
                warning: "Not logged in. Sign in via the Perplexity app."
            )
        }

        guard let restState = try await fetchRestState(sessionState), let group = restState.group as? [String: Any] else {
            return ProviderResult(
                identifier: Self.identifier,
                displayName: Self.displayName,
                category: Self.category,
                profile: activeProfile?.name ?? "Default",
                windows: [],
                today: .zero,
                burnRate: nil,
                dailyHeatmap: [],
                models: [],
                source: .mixed,
                freshness: Date(),
                warnings: [ProviderWarning(level: .info, message: "Perplexity data is currently unavailable. Try opening the app or site again.")]
            )
        }

        let customerInfo = (group["customerInfo"] as? [String: Any])
            ?? (group["customer_info"] as? [String: Any])
        let plan = detectPlanLabel(customerInfo)

        var windows: [Window] = []
        if let balanceUSD = readBalanceUSD(group) {
            let usedUSD = sumUsageCostUSD(restState.usageAnalytics) ?? 0
            if balanceUSD > 0 {
                windows.append(makeWindow(kind: .custom("API credits"), used: usedUSD, limit: balanceUSD, resetAt: nil))
            }
        }

        var warnings: [ProviderWarning] = []
        if let rateLimits = restState.rateLimits {
            warnings.append(contentsOf: buildRateLimitWarnings(rateLimits))
        }

        if windows.isEmpty && warnings.isEmpty {
            warnings.append(ProviderWarning(level: .info, message: "Perplexity usage data is unavailable. Try again later."))
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
            source: .mixed,
            freshness: Date(),
            warnings: warnings
        )
    }

    private func loadLocalSession() -> PerplexitySessionState? {
        for path in localCacheDBPaths where FileManager.default.fileExists(atPath: path.path) {
            if let state = queryLocalSession(from: path) {
                return state
            }
        }
        return nil
    }

    private func queryLocalSession(from databaseURL: URL) -> PerplexitySessionState? {
        let sql = "SELECT hex(b.request_object) AS requestHex FROM cfurl_cache_response r JOIN cfurl_cache_blob_data b ON b.entry_ID = r.entry_ID WHERE r.request_key = '\(localUserEndpoint)' ORDER BY r.entry_ID DESC LIMIT 1;"
        guard let row = try? sqlite.query(databaseURL: databaseURL, sql: sql).first,
              let requestHex = row["requestHex"],
              let authToken = extractAuthToken(requestHex) else {
            return nil
        }

        let userAgent = extractPrintableField(requestHex, prefixHex: askUAHexPrefix)
        let appVersion = userAgent.flatMap(askAppVersion)
        let deviceID = extractPrintableField(requestHex, prefixHex: macOSDeviceIDHexPrefix)
        return PerplexitySessionState(authToken: authToken, userAgent: userAgent, appVersion: appVersion, deviceID: deviceID, sourcePath: databaseURL)
    }

    private func extractAuthToken(_ requestHex: String) -> String? {
        let upper = requestHex.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard let range = upper.range(of: bearerHexPrefix) else { return nil }
        var index = range.upperBound
        var token = ""

        while index < upper.endIndex {
            let next = upper.index(index, offsetBy: 2, limitedBy: upper.endIndex) ?? upper.endIndex
            guard next <= upper.endIndex, next > index else { break }
            guard let byte = UInt8(upper[index..<next], radix: 16), isAllowedAuthByte(byte) else { break }
            if byte == 0x5f {
                let peekStart = next
                let peekEnd = upper.index(peekStart, offsetBy: 2, limitedBy: upper.endIndex) ?? upper.endIndex
                if peekEnd > peekStart, let nextByte = UInt8(upper[peekStart..<peekEnd], radix: 16), [0x10, 0x11, 0x12, 0x13, 0x14].contains(nextByte) {
                    break
                }
            }
            token.append(Character(UnicodeScalar(byte)))
            index = next
        }

        return token.filter { $0 == "." }.count >= 2 ? token : nil
    }

    private func extractPrintableField(_ requestHex: String, prefixHex: String) -> String? {
        let upper = requestHex.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard let range = upper.range(of: prefixHex) else { return nil }
        var index = range.lowerBound
        var output = ""

        while index < upper.endIndex && output.count < maxRequestFieldLength {
            let next = upper.index(index, offsetBy: 2, limitedBy: upper.endIndex) ?? upper.endIndex
            guard next <= upper.endIndex, next > index, let byte = UInt8(upper[index..<next], radix: 16), isPrintableASCII(byte) else { break }
            output.append(Character(UnicodeScalar(byte)))
            index = next
        }

        return output.isEmpty ? nil : output
    }

    private func askAppVersion(_ userAgent: String) -> String? {
        guard let range = userAgent.range(of: #"^Ask/([^/]+)"#, options: .regularExpression) else { return nil }
        let match = String(userAgent[range]).split(separator: "/")
        return match.count > 1 ? String(match[1]) : nil
    }

    private func isAllowedAuthByte(_ byte: UInt8) -> Bool {
        (0x30...0x39).contains(byte) || (0x41...0x5A).contains(byte) || (0x61...0x7A).contains(byte) || byte == 0x2e || byte == 0x2d || byte == 0x5f
    }

    private func isPrintableASCII(_ byte: UInt8) -> Bool {
        (0x20...0x7e).contains(byte)
    }

    private func fetchRestState(_ sessionState: PerplexitySessionState) async throws -> PerplexityRestState? {
        let groupsURL = URL(string: "\(restAPIBase)/groups")!
        let headers = makeRestHeaders(sessionState)
        let groups = try await fetchJSONAnyWithFallback(primary: groupsURL, fallback: URL(string: "\(restAPIBase)/groups/")!, authToken: sessionState.authToken, headers: headers) as? [String: Any]
        guard let groups else { return nil }
        guard let groupID = pickGroupID(groups) else { return nil }

        let groupURL = URL(string: "\(restAPIBase)/groups/\(groupID)")!
        let usageURL = URL(string: "\(restAPIBase)/groups/\(groupID)/usage-analytics")!
        let group = try await fetchJSONAnyWithFallback(primary: groupURL, fallback: URL(string: groupURL.absoluteString + "/")!, authToken: sessionState.authToken, headers: headers)
        let usageAnalytics = try await fetchJSONAnyWithFallback(primary: usageURL, fallback: URL(string: usageURL.absoluteString + "/")!, authToken: sessionState.authToken, headers: headers)
        let rateLimits = try await fetchJSONAnyOptional(url: rateLimitEndpoint, authToken: sessionState.authToken, headers: headers) as? [String: Any]
        return PerplexityRestState(groupID: groupID, group: group, usageAnalytics: usageAnalytics, rateLimits: rateLimits)
    }

    private func makeRestHeaders(_ sessionState: PerplexitySessionState) -> [String: String] {
        var headers = [
            "Accept": "*/*",
            "User-Agent": sessionState.userAgent ?? "Ask/0 (macOS) isiOSOnMac/false",
            "X-Client-Name": "Perplexity-Mac",
            "X-App-ApiVersion": "2.17",
            "X-App-ApiClient": "macos",
            "X-Client-Env": "production"
        ]
        if let appVersion = sessionState.appVersion { headers["X-App-Version"] = appVersion }
        if let deviceID = sessionState.deviceID { headers["X-Device-ID"] = deviceID }
        return headers
    }

    private func fetchJSONAnyOptional(url: URL, authToken: String, headers: [String: String]) async throws -> Any? {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 10
        request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("OpenUsage", forHTTPHeaderField: "User-Agent")
        headers.forEach { request.setValue($1, forHTTPHeaderField: $0) }

        do {
            let (data, response) = try await session.data(for: request)
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 500
            if statusCode == 401 || statusCode == 403 {
                if statusCode == 403, let html = String(data: data, encoding: .utf8), html.contains("Just a moment") { return nil }
                return nil
            }
            guard (200...299).contains(statusCode) else { return nil }
            return try? JSONSerialization.jsonObject(with: data)
        } catch {
            return nil
        }
    }

    private func fetchJSONAnyWithFallback(primary: URL, fallback: URL, authToken: String, headers: [String: String]) async throws -> Any? {
        if let primaryValue = try await fetchJSONAnyOptional(url: primary, authToken: authToken, headers: headers) {
            return primaryValue
        }
        return try await fetchJSONAnyOptional(url: fallback, authToken: authToken, headers: headers)
    }

    private func pickGroupID(_ payload: [String: Any]) -> String? {
        if let direct = readGroupID(payload) { return direct }
        for key in ["orgs", "groups", "results", "items", "data"] {
            if let array = payload[key] as? [[String: Any]], let id = pickGroupID(from: array) { return id }
        }
        return nil
    }

    private func pickGroupID(from array: [[String: Any]]) -> String? {
        var first: String?
        for item in array {
            guard let id = readGroupID(item) else { continue }
            if first == nil { first = id }
            if (item["is_default_org"] as? Bool) == true || (item["isDefaultOrg"] as? Bool) == true {
                return id
            }
        }
        return first
    }

    private func readGroupID(_ value: Any?) -> String? {
        guard let object = value as? [String: Any] else { return nil }
        return Self.stringValue(object["api_org_id"])
            ?? Self.stringValue(object["apiOrgId"])
            ?? Self.stringValue(object["org_id"])
            ?? Self.stringValue(object["orgId"])
            ?? Self.stringValue(object["id"])
            ?? Self.stringValue(object["group_id"])
            ?? Self.stringValue(object["groupId"])
    }

    private func detectPlanLabel(_ customerInfo: [String: Any]?) -> String? {
        guard let customerInfo else { return nil }
        if customerInfo["is_max"] as? Bool == true || Self.stringValue(customerInfo["subscription_tier"]) == "max" { return "Max" }
        if customerInfo["is_pro"] as? Bool == true { return "Pro" }
        return nil
    }

    private func readBalanceUSD(_ payload: Any?) -> Double? {
        guard let payload else { return nil }
        if let array = payload as? [Any] {
            for item in array {
                if let value = readBalanceUSD(item) { return value }
            }
            return nil
        }
        guard let object = payload as? [String: Any] else {
            return readMoneyLike(payload)
        }

        for key in ["apiOrganization", "api_organization", "group", "org", "organization", "data", "result", "item", "customerInfo", "wallet", "billing", "usage", "account", "balances"] {
            if let value = readBalanceUSD(object[key]) { return value }
        }

        for key in ["balance_usd", "balanceUsd", "balance", "pending_balance", "pendingBalance"] {
            if let value = Self.doubleValue(object[key]) ?? readMoneyLike(object[key]) { return value }
        }

        for (key, value) in object where key.range(of: #"balance|credit|wallet|prepaid|available"#, options: .regularExpression) != nil {
            if let parsed = readMoneyLike(value) { return parsed }
        }
        return nil
    }

    private func readMoneyLike(_ value: Any?) -> Double? {
        if let direct = Self.doubleValue(value) { return direct }
        guard let object = value as? [String: Any] else { return nil }
        if let cents = Self.doubleValue(object["cents"] ?? object["amount_cents"] ?? object["amountCents"] ?? object["value_cents"] ?? object["valueCents"]) {
            return cents / 100
        }
        return Self.doubleValue(object["usd"] ?? object["amount_usd"] ?? object["amountUsd"] ?? object["value_usd"] ?? object["valueUsd"] ?? object["amount"] ?? object["value"] ?? object["balance"] ?? object["remaining"] ?? object["available"])
    }

    private func sumUsageCostUSD(_ payload: Any?) -> Double? {
        guard let array = payload as? [Any] else { return nil }
        var total = 0.0
        var sawMeter = array.isEmpty
        var sawCost = false
        for item in array {
            guard let meter = item as? [String: Any] else { continue }
            let summaries = (meter["meter_event_summaries"] as? [Any]) ?? (meter["meterEventSummaries"] as? [Any]) ?? []
            if summaries.isEmpty { sawMeter = true }
            for summary in summaries {
                guard let summary = summary as? [String: Any], let cost = Self.doubleValue(summary["cost"]) else { continue }
                total += cost
                sawCost = true
            }
        }
        return (sawMeter || sawCost) ? total : nil
    }

    private func buildRateLimitWarnings(_ payload: [String: Any]) -> [ProviderWarning] {
        rateLimitCategories.compactMap { key, label in
            guard let value = Self.doubleValue(payload[key]) else { return nil }
            return ProviderWarning(level: .info, message: "\(label): \(max(0, Int(value.rounded(.down)))) remaining")
        }
    }

    private func makeWindow(kind: WindowKind, used: Double, limit: Double, resetAt: Date?) -> Window {
        let percentage = limit > 0 ? min(100, max(0, (used / limit) * 100)) : 0
        return Window(kind: kind, used: used, limit: limit, unit: .dollars, percentage: percentage, resetAt: resetAt)
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
        if let value = value as? String {
            let cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "$", with: "").replacingOccurrences(of: ",", with: "")
            return Double(cleaned)
        }
        return nil
    }
}

private struct PerplexitySessionState {
    let authToken: String
    let userAgent: String?
    let appVersion: String?
    let deviceID: String?
    let sourcePath: URL
}

private struct PerplexityRestState {
    let groupID: String
    let group: Any?
    let usageAnalytics: Any?
    let rateLimits: [String: Any]?
}