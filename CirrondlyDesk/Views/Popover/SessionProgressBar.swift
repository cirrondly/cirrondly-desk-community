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
                Text(L10n.tr("progress.resets", resetTimestamp))
                    .font(.caption)
                    .foregroundStyle(Color.cirrondlyBlack.opacity(0.56))
            }

            if let forecast = window.forecast {
                ForecastCaption(forecast: forecast)
            }

            HStack(spacing: 8) {
                metricLabel(title: L10n.tr("progress.metric.usage"), value: usageSummary)

                if let remainingSummary {
                    metricLabel(title: L10n.tr("progress.metric.remaining"), value: remainingSummary)
                }

                if let timeLeftSummary {
                    metricLabel(title: L10n.tr("progress.metric.timeLeft"), value: timeLeftSummary)
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
                return L10n.tr("progress.usage.percentUsed", "\(Int(window.used.rounded()))")
            }
            return L10n.tr("progress.usage.ofTotal", formatted(window.used), formatted(limit), unitLabel)
        }

        return L10n.tr("progress.usage.usedUnit", formatted(window.used), unitLabel)
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
        window.unit.localizedLabel
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