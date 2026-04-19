import Foundation

final class KiroProvider: UsageProvider {
    static let identifier = "kiro"
    static let displayName = "Kiro"
    static let category: ProviderCategory = .usageBased

    private let defaults = UserDefaults.standard
    private let sqlite = SQLiteReader()
    private let session = URLSession(configuration: .ephemeral)
    private let calculator = BurnRateCalculator()

    private let stateKey = "kiro.kiroAgent"
    private let refreshURL = URL(string: "https://prod.us-east-1.auth.desktop.kiro.dev/refreshToken")!
    private let liveStaleInterval: TimeInterval = 15 * 60
    private let refreshBuffer: TimeInterval = 10 * 60
    private let defaultRegion = "us-east-1"
    private let stateHint = "Kiro usage data unavailable. Open the Kiro account dashboard once and try again."
    private let loginHint = "Open Kiro and sign in, then try again."

    var isEnabled: Bool {
        get { defaults.object(forKey: "provider.kiro.enabled") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "provider.kiro.enabled") }
    }

    var profiles: [ProviderProfile] { [ProviderProfile(name: "Default")] }
    var activeProfile: ProviderProfile? = ProviderProfile(name: "Default")

    func isAvailable() async -> Bool {
        let paths = [stateDatabaseURL, logsRootURL, authTokenURL, profileURL]
        return paths.contains { FileManager.default.fileExists(atPath: $0.path) }
    }

    func probe() async throws -> ProviderResult {
        let now = Date()
        let localState = loadCachedState()
        let loggedState = loadLoggedState()
        let authState = loadAuthState()

        var liveState: KiroSnapshot?
        var warnings: [ProviderWarning] = []

        if shouldTryLive(localState: localState, loggedState: loggedState, now: now), var authState {
            do {
                liveState = try await fetchLiveState(authState: &authState, now: now)
            } catch let error as KiroLiveError {
                warnings.append(ProviderWarning(level: .info, message: error.message))
            } catch {
                warnings.append(ProviderWarning(level: .info, message: "Kiro live refresh failed. Using the latest local cache instead."))
            }
        }

        guard let snapshot = mergeSnapshots(localState: localState, loggedState: loggedState, liveState: liveState, now: now) else {
            let fallbackMessage = authState == nil ? loginHint : (warnings.last?.message ?? stateHint)
            return ProviderResult(
                identifier: Self.identifier,
                displayName: Self.displayName,
                category: Self.category,
                profile: formattedPlan(nil) ?? "Kiro Free",
                windows: [],
                today: .zero,
                burnRate: nil,
                dailyHeatmap: [],
                models: [],
                source: .local,
                freshness: now,
                warnings: [ProviderWarning(level: .info, message: fallbackMessage)]
            )
        }

        if liveState == nil {
            warnings.append(ProviderWarning(level: .info, message: "Using Kiro local cache/logs. Open Kiro to refresh if the values look stale."))
        }

        let activityHeatmap = loadActivityHeatmap()

        return ProviderResult(
            identifier: Self.identifier,
            displayName: Self.displayName,
            category: Self.category,
            profile: formattedPlan(snapshot.plan) ?? "Kiro Free",
            windows: makeWindows(from: snapshot),
            today: .zero,
            burnRate: nil,
            dailyHeatmap: activityHeatmap,
            models: [],
            source: snapshot.source,
            freshness: snapshot.timestamp ?? now,
            warnings: dedupeWarnings(warnings)
        )
    }

    private var stateDatabaseURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library/Application Support/Kiro/User/globalStorage/state.vscdb")
    }

    private var logsRootURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library/Application Support/Kiro/logs", directoryHint: .isDirectory)
    }

    private var taskStorageRootURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library/Application Support/Kiro/User/globalStorage/kiro.kiroagent", directoryHint: .isDirectory)
    }

    private var authTokenURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appending(path: ".aws/sso/cache/kiro-auth-token.json")
    }

    private var profileURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library/Application Support/Kiro/User/globalStorage/kiro.kiroagent/profile.json")
    }

    private func loadCachedState() -> KiroSnapshot? {
        guard FileManager.default.fileExists(atPath: stateDatabaseURL.path) else { return nil }
        let sql = "SELECT value FROM ItemTable WHERE key = '\(stateKey.replacingOccurrences(of: "'", with: "''"))' LIMIT 1;"
        guard let row = try? sqlite.query(databaseURL: stateDatabaseURL, sql: sql).first,
              let rawValue = row["value"],
              let payload = jsonObject(from: rawValue),
              let usageState = usageStateObject(in: payload),
              let rawBreakdowns = usageState["usageBreakdowns"] as? [Any] else {
            return nil
        }

        let breakdowns = rawBreakdowns.compactMap { normalizeBreakdown($0) }
        guard !breakdowns.isEmpty else { return nil }

        return KiroSnapshot(
            usageBreakdowns: breakdowns,
            timestamp: dateFromMilliseconds(usageState["timestamp"]),
            plan: nil,
            overageEnabled: nil,
            source: .local
        )
    }

    private func usageStateObject(in payload: [String: Any]) -> [String: Any]? {
        if let direct = payload["kiro.resourceNotifications.usageState"] as? [String: Any] {
            return direct
        }

        return payload.first(where: { key, value in
            key.hasSuffix(".usageState") && value is [String: Any]
        })?.value as? [String: Any]
    }

    private func loadLoggedState() -> KiroSnapshot? {
        guard let sessions = try? FileManager.default.contentsOfDirectory(at: logsRootURL, includingPropertiesForKeys: nil) else {
            return nil
        }

        for sessionDirectory in sessions.sorted(by: { $0.lastPathComponent > $1.lastPathComponent }).prefix(12) {
            guard let windows = try? FileManager.default.contentsOfDirectory(at: sessionDirectory, includingPropertiesForKeys: nil) else {
                continue
            }

            for windowDirectory in windows.sorted(by: { $0.lastPathComponent > $1.lastPathComponent }) {
                let logURL = windowDirectory
                    .appending(path: "exthost", directoryHint: .isDirectory)
                    .appending(path: "kiro.kiroAgent", directoryHint: .isDirectory)
                    .appending(path: "q-client.log")
                guard FileManager.default.fileExists(atPath: logURL.path),
                      let text = try? String(contentsOf: logURL, encoding: .utf8),
                      let snapshot = parseUsageLogText(text) else {
                    continue
                }
                return snapshot
            }
        }

        return nil
    }

    private func parseUsageLogText(_ text: String) -> KiroSnapshot? {
        let lines = text.split(whereSeparator: \ .isNewline)
        for line in lines.reversed() {
            let string = String(line)
            guard string.contains("\"commandName\":\"GetUsageLimitsCommand\""),
                  let jsonStart = string.firstIndex(of: "{"),
                  let payload = jsonObject(from: String(string[jsonStart...])),
                  let output = payload["output"] as? [String: Any] else {
                continue
            }

            let prefix = String(string[..<jsonStart]).trimmingCharacters(in: .whitespaces)
            let timestampString = prefix.components(separatedBy: " [").first
            let timestamp = timestampString.flatMap(parseLogTimestamp)
            return normalizeAPISnapshot(output, timestamp: timestamp, source: .local)
        }
        return nil
    }

    private func loadAuthState() -> KiroAuthState? {
        guard let payload = jsonObject(fromFile: authTokenURL) else { return nil }
        let sanitized = sanitizeAuth(payload)
        guard stringValue(sanitized["refreshToken"]) != nil || stringValue(sanitized["accessToken"]) != nil else {
            return nil
        }
        return KiroAuthState(path: authTokenURL, token: sanitized)
    }

    private func saveAuthState(_ authState: KiroAuthState) {
        guard JSONSerialization.isValidJSONObject(authState.token),
              let data = try? JSONSerialization.data(withJSONObject: authState.token, options: [.prettyPrinted, .sortedKeys]),
              let string = String(data: data, encoding: .utf8) else {
            return
        }
        try? string.write(to: authState.path, atomically: true, encoding: .utf8)
    }

    private func sanitizeAuth(_ token: [String: Any]) -> [String: Any] {
        var token = token
        switch stringValue(token["provider"]) {
        case "Google", "Github":
            token["authMethod"] = "social"
        case "ExternalIdp":
            token["authMethod"] = "external_idp"
        case "Enterprise", "BuilderId", "Internal":
            token["authMethod"] = "IdC"
        default:
            break
        }
        return token
    }

    private func shouldTryLive(localState: KiroSnapshot?, loggedState: KiroSnapshot?, now: Date) -> Bool {
        if localState == nil || loggedState == nil || loggedState?.plan == nil { return true }
        guard let timestamp = localState?.timestamp else { return true }
        return now.timeIntervalSince(timestamp) > liveStaleInterval
    }

    private func fetchLiveState(authState: inout KiroAuthState, now: Date) async throws -> KiroSnapshot? {
        guard let profileArn = loadProfileArn(authState: authState) else { return nil }
        var accessToken = stringValue(authState.token["accessToken"])

        if accessToken == nil || needsRefresh(authState: authState, now: now) {
            accessToken = try await refreshAccessToken(authState: &authState, now: now)
        }

        guard let accessToken else {
            throw KiroLiveError.sessionExpired
        }

        let url = usageURL(profileArn: profileArn)
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        buildUsageHeaders(authState: authState, accessToken: accessToken).forEach { key, value in
            request.setValue(value, forHTTPHeaderField: key)
        }

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            return nil
        }

        if http.statusCode == 401 || http.statusCode == 403 {
            guard let refreshed = try await refreshAccessToken(authState: &authState, now: now) else {
                throw KiroLiveError.sessionExpired
            }
            var retry = URLRequest(url: url)
            retry.httpMethod = "GET"
            buildUsageHeaders(authState: authState, accessToken: refreshed).forEach { key, value in
                retry.setValue(value, forHTTPHeaderField: key)
            }
            let (retryData, retryResponse) = try await session.data(for: retry)
            guard let retryHTTP = retryResponse as? HTTPURLResponse else { return nil }
            if retryHTTP.statusCode == 401 || retryHTTP.statusCode == 403 {
                throw KiroLiveError.sessionExpired
            }
            guard (200...299).contains(retryHTTP.statusCode),
                  let payload = try? JSONSerialization.jsonObject(with: retryData) as? [String: Any] else {
                return nil
            }
            return normalizeAPISnapshot(payload, timestamp: now, source: .api)
        }

        guard (200...299).contains(http.statusCode),
              let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        return normalizeAPISnapshot(payload, timestamp: now, source: .api)
    }

    private func usageURL(profileArn: String) -> URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "q.\(region(from: profileArn)).amazonaws.com"
        components.path = "/getUsageLimits"
        components.queryItems = [
            URLQueryItem(name: "origin", value: "AI_EDITOR"),
            URLQueryItem(name: "profileArn", value: profileArn),
            URLQueryItem(name: "resourceType", value: "AGENTIC_REQUEST")
        ]
        return components.url!
    }

    private func loadProfileArn(authState: KiroAuthState) -> String? {
        if let arn = stringValue(authState.token["profileArn"]) {
            return arn
        }
        if let profile = jsonObject(fromFile: profileURL), let arn = stringValue(profile["arn"]) {
            return arn
        }
        return nil
    }

    private func region(from profileArn: String) -> String {
        let parts = profileArn.split(separator: ":")
        return parts.count > 3 && !parts[3].isEmpty ? String(parts[3]) : defaultRegion
    }

    private func needsRefresh(authState: KiroAuthState, now: Date) -> Bool {
        guard let expiresAt = TimeHelpers.parseISODate(stringValue(authState.token["expiresAt"])) else {
            return true
        }
        return now.addingTimeInterval(refreshBuffer) >= expiresAt
    }

    private func refreshAccessToken(authState: inout KiroAuthState, now: Date) async throws -> String? {
        guard let refreshToken = stringValue(authState.token["refreshToken"]) else {
            throw KiroLiveError.sessionExpired
        }

        var request = URLRequest(url: refreshURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(userAgent(), forHTTPHeaderField: "User-Agent")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["refreshToken": refreshToken])

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { return nil }
        if http.statusCode == 401 || http.statusCode == 403 {
            throw KiroLiveError.sessionExpired
        }
        guard (200...299).contains(http.statusCode),
              let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let accessToken = stringValue(payload["accessToken"]) else {
            return nil
        }

        authState.token["accessToken"] = accessToken
        if let newRefresh = stringValue(payload["refreshToken"]) {
            authState.token["refreshToken"] = newRefresh
        }
        if let profileArn = stringValue(payload["profileArn"]) {
            authState.token["profileArn"] = profileArn
        }

        if let expiresIn = numberValue(payload["expiresIn"]) ?? numberValue(payload["expires_in"]), expiresIn > 0 {
            authState.token["expiresAt"] = TimeHelpers.iso8601Plain.string(from: now.addingTimeInterval(expiresIn))
        }

        authState.token = sanitizeAuth(authState.token)
        saveAuthState(authState)
        return accessToken
    }

    private func buildUsageHeaders(authState: KiroAuthState, accessToken: String) -> [String: String] {
        var headers = [
            "Authorization": "Bearer \(accessToken)",
            "Accept": "application/json",
            "User-Agent": userAgent()
        ]
        if stringValue(authState.token["authMethod"]) == "external_idp" {
            headers["TokenType"] = "EXTERNAL_IDP"
        }
        if stringValue(authState.token["provider"]) == "Internal" {
            headers["redirect-for-internal"] = "true"
        }
        return headers
    }

    private func userAgent() -> String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0"
        return "CirrondlyDesk/\(version)"
    }

    private func mergeSnapshots(localState: KiroSnapshot?, loggedState: KiroSnapshot?, liveState: KiroSnapshot?, now: Date) -> KiroSnapshot? {
        let usageSource: KiroSnapshot?
        if let liveState, !liveState.usageBreakdowns.isEmpty {
            usageSource = liveState
        } else if let localState, !localState.usageBreakdowns.isEmpty {
            usageSource = localState
        } else if let loggedState, !loggedState.usageBreakdowns.isEmpty {
            usageSource = loggedState
        } else {
            usageSource = nil
        }

        guard let usageSource else { return nil }

        let hasMultipleSources = [liveState, localState, loggedState].compactMap { snapshot in
            snapshot?.usageBreakdowns.isEmpty == false ? snapshot : nil
        }.count > 1

        return KiroSnapshot(
            usageBreakdowns: usageSource.usageBreakdowns,
            timestamp: usageSource.timestamp ?? now,
            plan: liveState?.plan ?? loggedState?.plan,
            overageEnabled: liveState?.overageEnabled ?? loggedState?.overageEnabled,
            source: hasMultipleSources ? .mixed : usageSource.source
        )
    }

    private func makeWindows(from snapshot: KiroSnapshot) -> [Window] {
        guard let primary = pickPrimaryBreakdown(snapshot.usageBreakdowns) else {
            return []
        }

        var windows: [Window] = [
            Window(
                kind: .custom(creditWindowTitle(for: primary)),
                used: primary.currentUsage,
                limit: primary.usageLimit,
                unit: .credits,
                percentage: percentage(used: primary.currentUsage, limit: primary.usageLimit),
                resetAt: primary.resetDate
            )
        ]

        if let freeTrial = primary.freeTrialUsage {
            windows.append(
                Window(
                    kind: .custom(freeTrial.displayName ?? "Bonus Credits"),
                    used: freeTrial.currentUsage,
                    limit: freeTrial.usageLimit,
                    unit: .credits,
                    percentage: percentage(used: freeTrial.currentUsage, limit: freeTrial.usageLimit),
                    resetAt: freeTrial.expiryDate
                )
            )
        }

        windows.append(contentsOf: primary.bonuses.map { bonus in
            Window(
                kind: .custom(bonus.displayName ?? "Bonus Credits"),
                used: bonus.currentUsage,
                limit: bonus.usageLimit,
                unit: .credits,
                percentage: percentage(used: bonus.currentUsage, limit: bonus.usageLimit),
                resetAt: bonus.expiryDate
            )
        })

        return windows
    }

    private func pickPrimaryBreakdown(_ breakdowns: [KiroBreakdown]) -> KiroBreakdown? {
        breakdowns.first { $0.type == "CREDIT" } ?? breakdowns.first
    }

    private func normalizeAPISnapshot(_ payload: [String: Any], timestamp: Date?, source: DataSource) -> KiroSnapshot? {
        let usageBreakdowns = (payload["usageBreakdownList"] as? [Any])?.compactMap { normalizeBreakdown($0) } ?? []
        guard !usageBreakdowns.isEmpty else { return nil }

        return KiroSnapshot(
            usageBreakdowns: usageBreakdowns,
            timestamp: timestamp,
            plan: formattedPlan(titleCase(stringValue((payload["subscriptionInfo"] as? [String: Any])?["subscriptionTitle"]))),
            overageEnabled: stringValue((payload["overageConfiguration"] as? [String: Any])?["overageStatus"]) == "ENABLED",
            source: source
        )
    }

    private func creditWindowTitle(for breakdown: KiroBreakdown) -> String {
        if breakdown.type.uppercased() == "CREDIT" {
            return "Credits"
        }

        let normalized = breakdown.type
            .replacingOccurrences(of: "_", with: " ")
            .lowercased()
        return titleCase(normalized) ?? "Credits"
    }

    private func formattedPlan(_ rawPlan: String?) -> String? {
        guard let rawPlan = rawPlan?.trimmingCharacters(in: .whitespacesAndNewlines), !rawPlan.isEmpty else {
            return nil
        }

        if rawPlan.lowercased().hasPrefix("kiro") {
            return rawPlan
        }
        return "Kiro \(rawPlan)"
    }

    private func normalizeBreakdown(_ raw: Any) -> KiroBreakdown? {
        guard let raw = raw as? [String: Any],
              let currentUsage = firstNumber(raw["currentUsageWithPrecision"], raw["currentUsage"]),
              let usageLimit = firstNumber(raw["usageLimitWithPrecision"], raw["usageLimit"]),
              usageLimit > 0 else {
            return nil
        }

        let bonuses = (raw["bonuses"] as? [Any])?.compactMap {
            normalizePool(
                $0,
                currentKey: "currentUsage",
                preciseCurrentKey: nil,
                limitKey: "usageLimit",
                preciseLimitKey: nil,
                expiryKeys: ["expiresAt", "expiryDate"],
                statusKey: "status",
                allowedStatuses: ["ACTIVE", "EXHAUSTED"]
            )
        } ?? []

        return KiroBreakdown(
            type: stringValue(raw["resourceType"]) ?? stringValue(raw["type"]) ?? "CREDIT",
            currentUsage: currentUsage,
            usageLimit: usageLimit,
            resetDate: firstDate(raw["nextDateReset"], raw["resetDate"]),
            freeTrialUsage: normalizePool(
                raw["freeTrialInfo"] ?? raw["freeTrialUsage"],
                currentKey: "currentUsage",
                preciseCurrentKey: "currentUsageWithPrecision",
                limitKey: "usageLimit",
                preciseLimitKey: "usageLimitWithPrecision",
                expiryKeys: ["freeTrialExpiry", "expiryDate"],
                statusKey: "freeTrialStatus",
                allowedStatuses: ["ACTIVE"]
            ),
            bonuses: bonuses
        )
    }

    private func normalizePool(
        _ raw: Any?,
        currentKey: String,
        preciseCurrentKey: String?,
        limitKey: String,
        preciseLimitKey: String?,
        expiryKeys: [String],
        statusKey: String?,
        allowedStatuses: Set<String>
    ) -> KiroPool? {
        guard let raw = raw as? [String: Any] else { return nil }
        if let statusKey, let status = stringValue(raw[statusKey]), !allowedStatuses.contains(status) {
            return nil
        }

        let currentUsage = firstNumber(preciseCurrentKey.flatMap { raw[$0] }, raw[currentKey])
        let usageLimit = firstNumber(preciseLimitKey.flatMap { raw[$0] }, raw[limitKey])
        guard let currentUsage, let usageLimit, usageLimit > 0 else { return nil }

        return KiroPool(
            currentUsage: currentUsage,
            usageLimit: usageLimit,
            expiryDate: expiryKeys.compactMap { key in firstDate(raw[key]) }.first,
            displayName: stringValue(raw["displayName"])
        )
    }

    private func titleCase(_ value: String?) -> String? {
        guard let value = value?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }
        return value
            .lowercased()
            .split(whereSeparator: \ .isWhitespace)
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined(separator: " ")
    }

    private func jsonObject(fromFile url: URL) -> [String: Any]? {
        guard let data = try? Data(contentsOf: url),
              let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return payload
    }

    private func jsonObject(from text: String) -> [String: Any]? {
        guard let data = text.data(using: .utf8),
              let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return payload
    }

    private func percentage(used: Double, limit: Double) -> Double {
        guard limit > 0 else { return 0 }
        return min(100, (used / limit) * 100)
    }

    private func numberValue(_ value: Any?) -> Double? {
        if let double = value as? Double, double.isFinite { return double }
        if let int = value as? Int { return Double(int) }
        if let string = value as? String, let double = Double(string), double.isFinite { return double }
        return nil
    }

    private func firstNumber(_ values: Any?...) -> Double? {
        values.compactMap(numberValue).first
    }

    private func firstDate(_ values: Any?...) -> Date? {
        for value in values {
            if let date = value as? Date {
                return date
            }
            if let date = TimeHelpers.parseISODate(stringValue(value)) {
                return date
            }
            if let milliseconds = numberValue(value), milliseconds > 1_000_000 {
                return Date(timeIntervalSince1970: milliseconds / 1000)
            }
        }
        return nil
    }

    private func dateFromMilliseconds(_ value: Any?) -> Date? {
        guard let milliseconds = numberValue(value) else { return nil }
        return Date(timeIntervalSince1970: milliseconds / 1000)
    }

    private func parseLogTimestamp(_ value: String) -> Date? {
        KiroDateFormatter.log.date(from: value)
    }

    private func dedupeWarnings(_ warnings: [ProviderWarning]) -> [ProviderWarning] {
        var seen = Set<String>()
        return warnings.filter { warning in
            seen.insert("\(warning.level.rawValue):\(warning.message)").inserted
        }
    }

    private func loadActivityHeatmap(days: Int = 90) -> [DailyCell] {
        let taskActivity = loadTaskActivity(days: days)
        if !taskActivity.isEmpty {
            return calculator.heatmap(fromDailyValues: taskActivity, days: days)
        }

        let snapshots = historicalSnapshots()
        guard !snapshots.isEmpty else { return [] }

        var maxUsageByDay: [(date: Date, value: Double)] = []
        let grouped = Dictionary(grouping: snapshots) { snapshot in
            TimeHelpers.dayFormatter.string(from: TimeHelpers.startOfDay(for: snapshot.date))
        }

        for rows in grouped.values {
            guard let best = rows.max(by: { $0.totalUsage < $1.totalUsage }) else { continue }
            maxUsageByDay.append((date: TimeHelpers.startOfDay(for: best.date), value: best.totalUsage))
        }

        let sorted = maxUsageByDay.sorted { $0.date < $1.date }
        var previousValue = 0.0
        var dailyDeltas: [(date: Date, value: Double)] = []

        for entry in sorted {
            let delta = entry.value >= previousValue ? (entry.value - previousValue) : entry.value
            previousValue = entry.value
            if delta > 0 {
                dailyDeltas.append((date: entry.date, value: delta))
            }
        }

        return calculator.heatmap(fromDailyValues: dailyDeltas, days: days)
    }

    private func loadTaskActivity(days: Int) -> [(date: Date, value: Double)] {
        guard FileManager.default.fileExists(atPath: taskStorageRootURL.path),
              let enumerator = FileManager.default.enumerator(
                at: taskStorageRootURL,
                includingPropertiesForKeys: [.contentModificationDateKey, .creationDateKey],
                options: [.skipsHiddenFiles]
              ) else {
            return []
        }

        let cutoff = Calendar.current.date(byAdding: .day, value: -(days - 1), to: TimeHelpers.startOfDay(for: Date())) ?? .distantPast
        var values: [(date: Date, value: Double)] = []

        for case let url as URL in enumerator {
            guard url.pathExtension == "json",
                  url.lastPathComponent != "config.json",
                  let payload = jsonObject(fromFile: url) else {
                continue
            }

            let timestamps = extractTaskActivityTimestamps(from: payload, fileURL: url)
            guard !timestamps.isEmpty else { continue }

            for timestamp in timestamps where timestamp >= cutoff {
                values.append((date: TimeHelpers.startOfDay(for: timestamp), value: 1))
            }
        }

        return values
    }

    private func extractTaskActivityTimestamps(from payload: [String: Any], fileURL: URL) -> [Date] {
        let looksLikeTaskRecord = payload["taskId"] != nil
            || payload["executionHistory"] != nil
            || payload["createdAt"] != nil
            || payload["updatedAt"] != nil
        guard looksLikeTaskRecord else { return [] }

        var timestamps = Set<Date>()

        if let executionHistory = payload["executionHistory"] as? [Any] {
            for entry in executionHistory {
                guard let record = entry as? [String: Any],
                      let timestamp = dateFromMilliseconds(record["timestamp"]) else {
                    continue
                }
                timestamps.insert(timestamp)
            }
        }

        if let createdAt = dateFromMilliseconds(payload["createdAt"]) {
            timestamps.insert(createdAt)
        }
        if let updatedAt = dateFromMilliseconds(payload["updatedAt"]) {
            timestamps.insert(updatedAt)
        }

        if timestamps.isEmpty,
           let values = try? fileURL.resourceValues(forKeys: [.contentModificationDateKey, .creationDateKey]),
           let fileDate = values.contentModificationDate ?? values.creationDate {
            timestamps.insert(fileDate)
        }

        return timestamps.sorted()
    }

    private func historicalSnapshots() -> [(date: Date, totalUsage: Double)] {
        guard let enumerator = FileManager.default.enumerator(at: logsRootURL, includingPropertiesForKeys: nil) else {
            return []
        }

        var snapshots: [(date: Date, totalUsage: Double)] = []

        for case let url as URL in enumerator {
            guard url.lastPathComponent == "q-client.log",
                  let text = try? String(contentsOf: url, encoding: .utf8) else {
                continue
            }

            for line in text.split(whereSeparator: \.isNewline) {
                let string = String(line)
                guard string.contains("\"commandName\":\"GetUsageLimitsCommand\""),
                      let jsonStart = string.firstIndex(of: "{"),
                      let payload = jsonObject(from: String(string[jsonStart...])),
                      let output = payload["output"] as? [String: Any] else {
                    continue
                }

                let prefix = String(string[..<jsonStart]).trimmingCharacters(in: .whitespaces)
                let timestampString = prefix.components(separatedBy: " [").first
                guard let timestamp = timestampString.flatMap(parseLogTimestamp),
                      let snapshot = normalizeAPISnapshot(output, timestamp: timestamp, source: .local) else {
                    continue
                }

                let totalUsage = snapshot.usageBreakdowns.reduce(0.0) { partial, breakdown in
                    partial
                        + breakdown.currentUsage
                        + (breakdown.freeTrialUsage?.currentUsage ?? 0)
                        + breakdown.bonuses.reduce(0.0) { $0 + $1.currentUsage }
                }
                snapshots.append((date: timestamp, totalUsage: totalUsage))
            }
        }

        return snapshots
    }
}

private struct KiroAuthState {
    let path: URL
    var token: [String: Any]
}

private struct KiroPool {
    let currentUsage: Double
    let usageLimit: Double
    let expiryDate: Date?
    let displayName: String?
}

private struct KiroBreakdown {
    let type: String
    let currentUsage: Double
    let usageLimit: Double
    let resetDate: Date?
    let freeTrialUsage: KiroPool?
    let bonuses: [KiroPool]
}

private struct KiroSnapshot {
    let usageBreakdowns: [KiroBreakdown]
    let timestamp: Date?
    let plan: String?
    let overageEnabled: Bool?
    let source: DataSource
}

private enum KiroLiveError: Error {
    case sessionExpired

    var message: String {
        switch self {
        case .sessionExpired:
            return "Kiro session expired. Open Kiro and sign in again."
        }
    }
}

private enum KiroDateFormatter {
    static let log: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return formatter
    }()
}