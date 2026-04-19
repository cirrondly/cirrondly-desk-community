import Foundation

final class AiderProvider: UsageProvider {
    static let identifier = "aider"
    static let displayName = "Aider"
    static let category: ProviderCategory = .api

    private let calculator = BurnRateCalculator()
    private let defaults = UserDefaults.standard

    var isEnabled: Bool {
        get { defaults.object(forKey: "provider.aider.enabled") as? Bool ?? true }
        set { defaults.set(newValue, forKey: "provider.aider.enabled") }
    }

    var profiles: [ProviderProfile] { [ProviderProfile(name: "Default")] }
    var activeProfile: ProviderProfile? = ProviderProfile(name: "Default")

    func isAvailable() async -> Bool {
        FileManager.default.fileExists(atPath: directory.path)
    }

    func probe() async throws -> ProviderResult {
        let sessions = try await loadSessions(since: Date().addingTimeInterval(-90 * 86_400))
        return calculator.buildHeuristicResult(
            identifier: Self.identifier,
            displayName: Self.displayName,
            category: Self.category,
            profile: activeProfile?.name ?? "Default",
            sessions: sessions,
            source: .local,
            warnings: sessions.isEmpty ? [ProviderWarning(level: .info, message: "Aider was detected, but token accounting could not be extracted from the local logs yet.")] : []
        )
    }

    func sessions(since: Date) async throws -> [RawSession] {
        try await loadSessions(since: since)
    }

    private var directory: URL {
        FileManager.default.homeDirectoryForCurrentUser.appending(path: ".aider", directoryHint: .isDirectory)
    }

    private func loadSessions(since: Date) async throws -> [RawSession] {
        guard let enumerator = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles]) else {
            return []
        }

        let urls = enumerator.compactMap { $0 as? URL }

        var sessions: [RawSession] = []
        let tokenRegex = try NSRegularExpression(pattern: "(tokens?|token count)\\s*[:=]\\s*([0-9,]+)", options: [.caseInsensitive])
        let costRegex = try NSRegularExpression(pattern: "(cost|spent)\\s*[:=]\\s*\\$?([0-9]+(?:\\.[0-9]+)?)", options: [.caseInsensitive])

        for url in urls where ["md", "txt", "jsonl"].contains(url.pathExtension) {
            let values = try? url.resourceValues(forKeys: [.contentModificationDateKey])
            guard let modifiedAt = values?.contentModificationDate, modifiedAt >= since else { continue }
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }

            let tokens = firstIntMatch(regex: tokenRegex, in: text) ?? 0
            let cost = firstDoubleMatch(regex: costRegex, in: text) ?? 0
            if tokens == 0 && cost == 0 { continue }

            sessions.append(
                RawSession(
                    providerIdentifier: Self.identifier,
                    profile: activeProfile?.name ?? "Default",
                    startedAt: modifiedAt,
                    endedAt: modifiedAt,
                    model: "aider",
                    inputTokens: tokens,
                    outputTokens: 0,
                    requestCount: 1,
                    costUSD: cost,
                    projectHint: url.deletingLastPathComponent().lastPathComponent
                )
            )
        }

        return sessions.sorted { $0.startedAt < $1.startedAt }
    }

    private func firstIntMatch(regex: NSRegularExpression, in text: String) -> Int? {
        guard let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)), let range = Range(match.range(at: 2), in: text) else {
            return nil
        }
        return Int(text[range].replacingOccurrences(of: ",", with: ""))
    }

    private func firstDoubleMatch(regex: NSRegularExpression, in text: String) -> Double? {
        guard let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)), let range = Range(match.range(at: 2), in: text) else {
            return nil
        }
        return Double(text[range])
    }
}