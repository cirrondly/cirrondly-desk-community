import SwiftUI

struct TimeToResetBadge: View {
    let resetAt: Date

    var body: some View {
        if let text = TimeHelpers.relativeResetString(until: resetAt) {
            Text(text)
                .font(Typography.mono(10))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(backgroundColor, in: Capsule())
                .foregroundStyle(foregroundColor)
        }
    }

    private var backgroundColor: Color {
        let remaining = resetAt.timeIntervalSinceNow
        if remaining <= 3600 {
            return Color.cirrondlyCriticalRed.opacity(0.18)
        }
        if remaining <= 86_400 {
            return Color.cirrondlyWarningOrange.opacity(0.18)
        }
        return Color.cirrondlyBlueLight.opacity(0.35)
    }

    private var foregroundColor: Color {
        let remaining = resetAt.timeIntervalSinceNow
        if remaining <= 3600 {
            return Color.cirrondlyCriticalRed
        }
        if remaining <= 86_400 {
            return Color.cirrondlyWarningOrange
        }
        return Color.cirrondlyBlueDark
    }
}