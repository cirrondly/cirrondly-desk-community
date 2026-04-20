import SwiftUI

struct ForecastCaption: View {
    let forecast: Forecast

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Text("Forecast")
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
            return "~\(Int(forecast.projectedPercentageAtReset.rounded()))% used by reset"
        case .willExceed:
            if let timeToDepletion = forecast.timeToDepletion {
                return "Runs out in \(formatInterval(timeToDepletion)) at this pace"
            }
            return "~\(Int(forecast.projectedPercentageAtReset.rounded()))% used by reset"
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
        let totalSeconds = max(0, Int(seconds.rounded()))
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60

        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(max(1, minutes))m"
    }
}