import Foundation

enum TimeHelpers {
    static let iso8601Fractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    static let iso8601Plain: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    static let resetFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    static func parseISODate(_ value: String?) -> Date? {
        guard let value, !value.isEmpty else { return nil }
        return iso8601Fractional.date(from: value) ?? iso8601Plain.date(from: value)
    }

    static func relativeResetString(until date: Date?) -> String? {
        guard let date else { return nil }
        let remaining = Int(date.timeIntervalSinceNow)
        guard remaining > 0 else { return nil }
        return compactDurationString(seconds: TimeInterval(remaining), approximate: false)
    }

    static func absoluteResetString(at date: Date?) -> String? {
        guard let date else { return nil }
        return resetFormatter.string(from: date)
    }

    static func resetTimestampString(at date: Date?) -> String? {
        guard let date else { return nil }
        return date.formatted(.dateTime.month(.abbreviated).day().year().hour().minute())
    }

    static func nextMonthBoundary(from date: Date = Date(), calendar: Calendar = Calendar(identifier: .gregorian)) -> Date? {
        let currentMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: date))
        return currentMonth.flatMap { calendar.date(byAdding: .month, value: 1, to: $0) }
    }

    static func startOfDay(for date: Date) -> Date {
        Calendar.current.startOfDay(for: date)
    }

    static func compactDurationString(seconds: TimeInterval, approximate: Bool) -> String {
        let totalSeconds = max(0, Int(seconds.rounded()))
        let days = totalSeconds / 86_400
        let hours = (totalSeconds % 86_400) / 3_600
        let minutes = (totalSeconds % 3_600) / 60

        if days > 0 {
            return L10n.tr(approximate ? "time.compact.approx.daysHours" : "time.compact.daysHours", "\(days)", "\(hours)")
        }
        if hours > 0 {
            return L10n.tr(approximate ? "time.compact.approx.hoursMinutes" : "time.compact.hoursMinutes", "\(hours)", "\(minutes)")
        }
        if minutes > 0 {
            return L10n.tr(approximate ? "time.compact.approx.minutes" : "time.compact.minutes", "\(minutes)")
        }
        return L10n.tr(approximate ? "time.compact.approx.underMinute" : "time.compact.underMinute")
    }
}