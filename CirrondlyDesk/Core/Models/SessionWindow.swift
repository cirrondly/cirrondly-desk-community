import Foundation

enum SessionWindowPreset: CaseIterable, Hashable {
    case lastFiveHours
    case lastSevenDays
    case lastThirtyDays
    case lastThirtyMinutes

    var duration: TimeInterval {
        switch self {
        case .lastFiveHours:
            return 5 * 60 * 60
        case .lastSevenDays:
            return 7 * 24 * 60 * 60
        case .lastThirtyDays:
            return 30 * 24 * 60 * 60
        case .lastThirtyMinutes:
            return 30 * 60
        }
    }
}

struct RawSession: Identifiable, Codable, Hashable {
    let id: UUID
    let providerIdentifier: String
    let profile: String
    let startedAt: Date
    let endedAt: Date
    let model: String
    let inputTokens: Int
    let outputTokens: Int
    let cacheReadTokens: Int
    let cacheWriteTokens: Int
    let requestCount: Int
    let costUSD: Double
    let projectHint: String?

    init(
        id: UUID = UUID(),
        providerIdentifier: String,
        profile: String,
        startedAt: Date,
        endedAt: Date,
        model: String,
        inputTokens: Int,
        outputTokens: Int,
        cacheReadTokens: Int = 0,
        cacheWriteTokens: Int = 0,
        requestCount: Int = 1,
        costUSD: Double,
        projectHint: String?
    ) {
        self.id = id
        self.providerIdentifier = providerIdentifier
        self.profile = profile
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.model = model
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.cacheReadTokens = cacheReadTokens
        self.cacheWriteTokens = cacheWriteTokens
        self.requestCount = requestCount
        self.costUSD = costUSD
        self.projectHint = projectHint
    }

    var totalTokens: Int {
        inputTokens + outputTokens + cacheReadTokens + cacheWriteTokens
    }
}