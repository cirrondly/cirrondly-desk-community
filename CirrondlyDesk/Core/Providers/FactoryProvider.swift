import CryptoKit
import Foundation

final class FactoryProvider: UsageProvider {
    static let identifier = "factory"
    static let displayName = "Factory"
    static let category: ProviderCategory = .subscription

    private let defaults = UserDefaults.standard
    private let keychainService: KeychainService
    private let session = URLSession(configuration: .ephemeral)
    private let authV2URL = FileManager.default.homeDirectoryForCurrentUser.appending(path: ".factory/auth.v2.file")
    private let authV2KeyURL = FileManager.default.homeDirectoryForCurrentUser.appending(path: ".factory/auth.v2.key")
    private let fallbackAuthURLs = [
        FileManager.default.homeDirectoryForCurrentUser.appending(path: ".factory/auth.encrypted"),
        FileManager.default.homeDirectoryForCurrentUser.appending(path: ".factory/auth.json")
    ]
    private let keychainServices = ["Factory Token", "Factory token", "Factory Auth", "Droid Auth"]
    private let workOSClientID = "client_01HNM792M5G5G1A2THWPXKFMXB"
    private let workOSAuthURL = URL(string: "https://api.workos.com/user_management/authenticate")!
    private let usageURL = URL(string: "https://api.factory.ai/api/organization/subscription/usage")!
    private let tokenRefreshThreshold: TimeInterval = 24 * 60 * 60

    init(keychainService: KeychainService) {
        self.keychainService = keychainService
    }

    var isEnabled: Bool {
        get { defaults.object(forKey: "provider.factory.enabled") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "provider.factory.enabled") }
    }

    var profiles: [ProviderProfile] { [ProviderProfile(name: "Default")] }
    var activeProfile: ProviderProfile? = ProviderProfile(name: "Default")

    func isAvailable() async -> Bool {
        FileManager.default.fileExists(atPath: authV2URL.path)
            || FileManager.default.fileExists(atPath: authV2KeyURL.path)
            || fallbackAuthURLs.contains { FileManager.default.fileExists(atPath: $0.path) }
            || keychainServices.contains { keychainService.readAny(service: $0) != nil }
    }

    func probe() async throws -> ProviderResult {
        guard var authState = loadAuthState() else {
            return .unavailable(
                identifier: Self.identifier,
                displayName: Self.displayName,
                category: Self.category,
                warning: "Not logged in. Run droid to authenticate."
            )
        }

        guard var accessToken = authState.auth.accessToken else {
            return .unavailable(
                identifier: Self.identifier,
                displayName: Self.displayName,
                category: Self.category,
                warning: "Invalid auth file. Run droid to authenticate."
            )
        }

        let now = Date()
        if needsRefresh(accessToken: accessToken, now: now) {
            do {
                if let refreshed = try await refreshAuth(&authState) {
                    accessToken = refreshed
                }
            } catch {
                if !canUseExistingAccessToken(accessToken: accessToken, now: now) {
                    return .unavailable(
                        identifier: Self.identifier,
                        displayName: Self.displayName,
                        category: Self.category,
                        warning: error.localizedDescription
                    )
                }
            }
        }

        let response = try await fetchUsage(accessToken: accessToken, authState: &authState)
        if response.statusCode == 401 || response.statusCode == 403 {
            return .unavailable(
                identifier: Self.identifier,
                displayName: Self.displayName,
                category: Self.category,
                warning: "Token expired. Run droid to log in again."
            )
        }

        guard (200...299).contains(response.statusCode), let usage = response.payload?["usage"] as? [String: Any] else {
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
                source: .api,
                freshness: Date(),
                warnings: [ProviderWarning(level: .info, message: "Factory usage response was unavailable.")]
            )
        }

        let resetAt = Self.dateFromEpochMilliseconds(usage["endDate"])
        let startDate = Self.dateFromEpochMilliseconds(usage["startDate"])
        let periodDuration = (startDate != nil && resetAt != nil) ? resetAt!.timeIntervalSince(startDate!) : nil
        _ = periodDuration

        var windows: [Window] = []
        if let standard = usage["standard"] as? [String: Any],
           let limit = Self.doubleValue(standard["totalAllowance"]),
           limit > 0 {
            let used = Self.doubleValue(standard["orgTotalTokensUsed"]) ?? 0
            windows.append(makeWindow(kind: .custom("Standard"), used: used, limit: limit, resetAt: resetAt, windowStart: startDate))
        }

        if let premium = usage["premium"] as? [String: Any],
           let limit = Self.doubleValue(premium["totalAllowance"]),
           limit > 0 {
            let used = Self.doubleValue(premium["orgTotalTokensUsed"]) ?? 0
            windows.append(makeWindow(kind: .custom("Premium"), used: used, limit: limit, resetAt: resetAt, windowStart: startDate))
        }

        return ProviderResult(
            identifier: Self.identifier,
            displayName: Self.displayName,
            category: Self.category,
            profile: inferPlan(usage: usage) ?? activeProfile?.name ?? "Default",
            windows: windows,
            today: .zero,
            burnRate: nil,
            dailyHeatmap: [],
            models: [],
            source: .api,
            freshness: Date(),
            warnings: windows.isEmpty ? [ProviderWarning(level: .info, message: "Factory returned no usage data.")] : []
        )
    }

    private func loadAuthState() -> FactoryAuthState? {
        if let state = loadAuthFromV2File() { return state }

        for path in fallbackAuthURLs where FileManager.default.fileExists(atPath: path.path) {
            guard let text = try? String(contentsOf: path, encoding: .utf8),
                  let auth = parseAuthPayload(rawText: text, allowPartial: true) else {
                continue
            }
            return FactoryAuthState(auth: auth, source: .file(path))
        }

        for service in keychainServices {
            guard let raw = keychainService.readAny(service: service),
                  let auth = parseAuthPayload(rawText: raw, allowPartial: true) else {
                continue
            }
            return FactoryAuthState(auth: auth, source: .keychain(service))
        }

        return nil
    }

    private func loadAuthFromV2File() -> FactoryAuthState? {
        guard FileManager.default.fileExists(atPath: authV2URL.path),
              FileManager.default.fileExists(atPath: authV2KeyURL.path),
              let envelope = try? String(contentsOf: authV2URL, encoding: .utf8),
              let keyB64 = try? String(contentsOf: authV2KeyURL, encoding: .utf8),
              let decrypted = decryptAes256GcmEnvelope(envelope: envelope, keyB64: keyB64),
              let auth = parseAuthPayload(rawText: decrypted, allowPartial: true) else {
            return nil
        }

        return FactoryAuthState(auth: auth, source: .fileV2(authV2URL, keyB64.trimmingCharacters(in: .whitespacesAndNewlines)))
    }

    private func parseAuthPayload(rawText: String, allowPartial: Bool = false) -> FactoryAuthPayload? {
        if let data = rawText.data(using: .utf8),
           let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let auth = normalizeAuthPayload(object, allowPartial: allowPartial) {
            return auth
        }

        var candidate = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        if candidate.hasPrefix("0x") || candidate.hasPrefix("0X") { candidate.removeFirst(2) }
        if candidate.count.isMultiple(of: 2), let hexData = decodeHexData(candidate),
           let text = String(data: hexData, encoding: .utf8),
           let data = text.data(using: .utf8),
           let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let auth = normalizeAuthPayload(object, allowPartial: allowPartial) {
            return auth
        }

        let direct = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        if looksLikeJWT(direct) {
            return FactoryAuthPayload(accessToken: direct, refreshToken: nil)
        }

        return nil
    }

    private func normalizeAuthPayload(_ object: [String: Any], allowPartial: Bool) -> FactoryAuthPayload? {
        let tokens = object["tokens"] as? [String: Any]
        let accessToken = Self.stringValue(object["access_token"])
            ?? Self.stringValue(object["accessToken"])
            ?? Self.stringValue(tokens?["access_token"])
            ?? Self.stringValue(tokens?["accessToken"])
        let refreshToken = Self.stringValue(object["refresh_token"])
            ?? Self.stringValue(object["refreshToken"])
            ?? Self.stringValue(tokens?["refresh_token"])
            ?? Self.stringValue(tokens?["refreshToken"])
        guard accessToken != nil || (allowPartial && refreshToken != nil) else { return nil }
        return FactoryAuthPayload(accessToken: accessToken, refreshToken: refreshToken)
    }

    private func needsRefresh(accessToken: String, now: Date) -> Bool {
        guard let exp = accessTokenExpiry(accessToken: accessToken) else { return true }
        return now.addingTimeInterval(tokenRefreshThreshold) >= exp
    }

    private func canUseExistingAccessToken(accessToken: String, now: Date) -> Bool {
        guard let exp = accessTokenExpiry(accessToken: accessToken) else { return false }
        return now < exp
    }

    private func accessTokenExpiry(accessToken: String) -> Date? {
        guard let payload = JWTUtilities.decodePayload(accessToken),
              let exp = Self.doubleValue(payload["exp"]) else {
            return nil
        }
        return Date(timeIntervalSince1970: exp)
    }

    private func refreshAuth(_ authState: inout FactoryAuthState) async throws -> String? {
        guard let refreshToken = authState.auth.refreshToken else { return nil }

        var request = URLRequest(url: workOSAuthURL)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = "grant_type=refresh_token&refresh_token=\(Self.urlEncode(refreshToken))&client_id=\(Self.urlEncode(workOSClientID))".data(using: .utf8)

        let (data, response) = try await session.data(for: request)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 500
        if statusCode == 400 || statusCode == 401 {
            throw NSError(domain: "FactoryProvider", code: statusCode, userInfo: [NSLocalizedDescriptionKey: "Session expired. Run droid to log in again."])
        }

        guard (200...299).contains(statusCode),
              let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let accessToken = Self.stringValue(payload["access_token"]) else {
            return nil
        }

        authState.auth.accessToken = accessToken
        if let refreshToken = Self.stringValue(payload["refresh_token"]) {
            authState.auth.refreshToken = refreshToken
        }
        saveAuthState(authState)
        return accessToken
    }

    private func saveAuthState(_ authState: FactoryAuthState) {
        let payload: [String: Any] = [
            "access_token": authState.auth.accessToken as Any,
            "refresh_token": authState.auth.refreshToken as Any
        ]
        guard JSONSerialization.isValidJSONObject(payload),
              let data = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys]),
              let text = String(data: data, encoding: .utf8) else {
            return
        }

        switch authState.source {
        case .file(let path):
            try? data.write(to: path)
        case .fileV2(let path, let keyB64):
            guard let envelope = encryptAes256GcmEnvelope(plaintext: text, keyB64: keyB64) else { return }
            try? envelope.write(to: path, atomically: true, encoding: .utf8)
        case .keychain(let service):
            try? keychainService.save(text, service: service, account: "auth")
        }
    }

    private func fetchUsage(accessToken: String, authState: inout FactoryAuthState) async throws -> FactoryUsageResponse {
        var response = try await rawFetchUsage(accessToken: accessToken)
        if (response.statusCode == 401 || response.statusCode == 403), let refreshed = try await refreshAuth(&authState) {
            response = try await rawFetchUsage(accessToken: refreshed)
        }
        return response
    }

    private func rawFetchUsage(accessToken: String) async throws -> FactoryUsageResponse {
        var request = URLRequest(url: usageURL)
        request.httpMethod = "POST"
        request.timeoutInterval = 10
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("OpenUsage", forHTTPHeaderField: "User-Agent")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["useCache": true])

        let (data, response) = try await session.data(for: request)
        let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        return FactoryUsageResponse(statusCode: (response as? HTTPURLResponse)?.statusCode ?? 500, payload: payload)
    }

    private func inferPlan(usage: [String: Any]) -> String? {
        guard let standard = usage["standard"] as? [String: Any],
              let allowance = Self.doubleValue(standard["totalAllowance"]) else {
            return nil
        }

        if allowance >= 200_000_000 { return "Max" }
        if allowance >= 20_000_000 { return "Pro" }
        if allowance > 0 { return "Basic" }
        return nil
    }

    private func makeWindow(kind: WindowKind, used: Double, limit: Double, resetAt: Date?, windowStart: Date?) -> Window {
        let percentage = limit > 0 ? min(100, max(0, (used / limit) * 100)) : 0
        return Window(kind: kind, used: used, limit: limit, unit: .tokens, percentage: percentage, resetAt: resetAt, windowStart: windowStart)
    }

    private func decryptAes256GcmEnvelope(envelope: String, keyB64: String) -> String? {
        let parts = envelope.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 3,
              let keyData = Data(base64Encoded: keyB64.trimmingCharacters(in: .whitespacesAndNewlines)),
              let ivData = Data(base64Encoded: String(parts[0])),
              let tagData = Data(base64Encoded: String(parts[1])),
              let cipherData = Data(base64Encoded: String(parts[2])) else {
            return nil
        }

        do {
            let key = SymmetricKey(data: keyData)
            let nonce = try AES.GCM.Nonce(data: ivData)
            let sealedBox = try AES.GCM.SealedBox(nonce: nonce, ciphertext: cipherData, tag: tagData)
            let plaintext = try AES.GCM.open(sealedBox, using: key)
            return String(data: plaintext, encoding: .utf8)
        } catch {
            return nil
        }
    }

    private func encryptAes256GcmEnvelope(plaintext: String, keyB64: String) -> String? {
        guard let keyData = Data(base64Encoded: keyB64.trimmingCharacters(in: .whitespacesAndNewlines)),
              let plaintextData = plaintext.data(using: .utf8) else {
            return nil
        }

        do {
            let key = SymmetricKey(data: keyData)
            let nonce = AES.GCM.Nonce()
            let sealedBox = try AES.GCM.seal(plaintextData, using: key, nonce: nonce)
            return [
                Data(sealedBox.nonce).base64EncodedString(),
                sealedBox.tag.base64EncodedString(),
                sealedBox.ciphertext.base64EncodedString()
            ].joined(separator: ":")
        } catch {
            return nil
        }
    }

    private func decodeHexData(_ value: String) -> Data? {
        guard value.count.isMultiple(of: 2) else { return nil }
        var data = Data(capacity: value.count / 2)
        var index = value.startIndex
        while index < value.endIndex {
            let next = value.index(index, offsetBy: 2)
            guard let byte = UInt8(value[index..<next], radix: 16) else { return nil }
            data.append(byte)
            index = next
        }
        return data
    }

    private func looksLikeJWT(_ value: String) -> Bool {
        value.range(of: #"^[A-Za-z0-9\-_]+\.[A-Za-z0-9\-_]+\.[A-Za-z0-9\-_]+$"#, options: .regularExpression) != nil
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

    private static func dateFromEpochMilliseconds(_ value: Any?) -> Date? {
        guard let numeric = doubleValue(value) else { return nil }
        return Date(timeIntervalSince1970: abs(numeric) < 10_000_000_000 ? numeric : numeric / 1000)
    }

    private static func urlEncode(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? value
    }
}

private struct FactoryAuthPayload {
    var accessToken: String?
    var refreshToken: String?
}

private struct FactoryAuthState {
    var auth: FactoryAuthPayload
    let source: FactoryAuthSource
}

private enum FactoryAuthSource {
    case file(URL)
    case fileV2(URL, String)
    case keychain(String)
}

private struct FactoryUsageResponse {
    let statusCode: Int
    let payload: [String: Any]?
}