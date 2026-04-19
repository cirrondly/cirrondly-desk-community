import Foundation

struct CostEstimate: Hashable {
    let inputPerMillion: Double
    let outputPerMillion: Double
    let cacheReadPerMillion: Double
    let cacheWritePerMillion: Double

    func totalCost(input: Int, output: Int, cacheRead: Int, cacheWrite: Int) -> Double {
        let inputCost = (Double(input) / 1_000_000) * inputPerMillion
        let outputCost = (Double(output) / 1_000_000) * outputPerMillion
        let cacheReadCost = (Double(cacheRead) / 1_000_000) * cacheReadPerMillion
        let cacheWriteCost = (Double(cacheWrite) / 1_000_000) * cacheWritePerMillion
        return inputCost + outputCost + cacheReadCost + cacheWriteCost
    }
}