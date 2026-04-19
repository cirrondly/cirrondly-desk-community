import Foundation

final class ClaudeCodeProvider: UsageProvider {
    static let identifier = "claude-code"
    static let displayName = "Claude Code"
    static let category: ProviderCategory = .subscription

    private let calculator = BurnRateCalculator()
    private let defaults = UserDefaults.standard
    private let keychainService: KeychainService
    private let liveUsageProvider: ClaudeSubscriptionProvider
    private let defaultClaudeHome = ".claude"
    private let credentialsFile = ".credentials.json"
    private let keychainServicePrefix = "Claude Code"

    init(keychainService: KeychainService) {
        self.keychainService = keychainService
        self.liveUsageProvider = ClaudeSubscriptionProvider(keychainService: keychainService)
    }

    var isEnabled: Bool {
        get { defaults.object(forKey: "provider.claude-code.enabled") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "provider.claude-code.enabled") }
    }

    var profiles: [ProviderProfile] { [ProviderProfile(name: "Default")] }
    var activeProfile: ProviderProfile? = ProviderProfile(name: "Default")

    func isAvailable() async -> Bool {
        if await liveUsageProvider.isAvailable() {
            return true
        }

        let fileManager = FileManager.default
        let footprintURLs = claudeRoots + projectDirectories + historyURLs + claudeCredentialPaths
        if footprintURLs.contains(where: { fileManager.fileExists(atPath: $0.path) }) {
            return true
        }

        if readEnvText("CLAUDE_CODE_OAUTH_TOKEN") != nil {
            return true
        }

        return candidateKeychainServiceNames().contains { service in
            keychainService.readAny(service: service) != nil
        }
    }

    func probe() async throws -> ProviderResult {
        let since = Date().addingTimeInterval(-90 * 86_400)
        let rows = try await loadSessions(since: since)
        let localResult = rows.isEmpty ? nil : calculator.buildHeuristicResult(
            identifier: Self.identifier,
            displayName: Self.displayName,
            category: Self.category,
            profile: activeProfile?.name ?? "Default",
            sessions: rows,
            source: .local
        )

        var liveFailureWarning: ProviderWarning?
        var liveResult: ProviderResult?
        if await liveUsageProvider.isAvailable() {
            do {
                liveResult = try await liveUsageProvider.probe()
            } catch {
                if localResult == nil {
                    throw error
                }
                liveFailureWarning = ProviderWarning(level: .warning, message: error.localizedDescription)
            }
        }

        if let liveResult, let localResult {
            return ProviderResult(
                identifier: Self.identifier,
                displayName: Self.displayName,
                category: Self.category,
                profile: liveResult.profile,
                windows: liveResult.windows,
                today: localResult.today,
                burnRate: localResult.burnRate,
                dailyHeatmap: localResult.dailyHeatmap,
                models: localResult.models,
                source: .mixed,
                freshness: max(liveResult.freshness, localResult.freshness),
                warnings: liveResult.warnings + (liveFailureWarning.map { [$0] } ?? [])
            )
        }

        if let liveResult {
            return ProviderResult(
                identifier: Self.identifier,
                displayName: Self.displayName,
                category: Self.category,
                profile: liveResult.profile,
                windows: liveResult.windows,
                today: liveResult.today,
                burnRate: liveResult.burnRate,
                dailyHeatmap: liveResult.dailyHeatmap,
                models: liveResult.models,
                source: liveResult.source,
                freshness: liveResult.freshness,
                warnings: liveResult.warnings
            )
        }

        if let localResult {
            return localResult
        }

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
            warnings: [ProviderWarning(level: .info, message: "Claude Code was detected, but neither live usage nor local tokenized logs are available yet.")]
        )
    }

    func sessions(since: Date) async throws -> [RawSession] {
        try await loadSessions(since: since)
    }

    private var claudeRoots: [URL] {
        configuredClaudeRoots()
    }

    private var projectDirectories: [URL] {
        claudeRoots.map { $0.appending(path: "projects", directoryHint: .isDirectory) }
    }

    private var historyURLs: [URL] {
        claudeRoots.map { $0.appending(path: "history.jsonl") }
    }

    private var claudeCredentialPaths: [URL] {
        claudeRoots.map { $0.appending(path: credentialsFile) }
    }

    private func configuredClaudeRoots() -> [URL] {
        let rawRoots: [URL]

        if let override = readEnvText("CLAUDE_CONFIG_DIR") {
            rawRoots = override
                .split(separator: ",")
                .compactMap { part in
                    let trimmed = String(part).trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { return nil }

                    let expandedPath = (trimmed as NSString).expandingTildeInPath
                    let url = URL(fileURLWithPath: expandedPath, isDirectory: true)
                    if url.lastPathComponent == "projects" {
                        return url.deletingLastPathComponent()
                    }
                    return url
                }
        } else {
            let home = FileManager.default.homeDirectoryForCurrentUser
            rawRoots = [
                home.appending(path: ".config/claude", directoryHint: .isDirectory),
                home.appending(path: defaultClaudeHome, directoryHint: .isDirectory)
            ]
        }

        var seenPaths = Set<String>()
        return rawRoots.filter { url in
            seenPaths.insert(url.standardizedFileURL.path).inserted
        }
    }

    private func candidateKeychainServiceNames() -> [String] {
        var suffixes = [""]
        let userType = readEnvText("USER_TYPE")

        if userType == "ant", readEnvFlag("USE_LOCAL_OAUTH") {
            suffixes.append("-local-oauth")
        } else if userType == "ant", readEnvFlag("USE_STAGING_OAUTH") {
            suffixes.append("-staging-oauth")
        }

        if readEnvText("CLAUDE_CODE_CUSTOM_OAUTH_URL") != nil {
            suffixes.append("-custom-oauth")
        }

        return Array(Set(suffixes)).map { keychainServicePrefix + $0 + "-credentials" }
    }

    private func readEnvText(_ name: String) -> String? {
        let value = ProcessInfo.processInfo.environment[name]?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let value, !value.isEmpty else { return nil }
        return value
    }

    private func readEnvFlag(_ name: String) -> Bool {
        guard let value = readEnvText(name)?.lowercased() else { return false }
        return ["1", "true", "yes", "on"].contains(value)
    }

    private func loadSessions(since: Date) async throws -> [RawSession] {
        var seenPaths = Set<String>()
        let fileURLs = projectDirectories.flatMap { directory in
            jsonlFiles(in: directory).filter { url in
                seenPaths.insert(url.standardizedFileURL.path).inserted
            }
        }
        var sessions: [RawSession] = []

        for url in fileURLs {
            let rows = try await JSONLStreamReader.readObjects(at: url)
            for row in rows {
                guard let timestamp = TimeHelpers.parseISODate(stringValue(row["timestamp"])) else { continue }
                guard timestamp >= since else { continue }

                guard let usage = usagePayload(from: row) else { continue }

                let model = modelName(from: row) ?? "Claude"
                let input = intValue(usage["input_tokens"])
                let output = intValue(usage["output_tokens"])
                let cacheRead = intValue(usage["cache_read_input_tokens"])
                let cacheWrite = intValue(usage["cache_creation_input_tokens"])
                let cwd = stringValue(row["cwd"])?.split(separator: "/").last.map(String.init)
                let family = ModelFamily.resolve(from: model)

                sessions.append(
                    RawSession(
                        providerIdentifier: Self.identifier,
                        profile: activeProfile?.name ?? "Default",
                        startedAt: timestamp,
                        endedAt: timestamp,
                        model: model,
                        inputTokens: input,
                        outputTokens: output,
                        cacheReadTokens: cacheRead,
                        cacheWriteTokens: cacheWrite,
                        requestCount: max(1, intValue(row["tool_calls"])),
                        costUSD: family.pricing.totalCost(input: input, output: output, cacheRead: cacheRead, cacheWrite: cacheWrite),
                        projectHint: cwd
                    )
                )
            }
        }

        if sessions.isEmpty {
            sessions.append(contentsOf: fallbackHistorySessions(since: since))
        }

        return sessions.sorted { $0.startedAt < $1.startedAt }
    }

    private func jsonlFiles(in root: URL) -> [URL] {
        guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil) else {
            return []
        }

        return enumerator.compactMap { $0 as? URL }.filter { $0.pathExtension == "jsonl" }
    }

    private func fallbackHistorySessions(since: Date) -> [RawSession] {
        historyURLs.flatMap { historyURL -> [RawSession] in
            guard let data = try? String(contentsOf: historyURL, encoding: .utf8) else { return [] }

            return data
                .split(separator: "\n")
                .compactMap { line in
                    guard let row = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any] else { return nil }
                    guard let timestamp = TimeHelpers.parseISODate(stringValue(row["timestamp"]) ?? stringValue(row["updated_at"])), timestamp >= since else { return nil }
                    return RawSession(
                        providerIdentifier: Self.identifier,
                        profile: activeProfile?.name ?? "Default",
                        startedAt: timestamp,
                        endedAt: timestamp,
                        model: modelName(from: row) ?? "claude",
                        inputTokens: 0,
                        outputTokens: 0,
                        requestCount: 1,
                        costUSD: 0,
                        projectHint: stringValue(row["cwd"])
                    )
                }
        }
    }

    private func usagePayload(from row: [String: Any]) -> [String: Any]? {
        if let message = row["message"] as? [String: Any],
           let usage = message["usage"] as? [String: Any],
           hasUsageFields(in: usage) {
            return usage
        }

        return hasUsageFields(in: row) ? row : nil
    }

    private func hasUsageFields(in payload: [String: Any]) -> Bool {
        payload["input_tokens"] != nil
            || payload["output_tokens"] != nil
            || payload["cache_read_input_tokens"] != nil
            || payload["cache_creation_input_tokens"] != nil
    }

    private func modelName(from row: [String: Any]) -> String? {
        if let message = row["message"] as? [String: Any],
           let model = stringValue(message["model"]) {
            return model
        }

        return stringValue(row["model"])
    }
}

func intValue(_ value: Any?) -> Int {
    if let int = value as? Int { return int }
    if let double = value as? Double { return Int(double) }
    if let string = value as? String { return Int(string) ?? 0 }
    if let array = value as? [Any] { return array.count }
    return 0
}

func stringValue(_ value: Any?) -> String? {
    if let string = value as? String, !string.isEmpty { return string }
    return nil
}