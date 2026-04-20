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
        let days = remaining / 86_400
        let hours = (remaining % 86_400) / 3_600
        let minutes = (remaining % 3_600) / 60

        if days > 0 { return "\(days)d \(hours)h" }
        if hours > 0 { return "\(hours)h \(minutes)m" }
        if minutes > 0 { return "\(minutes)m" }
        return "<1m"
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
}