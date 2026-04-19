import Foundation

final class AntigravityProvider: UsageProvider {
    static let identifier = "antigravity"
    static let displayName = "Antigravity"
    static let category: ProviderCategory = .subscription

    private let defaults = UserDefaults.standard
    private let sqlite = SQLiteReader()
    private let session = URLSession(configuration: .ephemeral)

    private let stateDatabaseURL = FileManager.default.homeDirectoryForCurrentUser
        .appending(path: "Library/Application Support/Antigravity/User/globalStorage/state.vscdb")
    private let cloudCodeBaseURLs = [
        "https://daily-cloudcode-pa.googleapis.com",
        "https://cloudcode-pa.googleapis.com"
    ]
    private let fetchAvailableModelsPath = "/v1internal:fetchAvailableModels"
    private let tokenURL = URL(string: "https://oauth2.googleapis.com/token")!
    private let googleClientID = "1071006060591-tmhssin2h21lcre235vtolojh4g403ep.apps.googleusercontent.com"
    private let googleClientSecret = "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"
    private let refreshBuffer: TimeInterval = 5 * 60
    private let blacklistedModelIDs: Set<String> = [
        "MODEL_CHAT_20706",
        "MODEL_CHAT_23310",
        "MODEL_GOOGLE_GEMINI_2_5_FLASH",
        "MODEL_GOOGLE_GEMINI_2_5_FLASH_THINKING",
        "MODEL_GOOGLE_GEMINI_2_5_FLASH_LITE",
        "MODEL_GOOGLE_GEMINI_2_5_PRO",
        "MODEL_PLACEHOLDER_M19",
        "MODEL_PLACEHOLDER_M9",
        "MODEL_PLACEHOLDER_M12"
    ]

    var isEnabled: Bool {
        get { defaults.object(forKey: "provider.antigravity.enabled") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "provider.antigravity.enabled") }
    }

    var profiles: [ProviderProfile] { [ProviderProfile(name: "Antigravity")] }
    var activeProfile: ProviderProfile? = ProviderProfile(name: "Antigravity")

    func isAvailable() async -> Bool {
        FileManager.default.fileExists(atPath: stateDatabaseURL.path)
    }

    func probe() async throws -> ProviderResult {
        guard FileManager.default.fileExists(atPath: stateDatabaseURL.path) else {
            return .unavailable(
                identifier: Self.identifier,
                displayName: Self.displayName,
                category: Self.category,
                warning: "Start Antigravity and sign in, then try again."
            )
        }

        let apiKey = loadAPIKey()
        var protoTokens = loadProtoTokens()
        let tokens = candidateAccessTokens(apiKey: apiKey, protoTokens: protoTokens)

        var payload = try await fetchAvailableModels(using: tokens)
        if payload == nil, let refreshToken = protoTokens?.refreshToken,
           let refreshedToken = try await refreshAccessToken(refreshToken) {
            protoTokens?.accessToken = refreshedToken
            payload = try await fetchAvailableModels(using: [refreshedToken])
        }

        guard let payload else {
            return .unavailable(
                identifier: Self.identifier,
                displayName: Self.displayName,
                category: Self.category,
                warning: "Start Antigravity and sign in, then try again."
            )
        }

        let windows = parseWindows(from: payload)
        return ProviderResult(
            identifier: Self.identifier,
            displayName: Self.displayName,
            category: Self.category,
            profile: activeProfile?.name ?? "Antigravity",
            windows: windows,
            today: .zero,
            burnRate: nil,
            dailyHeatmap: [],
            models: [],
            source: .api,
            freshness: Date(),
            warnings: windows.isEmpty
                ? [ProviderWarning(level: .info, message: "Antigravity returned no quota windows.")]
                : []
        )
    }

    private func loadAPIKey() -> String? {
        guard let raw = loadStateValue(forKey: "antigravityAuthStatus"),
              let payload = jsonObject(from: raw) else {
            return nil
        }
        return stringValue(payload["apiKey"])
    }

    private func loadProtoTokens() -> AntigravityProtoTokens? {
        guard let raw = loadStateValue(forKey: "jetskiStateSync.agentManagerInitState"),
              let data = Data(base64Encoded: raw, options: [.ignoreUnknownCharacters]) else {
            return nil
        }

        let outerFields = protobufFields(in: data)
        guard let nested = outerFields[6]?.data else { return nil }

        let innerFields = protobufFields(in: nested)
        let accessToken = innerFields[1]?.data.flatMap { String(data: $0, encoding: .utf8) }
        let refreshToken = innerFields[3]?.data.flatMap { String(data: $0, encoding: .utf8) }

        var expirySeconds: Double?
        if let timestampData = innerFields[4]?.data {
            let timestampFields = protobufFields(in: timestampData)
            expirySeconds = timestampFields[1]?.integer.map(Double.init)
        }

        guard accessToken != nil || refreshToken != nil else { return nil }
        return AntigravityProtoTokens(accessToken: accessToken, refreshToken: refreshToken, expirySeconds: expirySeconds)
    }

    private func candidateAccessTokens(apiKey: String?, protoTokens: AntigravityProtoTokens?) -> [String] {
        var tokens: [String] = []
        if let accessToken = protoTokens?.accessToken, !needsRefresh(protoTokens) {
            tokens.append(accessToken)
        }
        if let apiKey, !apiKey.isEmpty, !tokens.contains(apiKey) {
            tokens.append(apiKey)
        }
        return tokens
    }

    private func needsRefresh(_ protoTokens: AntigravityProtoTokens?) -> Bool {
        guard let expirySeconds = protoTokens?.expirySeconds else { return protoTokens?.accessToken == nil }
        return Date().addingTimeInterval(refreshBuffer).timeIntervalSince1970 >= expirySeconds
    }

    private func fetchAvailableModels(using tokens: [String]) async throws -> [String: Any]? {
        for token in tokens where !token.isEmpty {
            if let payload = try await fetchAvailableModels(accessToken: token) {
                return payload
            }
        }
        return nil
    }

    private func fetchAvailableModels(accessToken: String) async throws -> [String: Any]? {
        for baseURL in cloudCodeBaseURLs {
            guard let url = URL(string: baseURL + fetchAvailableModelsPath) else { continue }

            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.timeoutInterval = 15
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
            request.setValue("antigravity", forHTTPHeaderField: "User-Agent")
            request.httpBody = "{}".data(using: .utf8)

            do {
                let (data, response) = try await session.data(for: request)
                let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 500

                if statusCode == 401 || statusCode == 403 {
                    return nil
                }

                guard (200...299).contains(statusCode),
                      let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    continue
                }

                return payload
            } catch {
                continue
            }
        }

        return nil
    }

    private func refreshAccessToken(_ refreshToken: String) async throws -> String? {
        var request = URLRequest(url: tokenURL)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = [
            "client_id=\(urlEncode(googleClientID))",
            "client_secret=\(urlEncode(googleClientSecret))",
            "refresh_token=\(urlEncode(refreshToken))",
            "grant_type=refresh_token"
        ]
        .joined(separator: "&")
        .data(using: .utf8)

        let (data, response) = try await session.data(for: request)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 500
        guard (200...299).contains(statusCode),
              let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return stringValue(payload["access_token"])
    }

    private func parseWindows(from payload: [String: Any]) -> [Window] {
        guard let models = payload["models"] as? [String: Any] else { return [] }

        var grouped: [String: AntigravityQuota] = [:]
        for value in models.values {
            guard let object = value as? [String: Any],
                  object["isInternal"] as? Bool != true else {
                continue
            }

            let modelID = stringValue(object["model"]) ?? ""
            if blacklistedModelIDs.contains(modelID) { continue }

            guard let displayName = stringValue(object["displayName"]), !displayName.isEmpty else {
                continue
            }

            let quotaInfo = object["quotaInfo"] as? [String: Any]
            let remainingFraction = numberValue(quotaInfo?["remainingFraction"]) ?? 0
            let label = poolLabel(for: normalizeLabel(displayName))
            let quota = AntigravityQuota(
                label: label,
                remainingFraction: remainingFraction,
                resetAt: parseDate(quotaInfo?["resetTime"])
            )

            if let existing = grouped[label] {
                if quota.remainingFraction < existing.remainingFraction {
                    grouped[label] = quota
                }
            } else {
                grouped[label] = quota
            }
        }

        return grouped.values
            .sorted { lhs, rhs in
                sortKey(for: lhs.label) < sortKey(for: rhs.label)
            }
            .map { quota in
                let usedPercentage = max(0, min(100, (1 - quota.remainingFraction) * 100))
                return Window(
                    kind: .custom(quota.label),
                    used: usedPercentage,
                    limit: 100,
                    unit: .requests,
                    percentage: usedPercentage,
                    resetAt: quota.resetAt
                )
            }
    }

    private func normalizeLabel(_ label: String) -> String {
        label.replacingOccurrences(of: #"\s*\([^)]*\)\s*$"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func poolLabel(for label: String) -> String {
        let lowercased = label.lowercased()
        if lowercased.contains("gemini") && lowercased.contains("pro") {
            return "Gemini Pro"
        }
        if lowercased.contains("gemini") && lowercased.contains("flash") {
            return "Gemini Flash"
        }
        return "Claude"
    }

    private func sortKey(for label: String) -> String {
        let lowercased = label.lowercased()
        if lowercased.contains("gemini") && lowercased.contains("pro") { return "0_\(label)" }
        if lowercased.contains("gemini") { return "1_\(label)" }
        if lowercased.contains("claude") { return "2_\(label)" }
        return "3_\(label)"
    }

    private func loadStateValue(forKey key: String) -> String? {
        let sql = "SELECT value FROM ItemTable WHERE key = '\(key.replacingOccurrences(of: "'", with: "''"))' LIMIT 1;"
        return try? sqlite.query(databaseURL: stateDatabaseURL, sql: sql).first?["value"]
    }

    private func jsonObject(from string: String) -> [String: Any]? {
        guard let data = string.data(using: .utf8),
              let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return payload
    }

    private func parseDate(_ value: Any?) -> Date? {
        if let string = stringValue(value), let date = TimeHelpers.parseISODate(string) {
            return date
        }
        if let seconds = numberValue(value) {
            return Date(timeIntervalSince1970: seconds)
        }
        return nil
    }

    private func stringValue(_ value: Any?) -> String? {
        if let string = value as? String, !string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return string.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return nil
    }

    private func numberValue(_ value: Any?) -> Double? {
        if let double = value as? Double { return double }
        if let int = value as? Int { return Double(int) }
        if let number = value as? NSNumber { return number.doubleValue }
        if let string = value as? String { return Double(string) }
        return nil
    }

    private func urlEncode(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed.subtracting(CharacterSet(charactersIn: ":/?#[]@!$&'()*+,;="))) ?? value
    }

    private func protobufFields(in data: Data) -> [Int: AntigravityProtobufField] {
        var fields: [Int: AntigravityProtobufField] = [:]
        var index = 0
        let bytes = [UInt8](data)

        while index < bytes.count {
            guard let (tag, nextIndex) = readVarint(bytes, from: index) else { break }
            index = nextIndex

            let fieldNumber = Int(tag / 8)
            let wireType = Int(tag % 8)
            switch wireType {
            case 0:
                guard let (value, valueIndex) = readVarint(bytes, from: index) else { break }
                fields[fieldNumber] = AntigravityProtobufField(integer: value, data: nil)
                index = valueIndex
            case 2:
                guard let (length, lengthIndex) = readVarint(bytes, from: index) else { break }
                index = lengthIndex
                let end = min(bytes.count, index + Int(length))
                fields[fieldNumber] = AntigravityProtobufField(integer: nil, data: Data(bytes[index..<end]))
                index = end
            default:
                return fields
            }
        }

        return fields
    }

    private func readVarint(_ bytes: [UInt8], from startIndex: Int) -> (UInt64, Int)? {
        var result: UInt64 = 0
        var shift: UInt64 = 0
        var index = startIndex

        while index < bytes.count {
            let byte = bytes[index]
            result |= UInt64(byte & 0x7F) << shift
            index += 1

            if byte & 0x80 == 0 {
                return (result, index)
            }

            shift += 7
        }

        return nil
    }
}

private struct AntigravityProtoTokens {
    var accessToken: String?
    var refreshToken: String?
    var expirySeconds: Double?
}

private struct AntigravityQuota {
    let label: String
    let remainingFraction: Double
    let resetAt: Date?
}

private struct AntigravityProtobufField {
    let integer: UInt64?
    let data: Data?
}