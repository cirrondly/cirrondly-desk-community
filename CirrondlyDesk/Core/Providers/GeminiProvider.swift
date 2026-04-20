import Foundation

final class GeminiProvider: UsageProvider {
    static let identifier = "gemini"
    static let displayName = "Gemini"
    static let category: ProviderCategory = .api

    private let defaults = UserDefaults.standard
    private let session = URLSession(configuration: .ephemeral)
    private let settingsPath = FileManager.default.homeDirectoryForCurrentUser.appending(path: ".gemini/settings.json")
    private let credsPath = FileManager.default.homeDirectoryForCurrentUser.appending(path: ".gemini/oauth_creds.json")
    private let loadCodeAssistURL = URL(string: "https://cloudcode-pa.googleapis.com/v1internal:loadCodeAssist")!
    private let quotaURL = URL(string: "https://cloudcode-pa.googleapis.com/v1internal:retrieveUserQuota")!
    private let projectsURL = URL(string: "https://cloudresourcemanager.googleapis.com/v1/projects")!
    private let tokenURL = URL(string: "https://oauth2.googleapis.com/token")!
    private let refreshBuffer: TimeInterval = 5 * 60
    private let staticModuleRoots = [
        ".bun/install/global/node_modules",
        ".npm-global/lib/node_modules",
        "/usr/local/lib/node_modules",
        "Library/pnpm/global/5/node_modules"
    ]
    private let staticNestedOnly = [
        "/opt/homebrew/opt/gemini-cli/libexec/lib/node_modules",
        "/usr/local/opt/gemini-cli/libexec/lib/node_modules"
    ]

    var isEnabled: Bool {
        get { defaults.object(forKey: "provider.gemini.enabled") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "provider.gemini.enabled") }
    }

    var profiles: [ProviderProfile] { [ProviderProfile(name: "Default")] }
    var activeProfile: ProviderProfile? = ProviderProfile(name: "Default")

    func isAvailable() async -> Bool {
        FileManager.default.fileExists(atPath: settingsPath.path) || FileManager.default.fileExists(atPath: credsPath.path)
    }

    func probe() async throws -> ProviderResult {
        try assertSupportedAuthType()
        guard var creds = loadOAuthCreds() else {
            return .unavailable(identifier: Self.identifier, displayName: Self.displayName, category: Self.category, warning: "Not logged in. Run gemini auth login to authenticate.")
        }

        var accessToken = creds.accessToken
        if needsRefresh(creds) {
            if let refreshed = try await refreshToken(&creds) {
                accessToken = refreshed
            } else if accessToken == nil {
                return .unavailable(identifier: Self.identifier, displayName: Self.displayName, category: Self.category, warning: "Not logged in. Run gemini auth login to authenticate.")
            }
        }

        guard let currentToken = accessToken else {
            return .unavailable(identifier: Self.identifier, displayName: Self.displayName, category: Self.category, warning: "Not logged in. Run gemini auth login to authenticate.")
        }

        var token = currentToken
        let loadCodeAssistData = try await fetchLoadCodeAssist(accessToken: &token, creds: &creds)
        let idPayload = creds.idToken.flatMap(JWTUtilities.decodePayload)
        let tier = firstStringDeep(in: loadCodeAssistData, keys: ["tier", "userTier", "subscriptionTier"])
        let plan = mapTierToPlan(tier, idPayload: idPayload)
        let projectId = try await discoverProjectID(accessToken: token, loadCodeAssistData: loadCodeAssistData)
        let quotaData = try await fetchQuota(accessToken: &token, creds: &creds, projectID: projectId)
        let windows = parseQuotaWindows(quotaData)
        let email = idPayload.flatMap { stringValue($0["email"]) }

        return ProviderResult(
            identifier: Self.identifier,
            displayName: Self.displayName,
            category: Self.category,
            profile: email ?? plan ?? activeProfile?.name ?? "Default",
            windows: windows,
            today: .zero,
            burnRate: nil,
            dailyHeatmap: [],
            models: [],
            source: .api,
            freshness: Date(),
            warnings: windows.isEmpty ? [ProviderWarning(level: .info, message: "Gemini returned no quota data.")] : []
        )
    }

    private func assertSupportedAuthType() throws {
        guard let settings = loadSettings(), let authType = stringValue(settings["authType"])?.lowercased() else {
            return
        }

        switch authType {
        case "oauth-personal":
            return
        case "api-key":
            throw NSError(domain: "GeminiProvider", code: 1, userInfo: [NSLocalizedDescriptionKey: "Gemini auth type api-key is not supported by this provider yet."])
        case "vertex-ai":
            throw NSError(domain: "GeminiProvider", code: 2, userInfo: [NSLocalizedDescriptionKey: "Gemini auth type vertex-ai is not supported by this provider yet."])
        default:
            throw NSError(domain: "GeminiProvider", code: 3, userInfo: [NSLocalizedDescriptionKey: "Gemini unsupported auth type: \(authType)"])
        }
    }

    private func loadSettings() -> [String: Any]? {
        guard let data = try? Data(contentsOf: settingsPath),
              let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return payload
    }

    private func loadOAuthCreds() -> GeminiCreds? {
        guard let data = try? Data(contentsOf: credsPath),
              let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        let accessToken = stringValue(payload["access_token"])
        let refreshToken = stringValue(payload["refresh_token"])
        guard accessToken != nil || refreshToken != nil else { return nil }
        return GeminiCreds(
            accessToken: accessToken,
            refreshToken: refreshToken,
            idToken: stringValue(payload["id_token"]),
            expiryDate: numberValue(payload["expiry_date"])
        )
    }

    private func saveOAuthCreds(_ creds: GeminiCreds) {
        let payload: [String: Any] = [
            "access_token": creds.accessToken as Any,
            "refresh_token": creds.refreshToken as Any,
            "id_token": creds.idToken as Any,
            "expiry_date": creds.expiryDate as Any
        ]
        guard JSONSerialization.isValidJSONObject(payload),
              let data = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys]) else {
            return
        }
        try? data.write(to: credsPath)
    }

    private func needsRefresh(_ creds: GeminiCreds) -> Bool {
        guard let accessToken = creds.accessToken else { return true }
        guard let expiry = creds.expiryDate else { return false }
        let expiryTime = expiry > 10_000_000_000 ? expiry / 1000 : expiry
        _ = accessToken
        return Date().addingTimeInterval(refreshBuffer).timeIntervalSince1970 >= expiryTime
    }

    private func refreshToken(_ creds: inout GeminiCreds) async throws -> String? {
        guard let refreshToken = creds.refreshToken, let clientCreds = loadOAuthClientCreds() else { return nil }
        var request = URLRequest(url: tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let body = "client_id=\(urlEncode(clientCreds.clientID))&client_secret=\(urlEncode(clientCreds.clientSecret))&refresh_token=\(urlEncode(refreshToken))&grant_type=refresh_token"
        request.httpBody = body.data(using: .utf8)

        let (data, response) = try await session.data(for: request)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 500
        if statusCode == 401 || statusCode == 403 {
            throw NSError(domain: "GeminiProvider", code: statusCode, userInfo: [NSLocalizedDescriptionKey: "Gemini session expired. Run gemini auth login to authenticate."])
        }
        guard (200...299).contains(statusCode),
              let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let accessToken = stringValue(payload["access_token"]) else {
            return nil
        }

        creds.accessToken = accessToken
        if let idToken = stringValue(payload["id_token"]) { creds.idToken = idToken }
        if let refreshToken = stringValue(payload["refresh_token"]) { creds.refreshToken = refreshToken }
        if let expiresIn = numberValue(payload["expires_in"]) {
            creds.expiryDate = Date().addingTimeInterval(expiresIn).timeIntervalSince1970 * 1000
        }
        saveOAuthCreds(creds)
        return accessToken
    }

    private func loadOAuthClientCreds() -> GeminiClientCreds? {
        for candidate in oauthCandidatePaths() {
            guard FileManager.default.fileExists(atPath: candidate.path),
                  let text = try? String(contentsOf: candidate, encoding: .utf8) else { continue }
            if let parsed = parseOAuthClientCreds(text) {
                return parsed
            }
        }
        return nil
    }

    private func oauthCandidatePaths() -> [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let flatSuffix = "/@google/gemini-cli-core/dist/src/code_assist/oauth2.js"
        let nestedSuffix = "/@google/gemini-cli/node_modules/@google/gemini-cli-core/dist/src/code_assist/oauth2.js"
        var paths: [URL] = []

        for root in staticModuleRoots {
            let base = root.hasPrefix("/") ? URL(fileURLWithPath: root) : home.appending(path: root)
            paths.append(URL(fileURLWithPath: base.path + flatSuffix))
            paths.append(URL(fileURLWithPath: base.path + nestedSuffix))
        }

        for root in staticNestedOnly {
            paths.append(URL(fileURLWithPath: root + nestedSuffix))
        }

        let versionManagers: [(String, String)] = [
            (".nvm/versions/node", "/lib/node_modules"),
            ("Library/Application Support/fnm/node-versions", "/installation/lib/node_modules")
        ]
        for (root, modulePath) in versionManagers {
            let baseRoot = home.appending(path: root, directoryHint: .isDirectory)
            guard let versions = try? FileManager.default.contentsOfDirectory(at: baseRoot, includingPropertiesForKeys: nil) else { continue }
            for version in versions {
                paths.append(URL(fileURLWithPath: version.path + modulePath + flatSuffix))
                paths.append(URL(fileURLWithPath: version.path + modulePath + nestedSuffix))
            }
        }

        paths.append(home.appending(path: ".volta/tools/image/packages/@google/gemini-cli/lib/node_modules" + nestedSuffix))
        paths.append(home.appending(path: ".volta/tools/image/packages/@google/gemini-cli/lib/node_modules" + flatSuffix))
        return paths
    }

    private func parseOAuthClientCreds(_ text: String) -> GeminiClientCreds? {
        guard let idRegex = try? NSRegularExpression(pattern: #"OAUTH_CLIENT_ID\s*=\s*['\"]([^'\"]+)['\"]"#),
              let secretRegex = try? NSRegularExpression(pattern: #"OAUTH_CLIENT_SECRET\s*=\s*['\"]([^'\"]+)['\"]"#),
              let idMatch = idRegex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let secretMatch = secretRegex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let idRange = Range(idMatch.range(at: 1), in: text),
              let secretRange = Range(secretMatch.range(at: 1), in: text) else {
            return nil
        }
        return GeminiClientCreds(clientID: String(text[idRange]), clientSecret: String(text[secretRange]))
    }

    private func fetchLoadCodeAssist(accessToken: inout String, creds: inout GeminiCreds) async throws -> [String: Any]? {
        let response = try await postJSONWithRetry(url: loadCodeAssistURL, accessToken: &accessToken, creds: &creds, body: ["metadata": [
            "ideType": "IDE_UNSPECIFIED",
            "platform": "PLATFORM_UNSPECIFIED",
            "pluginType": "GEMINI",
            "duetProject": "default"
        ]])
        return response
    }

    private func fetchQuota(accessToken: inout String, creds: inout GeminiCreds, projectID: String?) async throws -> [String: Any] {
        let body = projectID.map { ["project": $0] } ?? [:]
        guard let response = try await postJSONWithRetry(url: quotaURL, accessToken: &accessToken, creds: &creds, body: body) else {
            throw NSError(domain: "GeminiProvider", code: 4, userInfo: [NSLocalizedDescriptionKey: "Gemini quota response invalid. Try again later."])
        }
        return response
    }

    private func postJSONWithRetry(url: URL, accessToken: inout String, creds: inout GeminiCreds, body: [String: Any]) async throws -> [String: Any]? {
        var response = try await postJSON(url: url, accessToken: accessToken, body: body)
        if response.statusCode == 401 || response.statusCode == 403, let refreshed = try await refreshToken(&creds) {
            accessToken = refreshed
            response = try await postJSON(url: url, accessToken: refreshed, body: body)
        }
        if response.statusCode == 401 || response.statusCode == 403 {
            throw NSError(domain: "GeminiProvider", code: response.statusCode, userInfo: [NSLocalizedDescriptionKey: "Gemini session expired. Run gemini auth login to authenticate."])
        }
        guard (200...299).contains(response.statusCode) else {
            throw NSError(domain: "GeminiProvider", code: response.statusCode, userInfo: [NSLocalizedDescriptionKey: "Gemini quota request failed (HTTP \(response.statusCode)). Try again later."])
        }
        return try? JSONSerialization.jsonObject(with: response.data) as? [String: Any]
    }

    private func postJSON(url: URL, accessToken: String, body: [String: Any]) async throws -> (data: Data, statusCode: Int) {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 10
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)
        return (data, (response as? HTTPURLResponse)?.statusCode ?? 500)
    }

    private func discoverProjectID(accessToken: String, loadCodeAssistData: [String: Any]?) async throws -> String? {
        if let project = firstStringDeep(in: loadCodeAssistData, keys: ["cloudaicompanionProject"]) {
            return project
        }

        var request = URLRequest(url: projectsURL)
        request.httpMethod = "GET"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 10
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode),
              let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let projects = payload["projects"] as? [[String: Any]] else {
            return nil
        }

        for project in projects {
            if let projectID = stringValue(project["projectId"]), projectID.hasPrefix("gen-lang-client") {
                return projectID
            }
            if let labels = project["labels"] as? [String: Any], labels["generative-language"] != nil {
                return stringValue(project["projectId"])
            }
        }
        return nil
    }

    private func parseQuotaWindows(_ payload: [String: Any]) -> [Window] {
        var buckets: [GeminiBucket] = []
        collectQuotaBuckets(payload, into: &buckets)
        let pro = lowestRemaining(in: buckets.filter { $0.modelID.contains("gemini") && $0.modelID.contains("pro") })
        let flash = lowestRemaining(in: buckets.filter { $0.modelID.contains("gemini") && $0.modelID.contains("flash") })

        return [
            pro.map { makeQuotaWindow(label: "Pro", bucket: $0) },
            flash.map { makeQuotaWindow(label: "Flash", bucket: $0) }
        ].compactMap { $0 }
    }

    private func collectQuotaBuckets(_ value: Any, into output: inout [GeminiBucket]) {
        if let array = value as? [Any] {
            array.forEach { collectQuotaBuckets($0, into: &output) }
            return
        }

        guard let object = value as? [String: Any] else { return }
        if let remainingFraction = numberValue(object["remainingFraction"]) {
            let modelID = stringValue(object["modelId"]) ?? stringValue(object["model_id"]) ?? "unknown"
            output.append(GeminiBucket(modelID: modelID.lowercased(), remainingFraction: remainingFraction, resetTime: firstDate(object["resetTime"], object["reset_time"])))
        }

        object.values.forEach { collectQuotaBuckets($0, into: &output) }
    }

    private func lowestRemaining(in buckets: [GeminiBucket]) -> GeminiBucket? {
        buckets.min { $0.remainingFraction < $1.remainingFraction }
    }

    private func makeQuotaWindow(label: String, bucket: GeminiBucket) -> Window {
        let remaining = min(max(bucket.remainingFraction, 0), 1)
        let used = (1 - remaining) * 100
        return Window(kind: .custom(label), used: used, limit: 100, unit: .requests, percentage: used, resetAt: bucket.resetTime, windowStart: bucket.resetTime?.addingTimeInterval(-24 * 60 * 60))
    }

    private func mapTierToPlan(_ tier: String?, idPayload: [String: Any]?) -> String? {
        guard let tier else { return nil }
        switch tier.lowercased() {
        case "standard-tier":
            return "Paid"
        case "legacy-tier":
            return "Legacy"
        case "free-tier":
            return idPayload?["hd"] != nil ? "Workspace" : "Free"
        default:
            return nil
        }
    }

    private func firstStringDeep(in value: Any?, keys: [String]) -> String? {
        guard let value else { return nil }
        if let object = value as? [String: Any] {
            for key in keys {
                if let string = stringValue(object[key]) { return string }
            }
            for nested in object.values {
                if let found = firstStringDeep(in: nested, keys: keys) { return found }
            }
        } else if let array = value as? [Any] {
            for nested in array {
                if let found = firstStringDeep(in: nested, keys: keys) { return found }
            }
        }
        return nil
    }

    private func firstDate(_ values: Any?...) -> Date? {
        for value in values {
            if let string = stringValue(value), let date = TimeHelpers.parseISODate(string) {
                return date
            }
        }
        return nil
    }

    private func numberValue(_ value: Any?) -> Double? {
        if let double = value as? Double, double.isFinite { return double }
        if let int = value as? Int { return Double(int) }
        if let string = value as? String, let double = Double(string), double.isFinite { return double }
        return nil
    }

    private func urlEncode(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? value
    }
}

private struct GeminiCreds {
    var accessToken: String?
    var refreshToken: String?
    var idToken: String?
    var expiryDate: Double?
}

private struct GeminiClientCreds {
    let clientID: String
    let clientSecret: String
}

private struct GeminiBucket {
    let modelID: String
    let remainingFraction: Double
    let resetTime: Date?
}