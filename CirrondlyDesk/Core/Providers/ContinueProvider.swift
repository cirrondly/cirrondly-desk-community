import Foundation

final class ContinueProvider: UsageProvider {
    static let identifier = "continue"
    static let displayName = "Continue"
    static let category: ProviderCategory = .free

    private let calculator = BurnRateCalculator()
    private let defaults = UserDefaults.standard

    var isEnabled: Bool {
        get { defaults.object(forKey: "provider.continue.enabled") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "provider.continue.enabled") }
    }

    var profiles: [ProviderProfile] { [ProviderProfile(name: "Default")] }
    var activeProfile: ProviderProfile? = ProviderProfile(name: "Default")

    func isAvailable() async -> Bool {
        FileManager.default.fileExists(atPath: logsDirectory.path)
    }

    func probe() async throws -> ProviderResult {
        let sessions = try await loadSessions(since: Date().addingTimeInterval(-90 * 86_400))
        return calculator.buildHeuristicResult(
            identifier: Self.identifier,
            displayName: Self.displayName,
            category: Self.category,
            profile: activeProfile?.name ?? "Default",
            sessions: sessions,
            source: .local
        )
    }

    func sessions(since: Date) async throws -> [RawSession] {
        try await loadSessions(since: since)
    }

    private var logsDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser.appending(path: ".continue/logs", directoryHint: .isDirectory)
    }

    private func loadSessions(since: Date) async throws -> [RawSession] {
        let urls = (try? FileManager.default.contentsOfDirectory(at: logsDirectory, includingPropertiesForKeys: nil)) ?? []
        var sessions: [RawSession] = []

        for url in urls where ["json", "jsonl"].contains(url.pathExtension) {
            let data = try Data(contentsOf: url)
            if url.pathExtension == "jsonl" {
                let rows = try await JSONLStreamReader.readObjects(at: url)
                sessions.append(contentsOf: rows.compactMap { makeSession(from: $0, since: since) })
            } else if let object = try? JSONSerialization.jsonObject(with: data) {
                if let array = object as? [[String: Any]] {
                    sessions.append(contentsOf: array.compactMap { makeSession(from: $0, since: since) })
                } else if let dict = object as? [String: Any] {
                    if let session = makeSession(from: dict, since: since) {
                        sessions.append(session)
                    }
                    if let history = dict["history"] as? [[String: Any]] {
                        sessions.append(contentsOf: history.compactMap { makeSession(from: $0, since: since) })
                    }
                }
            }
        }

        return sessions.sorted { $0.startedAt < $1.startedAt }
    }

    private func makeSession(from row: [String: Any], since: Date) -> RawSession? {
        let timestamp = TimeHelpers.parseISODate(stringValue(row["timestamp"]) ?? stringValue(row["createdAt"]) ?? stringValue(row["date"]))
        guard let timestamp, timestamp >= since else { return nil }

        let model = stringValue(row["model"]) ?? stringValue(row["modelTitle"]) ?? "continue"
        let usage = row["usage"] as? [String: Any]
        let input = intValue(usage?["promptTokens"]) + intValue(row["promptTokens"]) + intValue(usage?["inputTokens"])
        let output = intValue(usage?["completionTokens"]) + intValue(row["completionTokens"]) + intValue(usage?["outputTokens"])
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
            projectHint: stringValue(row["workspaceName"])
        )
    }
}