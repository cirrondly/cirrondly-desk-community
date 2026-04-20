import SwiftUI

struct SessionProgressBar: View {
    let title: String
    let window: Window

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center) {
                Text(title)
                    .font(Typography.body(12, weight: .semibold))
                    .foregroundStyle(Color.cirrondlyBlueDark)
                Spacer()
                if window.percentage > 0 {
                    Text("\(Int(window.percentage.rounded()))%")
                        .font(Typography.mono(11))
                        .foregroundStyle(Color.cirrondlyBlueDark.opacity(0.8))
                }
                if let resetAt = window.resetAt {
                    TimeToResetBadge(resetAt: resetAt)
                }
            }

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.cirrondlyBlueLight.opacity(0.25))
                    Capsule()
                        .fill(barColor)
                        .frame(width: max(8, proxy.size.width * CGFloat(window.percentage / 100)))
                }
            }
            .frame(height: 8)

            if let resetTimestamp {
                Text("Resets \(resetTimestamp)")
                    .font(.caption)
                    .foregroundStyle(Color.cirrondlyBlack.opacity(0.56))
            }

            if let forecast = window.forecast {
                ForecastCaption(forecast: forecast)
            }

            HStack(spacing: 8) {
                metricLabel(title: "Usage", value: usageSummary)

                if let remainingSummary {
                    metricLabel(title: "Remaining", value: remainingSummary)
                }

                if let timeLeftSummary {
                    metricLabel(title: "Time left", value: timeLeftSummary)
                }
            }
        }
    }

    private var barColor: Color {
        switch window.percentage {
        case 90...:
            return .cirrondlyCriticalRed
        case 70...:
            return .cirrondlyWarningOrange
        default:
            return .cirrondlyGreenAccent
        }
    }

    private var usageSummary: String {
        if let limit = window.limit, limit > 0 {
            if abs(limit - 100) < 0.001, abs(window.used - window.percentage) < 0.001 {
                return "\(Int(window.used.rounded()))% used"
            }
            return "\(formatted(window.used)) of \(formatted(limit)) \(unitLabel)"
        }

        return "\(formatted(window.used)) \(unitLabel) used"
    }

    private var remainingSummary: String? {
        guard let limit = window.limit else { return nil }
        let remaining = max(0, limit - window.used)
        guard remaining > 0 else { return nil }
        return "\(formatted(remaining)) \(unitLabel)"
    }

    private var timeLeftSummary: String? {
        TimeHelpers.relativeResetString(until: window.resetAt)
    }

    private var resetTimestamp: String? {
        TimeHelpers.resetTimestampString(at: window.resetAt)
    }

    private var unitLabel: String {
        switch window.unit {
        case .tokens:
            return "tokens"
        case .requests:
            return "requests"
        case .credits:
            return "credits"
        case .dollars:
            return "USD"
        }
    }

    private func formatted(_ value: Double) -> String {
        switch window.unit {
        case .dollars:
            return value.formatted(.currency(code: "USD").precision(.fractionLength(0...2)))
        case .tokens, .requests, .credits:
            if value.rounded() == value {
                return Int(value).formatted()
            }
            return value.formatted(.number.precision(.fractionLength(0...1)))
        }
    }

    private func metricLabel(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(Typography.body(9, weight: .semibold))
                .foregroundStyle(Color.cirrondlyBlueDark.opacity(0.56))

            Text(value)
                .font(Typography.body(10, weight: .semibold))
                .foregroundStyle(Color.cirrondlyBlueDark.opacity(0.82))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Color.white.opacity(0.6), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.cirrondlyBlueLight.opacity(0.45), lineWidth: 1)
        )
    }
}