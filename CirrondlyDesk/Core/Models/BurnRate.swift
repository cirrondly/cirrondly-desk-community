import Foundation

struct BurnRate: Identifiable, Codable, Hashable {
    let id: UUID
    let tokensPerMinute: Double
    let costPerHour: Double
    let projectedTotalTokens: Int?
    let projectedTotalCost: Double?
    let remainingMinutes: Int?

    init(
        id: UUID = UUID(),
        tokensPerMinute: Double,
        costPerHour: Double,
        projectedTotalTokens: Int? = nil,
        projectedTotalCost: Double? = nil,
        remainingMinutes: Int? = nil
    ) {
        self.id = id
        self.tokensPerMinute = tokensPerMinute
        self.costPerHour = costPerHour
        self.projectedTotalTokens = projectedTotalTokens
        self.projectedTotalCost = projectedTotalCost
        self.remainingMinutes = remainingMinutes
    }

    var isSafeToStartHeavyTask: Bool {
        guard let remainingMinutes else { return false }
        return remainingMinutes > 30
    }
}