import SwiftUI

struct ForecastCaption: View {
    let forecast: Forecast

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Text(L10n.tr("forecast.badge"))
                .font(Typography.body(10, weight: .semibold))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(color.opacity(0.12), in: Capsule())
                .foregroundStyle(color)

            Text(captionText)
                .font(Typography.body(11, weight: .medium))
                .foregroundStyle(color)

            Spacer(minLength: 0)
        }
    }

    private var captionText: String {
        switch forecast.status {
        case .onTrack, .tight:
            return L10n.tr("forecast.caption.usedByReset", "\(Int(forecast.projectedPercentageAtReset.rounded()))")
        case .willExceed:
            if let timeToDepletion = forecast.timeToDepletion {
                return L10n.tr("forecast.caption.runsOut", formatInterval(timeToDepletion))
            }
            return L10n.tr("forecast.caption.usedByReset", "\(Int(forecast.projectedPercentageAtReset.rounded()))")
        }
    }

    private var color: Color {
        switch forecast.status {
        case .onTrack:
            return Color.cirrondlyBlack.opacity(0.68)
        case .tight:
            return Color.cirrondlyWarningOrange
        case .willExceed:
            return Color.cirrondlyCriticalRed
        }
    }

    private func formatInterval(_ seconds: TimeInterval) -> String {
        TimeHelpers.compactDurationString(seconds: seconds, approximate: false)
    }
}