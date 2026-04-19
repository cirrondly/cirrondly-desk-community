import Foundation

enum UsageIntensity: Int, Codable, CaseIterable, Hashable {
    case zero
    case low
    case medium
    case high
    case peak
}

struct DailyCell: Identifiable, Codable, Hashable {
    var id: String { dayKey }

    let date: Date
    let value: Double
    let intensity: UsageIntensity

    var dayKey: String {
        TimeHelpers.dayFormatter.string(from: date)
    }

    static func intensity(for value: Double, max: Double) -> UsageIntensity {
        guard value > 0, max > 0 else { return .zero }
        let ratio = value / max
        switch ratio {
        case 0..<0.25:
            return .low
        case 0.25..<0.5:
            return .medium
        case 0.5..<0.8:
            return .high
        default:
            return .peak
        }
    }
}