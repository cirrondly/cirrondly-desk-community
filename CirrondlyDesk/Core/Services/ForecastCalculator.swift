import Foundation

enum ForecastCalculator {
    static func forecastUsage(
        used: Double,
        limit: Double?,
        windowStart: Date?,
        windowEnd: Date?,
        now: Date = Date()
    ) -> Forecast? {
        guard used >= 0,
              let limit,
              limit > 0,
              let windowStart,
              let windowEnd,
              windowEnd > now else {
            return nil
        }

        let totalWindowSeconds = windowEnd.timeIntervalSince(windowStart)
        let elapsedSeconds = now.timeIntervalSince(windowStart)
        guard totalWindowSeconds > 0, elapsedSeconds >= 60 else {
            return nil
        }

        let pace = used / elapsedSeconds
        let projectedAtReset = pace * totalWindowSeconds
        let projectedPercentage = (projectedAtReset / limit) * 100

        let status: ForecastStatus
        if projectedPercentage <= 80 {
            status = .onTrack
        } else if projectedPercentage <= 100 {
            status = .tight
        } else {
            status = .willExceed
        }

        let remainingWindowSeconds = windowEnd.timeIntervalSince(now)
        var timeToDepletion: TimeInterval?
        if pace > 0 {
            let remaining = max(0, limit - used)
            let secondsToDepletion = remaining / pace
            if secondsToDepletion < remainingWindowSeconds {
                timeToDepletion = secondsToDepletion
            }
        }

        return Forecast(
            projectedUsageAtReset: projectedAtReset,
            projectedPercentageAtReset: projectedPercentage,
            status: status,
            timeToDepletion: timeToDepletion
        )
    }

    static func inferredWindowStart(kind: WindowKind, resetAt: Date?, calendar: Calendar = Calendar(identifier: .gregorian)) -> Date? {
        guard let resetAt else { return nil }

        switch kind {
        case .fiveHour:
            return resetAt.addingTimeInterval(-5 * 60 * 60)
        case .weekly:
            return resetAt.addingTimeInterval(-7 * 24 * 60 * 60)
        case .monthly:
            return calendar.date(byAdding: .month, value: -1, to: resetAt)
        case .custom:
            return nil
        }
    }
}