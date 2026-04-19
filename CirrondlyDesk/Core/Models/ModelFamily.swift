import Foundation

enum ModelFamily: String, CaseIterable, Hashable {
    case claudeSonnet
    case claudeOpus
    case codex
    case gpt
    case geminiPro
    case geminiFlash
    case cursor
    case unknown

    static func resolve(from model: String) -> ModelFamily {
        let normalized = model.lowercased()
        if normalized.contains("sonnet") { return .claudeSonnet }
        if normalized.contains("opus") { return .claudeOpus }
        if normalized.contains("codex") { return .codex }
        if normalized.contains("gpt") { return .gpt }
        if normalized.contains("gemini") && normalized.contains("flash") { return .geminiFlash }
        if normalized.contains("gemini") { return .geminiPro }
        if normalized.contains("cursor") { return .cursor }
        return .unknown
    }

    var pricing: CostEstimate {
        switch self {
        case .claudeSonnet:
            return CostEstimate(inputPerMillion: 3.0, outputPerMillion: 15.0, cacheReadPerMillion: 0.3, cacheWritePerMillion: 3.75)
        case .claudeOpus:
            return CostEstimate(inputPerMillion: 15.0, outputPerMillion: 75.0, cacheReadPerMillion: 1.5, cacheWritePerMillion: 18.75)
        case .codex:
            return CostEstimate(inputPerMillion: 1.5, outputPerMillion: 6.0, cacheReadPerMillion: 0, cacheWritePerMillion: 0)
        case .gpt:
            return CostEstimate(inputPerMillion: 5.0, outputPerMillion: 15.0, cacheReadPerMillion: 0, cacheWritePerMillion: 0)
        case .geminiPro:
            return CostEstimate(inputPerMillion: 1.25, outputPerMillion: 5.0, cacheReadPerMillion: 0, cacheWritePerMillion: 0)
        case .geminiFlash:
            return CostEstimate(inputPerMillion: 0.35, outputPerMillion: 1.05, cacheReadPerMillion: 0, cacheWritePerMillion: 0)
        case .cursor:
            return CostEstimate(inputPerMillion: 0, outputPerMillion: 0, cacheReadPerMillion: 0, cacheWritePerMillion: 0)
        case .unknown:
            return CostEstimate(inputPerMillion: 0, outputPerMillion: 0, cacheReadPerMillion: 0, cacheWritePerMillion: 0)
        }
    }
}