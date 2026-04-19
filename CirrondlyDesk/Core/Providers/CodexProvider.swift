import Foundation

final class CodexProvider: UsageProvider {
    static let identifier = "codex"
    static let displayName = "Codex"
    static let category: ProviderCategory = .api

    private let calculator = BurnRateCalculator()
    private let sqlite = SQLiteReader()
    private let defaults = UserDefaults.standard
    private let keychainService: KeychainService
    private let session = URLSession(configuration: .ephemeral)
    private let refreshURL = URL(string: "https://auth.openai.com/oauth/token")!
    private let usageURL = URL(string: "https://chatgpt.com/backend-api/wham/usage")!
    private let authFile = "auth.json"
    private let keychainServiceName = "Codex Auth"
    private let refreshAge: TimeInterval = 8 * 24 * 60 * 60
    private let clientID = "app_EMoamEEZ73f0CkXaXp7hrann"

    init(keychainService: KeychainService) {
        self.keychainService = keychainService
    }

    var isEnabled: Bool {
        get { defaults.object(forKey: "provider.codex.enabled") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "provider.codex.enabled") }
    }

    var profiles: [ProviderProfile] { [ProviderProfile(name: "Default")] }
    var activeProfile: ProviderProfile? = ProviderProfile(name: "Default")

    func isAvailable() async -> Bool {
        let manager = FileManager.default
        let hasLocalFootprint = candidateAvailabilityPaths.contains { manager.fileExists(atPath: $0.path) }
        return hasLocalFootprint || loadAuthState() != nil
    }

    func probe() async throws -> ProviderResult {
        let sessions = try await loadSessions(since: Date().addingTimeInterval(-90 * 86_400))

        guard var authState = loadAuthState() else {
            if !sessions.isEmpty {
                return buildLocalHistoryResult(
                    sessions: sessions,
                    source: .local,
                    warnings: [ProviderWarning(level: .info, message: "Codex auth was not available, so the provider is using local session history only.")]
                )
            }

            return ProviderResult.unavailable(identifier: Self.identifier, displayName: Self.displayName, category: Self.category, warning: "Not logged in. Run codex to authenticate.")
        }

        do {
            if needsRefresh(authState.auth), let refreshed = try await refreshToken(&authState) {
                authState.auth = refreshed
            }

            if let token = accessToken(from: authState.auth) {
                let usageResponse = try await fetchUsage(accessTokenValue: token, accountIDValue: accountID(from: authState.auth), authState: &authState)
                if let result = buildQuotaResult(from: usageResponse, sessions: sessions) {
                    return result
                }
            }
        } catch {
            if !sessions.isEmpty {
                return buildLocalHistoryResult(
                    sessions: sessions,
                    source: .mixed,
                    warnings: [ProviderWarning(level: .info, message: "Codex live refresh failed, so the provider is using local session history only.")]
                )
            }

            throw error
        }

        guard !sessions.isEmpty else {
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
                source: .local,
                freshness: Date(),
                warnings: [ProviderWarning(level: .info, message: "Codex was detected, but neither quota nor local tokenized session data was available.")]
            )
        }

        return buildLocalHistoryResult(
            sessions: sessions,
            source: .mixed,
            warnings: [ProviderWarning(level: .info, message: "Codex quota request was unavailable, so the provider fell back to local session history.")]
        )
    }

    func sessions(since: Date) async throws -> [RawSession] {
        try await loadSessions(since: since)
    }

    private var codexRoots: [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let env = ProcessInfo.processInfo.environment["CODEX_HOME"]?.trimmingCharacters(in: .whitespacesAndNewlines)

        var roots: [URL] = []
        if let env, !env.isEmpty {
            roots.append(URL(fileURLWithPath: env, isDirectory: true))
        }
        roots.append(home.appending(path: ".codex", directoryHint: .isDirectory))
        roots.append(home.appending(path: ".config/codex", directoryHint: .isDirectory))

        var seen = Set<String>()
        return roots.filter { seen.insert($0.path).inserted }
    }

    private var codexRoot: URL {
        codexRoots.first ?? FileManager.default.homeDirectoryForCurrentUser.appending(path: ".codex", directoryHint: .isDirectory)
    }

    private var authPaths: [URL] {
        codexRoots.map { $0.appending(path: authFile) }
    }

    private var sessionsDirectories: [URL] {
        codexRoots.map { $0.appending(path: "sessions", directoryHint: .isDirectory) }
    }

    private var candidateAvailabilityPaths: [URL] {
        var paths = authPaths
        paths.append(contentsOf: sessionsDirectories)
        paths.append(contentsOf: codexRoots.map { $0.appending(path: "history.jsonl") })
        paths.append(contentsOf: codexRoots.map { $0.appending(path: "session_index.jsonl") })
        paths.append(contentsOf: codexRoots.map { $0.appending(path: "logs_2.sqlite") })
        paths.append(contentsOf: codexRoots.map { $0.appending(path: "config.toml") })
        return paths
    }

    private func loadSessions(since: Date) async throws -> [RawSession] {
        let urls = sessionFileURLs()
        var sessions: [RawSession] = []

        for url in urls {
            let rows = try await JSONLStreamReader.readObjects(at: url)
            for row in rows {
                guard let session = rawSession(from: row), session.startedAt >= since else { continue }
                sessions.append(session)
            }
        }

        sessions.append(contentsOf: loadSQLiteSessions(since: since))

        if sessions.isEmpty {
            sessions.append(contentsOf: fallbackHistorySessions(since: since))
            sessions.append(contentsOf: fallbackIndexSessions(since: since))
        }

        let deduped = Dictionary(grouping: sessions, by: { "\($0.startedAt.timeIntervalSince1970)-\($0.projectHint ?? "")-\($0.model)" })
            .compactMap { $0.value.first }

        return deduped.sorted { $0.startedAt < $1.startedAt }
    }

    private func sessionFileURLs() -> [URL] {
        let manager = FileManager.default
        var urls: [URL] = []

        for directory in sessionsDirectories where manager.fileExists(atPath: directory.path) {
            if let enumerator = manager.enumerator(at: directory, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) {
                for case let url as URL in enumerator where url.pathExtension == "jsonl" {
                    urls.append(url)
                }
            }
        }

        return urls
    }

    private func rawSession(from row: [String: Any]) -> RawSession? {
        if let tokenCountSession = nestedTokenCountSession(from: row) {
            return tokenCountSession
        }

        guard let timestamp = TimeHelpers.parseISODate(stringValue(row["timestamp"]) ?? stringValue(row["created_at"])) else {
            return nil
        }

        let model = stringValue(row["model"]) ?? "codex"
        let input = intValue(row["input_tokens"]) + intValue(row["prompt_tokens"])
        let output = intValue(row["output_tokens"]) + intValue(row["completion_tokens"])
        let family = ModelFamily.resolve(from: model)

        return RawSession(
            providerIdentifier: Self.identifier,
            profile: activeProfile?.name ?? "Default",
            startedAt: timestamp,
            endedAt: timestamp,
            model: model,
            inputTokens: input,
            outputTokens: output,
            requestCount: 1,
            costUSD: family.pricing.totalCost(input: input, output: output, cacheRead: 0, cacheWrite: 0),
            projectHint: nil
        )
    }

    private func nestedTokenCountSession(from row: [String: Any]) -> RawSession? {
        guard let payload = row["payload"] as? [String: Any],
              stringValue(payload["type"]) == "token_count",
              let info = payload["info"] as? [String: Any],
              let usage = (info["last_token_usage"] as? [String: Any]) ?? (info["total_token_usage"] as? [String: Any]),
              let timestamp = TimeHelpers.parseISODate(stringValue(row["timestamp"]) ?? stringValue(payload["timestamp"])) else {
            return nil
        }

        let model = stringValue(payload["model"]) ?? "codex"
        let inputTokens = intValue(usage["input_tokens"])
        let cacheReadTokens = intValue(usage["cached_input_tokens"])
        let outputTokens = intValue(usage["output_tokens"]) + intValue(usage["reasoning_output_tokens"])
        let family = ModelFamily.resolve(from: model)

        return RawSession(
            providerIdentifier: Self.identifier,
            profile: activeProfile?.name ?? "Default",
            startedAt: timestamp,
            endedAt: timestamp,
            model: model,
            inputTokens: inputTokens,
            outputTokens: outputTokens,
            cacheReadTokens: cacheReadTokens,
            requestCount: 1,
            costUSD: family.pricing.totalCost(input: inputTokens, output: outputTokens, cacheRead: cacheReadTokens, cacheWrite: 0),
            projectHint: stringValue(payload["turn_id"])
        )
    }

    private var sqliteLogPaths: [URL] {
        codexRoots.map { $0.appending(path: "logs_2.sqlite") }
    }

    private func loadSQLiteSessions(since: Date) -> [RawSession] {
        let sinceUnix = Int(since.timeIntervalSince1970)
        let sql = """
        SELECT ts, feedback_log_body
        FROM logs
        WHERE target = 'codex_app_server::message_processor'
          AND feedback_log_body LIKE 'app-server request:%'
          AND ts >= \(sinceUnix)
        ORDER BY ts ASC, ts_nanos ASC, id ASC
        """

        return sqliteLogPaths.flatMap { path -> [RawSession] in
            guard FileManager.default.fileExists(atPath: path.path),
                  let rows = try? sqlite.query(databaseURL: path, sql: sql) else {
                return []
            }

            return rows.compactMap { row in
                guard let tsString = row["ts"],
                      let seconds = Double(tsString) else {
                    return nil
                }

                let body = row["feedback_log_body"] ?? ""
                let timestamp = Date(timeIntervalSince1970: seconds)
                let requestName = extractSQLiteRequestName(from: body)
                let requestID = extractSQLiteRequestID(from: body)

                return RawSession(
                    providerIdentifier: Self.identifier,
                    profile: activeProfile?.name ?? "Default",
                    startedAt: timestamp,
                    endedAt: timestamp,
                    model: "codex",
                    inputTokens: 0,
                    outputTokens: 0,
                    requestCount: 1,
                    costUSD: 0,
                    projectHint: [requestName, requestID].compactMap { $0 }.joined(separator: ":")
                )
            }
        }
    }

    private func extractSQLiteRequestName(from body: String) -> String? {
        if let range = body.range(of: "app-server request: ") {
            let suffix = body[range.upperBound...]
            return suffix.split(separator: " ").first.map(String.init)
        }
        return nil
    }

    private func extractSQLiteRequestID(from body: String) -> String? {
        guard let range = body.range(of: "request_id=") else { return nil }
        let suffix = body[range.upperBound...]

        if let quotedStart = suffix.firstIndex(of: "\"") {
            let afterStart = suffix.index(after: quotedStart)
            if let quotedEnd = suffix[afterStart...].firstIndex(of: "\"") {
                return String(suffix[afterStart..<quotedEnd])
            }
        }

        return suffix.split(separator: " ").first.map(String.init)
    }

    private func buildLocalHistoryResult(sessions: [RawSession], source: DataSource, warnings: [ProviderWarning]) -> ProviderResult {
        let hasTokenUsage = sessions.contains { $0.totalTokens > 0 || $0.costUSD > 0 }
        if hasTokenUsage {
            return calculator.buildHeuristicResult(
                identifier: Self.identifier,
                displayName: Self.displayName,
                category: Self.category,
                profile: activeProfile?.name ?? "Default",
                sessions: sessions,
                source: source,
                warnings: warnings
            )
        }

        let requestHeatmap = calculator.heatmap(
            fromDailyValues: sessions.map { (date: $0.startedAt, value: Double(max(1, $0.requestCount))) }
        )

        return ProviderResult(
            identifier: Self.identifier,
            displayName: Self.displayName,
            category: Self.category,
            profile: activeProfile?.name ?? "Default",
            windows: requestHeuristicWindows(from: sessions),
            today: calculator.todayUsage(from: sessions),
            burnRate: nil,
            dailyHeatmap: requestHeatmap,
            models: calculator.modelBreakdown(from: sessions),
            source: source,
            freshness: Date(),
            warnings: warnings
        )
    }

    private func requestHeuristicWindows(from sessions: [RawSession]) -> [Window] {
        [
            requestWindow(kind: .fiveHour, duration: SessionWindowPreset.lastFiveHours.duration, sessions: sessions),
            requestWindow(kind: .weekly, duration: SessionWindowPreset.lastSevenDays.duration, sessions: sessions),
            requestWindow(kind: .monthly, duration: SessionWindowPreset.lastThirtyDays.duration, sessions: sessions)
        ].compactMap { $0 }
    }

    private func requestWindow(kind: WindowKind, duration: TimeInterval, sessions: [RawSession]) -> Window? {
        guard !sessions.isEmpty else { return nil }

        let now = Date()
        let since = now.addingTimeInterval(-duration)
        let currentRequests = sessions
            .filter { $0.startedAt >= since }
            .reduce(0) { $0 + max(1, $1.requestCount) }
        let sampleValues = requestRollingSamples(for: sessions, duration: duration)
        let inferredLimit = percentile90(sampleValues) ?? max(Double(currentRequests) * 1.25, 1)
        let percentage = inferredLimit > 0 ? min(100, (Double(currentRequests) / inferredLimit) * 100) : 0
        let resetAt = sessions.map(\.startedAt).max()?.addingTimeInterval(duration) ?? now.addingTimeInterval(duration)

        return Window(
            kind: kind,
            used: Double(currentRequests),
            limit: inferredLimit,
            unit: .requests,
            percentage: percentage,
            resetAt: resetAt
        )
    }

    private func requestRollingSamples(for sessions: [RawSession], duration: TimeInterval) -> [Double] {
        let sorted = sessions.sorted { $0.startedAt < $1.startedAt }
        guard !sorted.isEmpty else { return [] }

        return sorted.map { anchor in
            let rangeStart = anchor.startedAt.addingTimeInterval(-duration)
            let requestCount = sorted
                .filter { $0.startedAt >= rangeStart && $0.startedAt <= anchor.startedAt }
                .reduce(0) { $0 + max(1, $1.requestCount) }
            return Double(requestCount)
        }
    }

    private func percentile90(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let index = Int(Double(sorted.count - 1) * 0.9)
        return max(sorted[index], 1)
    }

    private func fallbackHistorySessions(since: Date) -> [RawSession] {
        codexRoots.flatMap { root -> [RawSession] in
            let historyURL = root.appending(path: "history.jsonl")
            guard let contents = try? String(contentsOf: historyURL, encoding: .utf8) else { return [] }

            return contents.split(separator: "\n").compactMap { line in
                guard let row = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any] else { return nil }
                guard let date = dateFromUnixOrISO(row["ts"]), date >= since else { return nil }
                return RawSession(
                    providerIdentifier: Self.identifier,
                    profile: activeProfile?.name ?? "Default",
                    startedAt: date,
                    endedAt: date,
                    model: stringValue(row["model"]) ?? "codex",
                    inputTokens: intValue(row["input_tokens"]) + intValue(row["prompt_tokens"]),
                    outputTokens: intValue(row["output_tokens"]) + intValue(row["completion_tokens"]),
                    requestCount: 1,
                    costUSD: 0,
                    projectHint: stringValue(row["session_id"])
                )
            }
        }
    }

    private func fallbackIndexSessions(since: Date) -> [RawSession] {
        codexRoots.flatMap { root -> [RawSession] in
            let indexURL = root.appending(path: "session_index.jsonl")
            guard let contents = try? String(contentsOf: indexURL, encoding: .utf8) else { return [] }

            return contents.split(separator: "\n").compactMap { line in
                guard let row = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any] else { return nil }
                guard let date = TimeHelpers.parseISODate(stringValue(row["updated_at"]) ?? stringValue(row["timestamp"])), date >= since else { return nil }
                return RawSession(
                    providerIdentifier: Self.identifier,
                    profile: activeProfile?.name ?? "Default",
                    startedAt: date,
                    endedAt: date,
                    model: "codex",
                    inputTokens: 0,
                    outputTokens: 0,
                    requestCount: 1,
                    costUSD: 0,
                    projectHint: stringValue(row["thread_name"]) ?? stringValue(row["id"])
                )
            }
        }
    }

    private func dateFromUnixOrISO(_ value: Any?) -> Date? {
        if let int = value as? Int {
            return Date(timeIntervalSince1970: TimeInterval(int))
        }
        if let double = value as? Double {
            return Date(timeIntervalSince1970: double)
        }
        if let string = value as? String, let double = Double(string) {
            return Date(timeIntervalSince1970: double)
        }
        if let string = value as? String {
            return TimeHelpers.parseISODate(string)
        }
        return nil
    }

    private func loadAuthState() -> CodexAuthState? {
        for path in authPaths where FileManager.default.fileExists(atPath: path.path) {
            guard let data = try? Data(contentsOf: path),
                  let auth = parseAuthJSON(data: data),
                  hasTokenLikeAuth(auth) else {
                continue
            }
            return CodexAuthState(auth: auth, authPath: path, source: .file)
        }

        if let raw = keychainService.readAny(service: keychainServiceName),
           let data = raw.data(using: .utf8) ?? decodeHexData(raw),
           let auth = parseAuthJSON(data: data),
           hasTokenLikeAuth(auth) {
            return CodexAuthState(auth: auth, authPath: nil, source: .keychain)
        }

        return nil
    }

    private func parseAuthJSON(data: Data) -> [String: Any]? {
        try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    private func decodeHexData(_ raw: String) -> Data? {
        var hex = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if hex.hasPrefix("0x") || hex.hasPrefix("0X") {
            hex.removeFirst(2)
        }
        guard hex.count.isMultiple(of: 2) else { return nil }
        var bytes = Data(capacity: hex.count / 2)
        var index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 2)
            guard let byte = UInt8(hex[index..<next], radix: 16) else { return nil }
            bytes.append(byte)
            index = next
        }
        return bytes
    }

    private func hasTokenLikeAuth(_ auth: [String: Any]) -> Bool {
        if let tokens = auth["tokens"] as? [String: Any], stringValue(tokens["access_token"]) != nil {
            return true
        }
        return stringValue(auth["OPENAI_API_KEY"]) != nil
    }

    private func accessToken(from auth: [String: Any]) -> String? {
        stringValue((auth["tokens"] as? [String: Any])?["access_token"])
    }

    private func accountID(from auth: [String: Any]) -> String? {
        stringValue((auth["tokens"] as? [String: Any])?["account_id"])
    }

    private func needsRefresh(_ auth: [String: Any]) -> Bool {
        guard let lastRefresh = stringValue(auth["last_refresh"]), let lastDate = TimeHelpers.parseISODate(lastRefresh) else {
            return true
        }
        return Date().timeIntervalSince(lastDate) > refreshAge
    }

    private func refreshToken(_ authState: inout CodexAuthState) async throws -> [String: Any]? {
        var auth = authState.auth
        guard var tokens = auth["tokens"] as? [String: Any],
              let refreshToken = stringValue(tokens["refresh_token"]) else {
            return nil
        }

        var request = URLRequest(url: refreshURL)
        request.httpMethod = "POST"
        request.timeoutInterval = 15
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = "grant_type=refresh_token&client_id=\(urlEncode(clientID))&refresh_token=\(urlEncode(refreshToken))".data(using: .utf8)

        let (data, response) = try await session.data(for: request)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 500
        if statusCode == 400 || statusCode == 401 {
            throw NSError(domain: "CodexProvider", code: statusCode, userInfo: [NSLocalizedDescriptionKey: "Token expired. Run codex to log in again."])
        }

        guard (200...299).contains(statusCode),
              let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let accessToken = stringValue(payload["access_token"]) else {
            return nil
        }

        tokens["access_token"] = accessToken
        if let refresh = stringValue(payload["refresh_token"]) { tokens["refresh_token"] = refresh }
        if let idToken = stringValue(payload["id_token"]) { tokens["id_token"] = idToken }
        auth["tokens"] = tokens
        auth["last_refresh"] = TimeHelpers.iso8601Plain.string(from: Date())
        authState.auth = auth
        saveAuthState(authState)
        return auth
    }

    private func saveAuthState(_ authState: CodexAuthState) {
        guard JSONSerialization.isValidJSONObject(authState.auth),
              let data = try? JSONSerialization.data(withJSONObject: authState.auth, options: authState.source == .file ? [.prettyPrinted, .sortedKeys] : []) else {
            return
        }

        switch authState.source {
        case .file:
            if let path = authState.authPath { try? data.write(to: path) }
        case .keychain:
            if let text = String(data: data, encoding: .utf8) {
                try? keychainService.save(text, service: keychainServiceName, account: "auth")
            }
        }
    }

    private func fetchUsage(accessTokenValue: String, accountIDValue: String?, authState: inout CodexAuthState) async throws -> CodexUsageResponse {
        var response = try await rawFetchUsage(accessToken: accessTokenValue, accountID: accountIDValue)
        if (response.statusCode == 401 || response.statusCode == 403),
           let refreshedAuth = try await refreshToken(&authState),
           let refreshedToken = accessToken(from: refreshedAuth) {
            response = try await rawFetchUsage(accessToken: refreshedToken, accountID: accountID(from: refreshedAuth))
        }
        if response.statusCode == 401 || response.statusCode == 403 {
            throw NSError(domain: "CodexProvider", code: response.statusCode, userInfo: [NSLocalizedDescriptionKey: "Token expired. Run codex to log in again."])
        }
        return response
    }

    private func rawFetchUsage(accessToken: String, accountID: String?) async throws -> CodexUsageResponse {
        var request = URLRequest(url: usageURL)
        request.httpMethod = "GET"
        request.timeoutInterval = 10
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("OpenUsage", forHTTPHeaderField: "User-Agent")
        if let accountID {
            request.setValue(accountID, forHTTPHeaderField: "ChatGPT-Account-Id")
        }

        let (data, response) = try await session.data(for: request)
        let http = response as? HTTPURLResponse
        let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        let headers = http?.allHeaderFields.reduce(into: [String: String]()) { result, entry in
            result[String(describing: entry.key).lowercased()] = String(describing: entry.value)
        } ?? [:]
        return CodexUsageResponse(statusCode: http?.statusCode ?? 500, payload: payload, headers: headers)
    }

    private func buildQuotaResult(from response: CodexUsageResponse, sessions: [RawSession]) -> ProviderResult? {
        guard (200...299).contains(response.statusCode), let payload = response.payload else { return nil }
        let nowSeconds = Int(Date().timeIntervalSince1970)
        var windows: [Window] = []

        if let primary = percentValue(response.headers["x-codex-primary-used-percent"]) ?? percentValue((payload["rate_limit"] as? [String: Any])?["primary_window"] as? [String: Any], key: "used_percent") {
            let resetAt = resetDate(nowSeconds: nowSeconds, window: (payload["rate_limit"] as? [String: Any])?["primary_window"] as? [String: Any])
            windows.append(Window(kind: .fiveHour, used: primary, limit: 100, unit: .requests, percentage: primary, resetAt: resetAt))
        }

        if let weekly = percentValue(response.headers["x-codex-secondary-used-percent"]) ?? percentValue((payload["rate_limit"] as? [String: Any])?["secondary_window"] as? [String: Any], key: "used_percent") {
            let resetAt = resetDate(nowSeconds: nowSeconds, window: (payload["rate_limit"] as? [String: Any])?["secondary_window"] as? [String: Any])
            windows.append(Window(kind: .weekly, used: weekly, limit: 100, unit: .requests, percentage: weekly, resetAt: resetAt))
        }

        if let reviewWindow = (payload["code_review_rate_limit"] as? [String: Any])?["primary_window"] as? [String: Any], let review = percentValue(reviewWindow, key: "used_percent") {
            windows.append(Window(kind: .custom("Reviews"), used: review, limit: 100, unit: .requests, percentage: review, resetAt: resetDate(nowSeconds: nowSeconds, window: reviewWindow)))
        }

        if let additional = payload["additional_rate_limits"] as? [[String: Any]] {
            for item in additional {
                guard let rateLimit = item["rate_limit"] as? [String: Any] else { continue }
                let name = (stringValue(item["limit_name"]) ?? "Model").replacingOccurrences(of: #"^GPT-[\d.]+-Codex-"#, with: "", options: .regularExpression)
                if let primary = percentValue(rateLimit["primary_window"] as? [String: Any], key: "used_percent") {
                    windows.append(Window(kind: .custom(name), used: primary, limit: 100, unit: .requests, percentage: primary, resetAt: resetDate(nowSeconds: nowSeconds, window: rateLimit["primary_window"] as? [String: Any])))
                }
            }
        }

        if let creditsRemaining = numberValue(response.headers["x-codex-credits-balance"]) ?? numberValue((payload["credits"] as? [String: Any])?["balance"]) {
            let limit = 1000.0
            let used = max(0, min(limit, limit - creditsRemaining))
            windows.append(Window(kind: .custom("Credits"), used: used, limit: limit, unit: .requests, percentage: min(100, (used / limit) * 100), resetAt: nil))
        }

        let today = calculator.todayUsage(from: sessions)
        let models = calculator.modelBreakdown(from: sessions)
        let heatmap = calculator.heatmap(from: sessions)

        return ProviderResult(
            identifier: Self.identifier,
            displayName: Self.displayName,
            category: Self.category,
            profile: stringValue(payload["plan_type"])?.capitalized ?? activeProfile?.name ?? "Default",
            windows: windows,
            today: today,
            burnRate: calculator.burnRate(from: sessions, activeWindow: windows.first),
            dailyHeatmap: heatmap,
            models: models,
            source: .mixed,
            freshness: Date(),
            warnings: windows.isEmpty ? [ProviderWarning(level: .info, message: "Codex returned no quota data.")] : []
        )
    }

    private func percentValue(_ value: String?) -> Double? {
        guard let value else { return nil }
        return Double(value)
    }

    private func percentValue(_ window: [String: Any]?, key: String) -> Double? {
        numberValue(window?[key])
    }

    private func numberValue(_ value: Any?) -> Double? {
        if let double = value as? Double, double.isFinite { return double }
        if let int = value as? Int { return Double(int) }
        if let string = value as? String, let double = Double(string), double.isFinite { return double }
        return nil
    }

    private func resetDate(nowSeconds: Int, window: [String: Any]?) -> Date? {
        if let absolute = numberValue(window?["reset_at"]) {
            return Date(timeIntervalSince1970: absolute)
        }
        if let after = numberValue(window?["reset_after_seconds"]) {
            return Date(timeIntervalSince1970: Double(nowSeconds) + after)
        }
        return nil
    }

    private func urlEncode(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? value
    }
}

private struct CodexAuthState {
    var auth: [String: Any]
    let authPath: URL?
    let source: CodexAuthSource
}

private enum CodexAuthSource {
    case file
    case keychain
}

private struct CodexUsageResponse {
    let statusCode: Int
    let payload: [String: Any]?
    let headers: [String: String]
}