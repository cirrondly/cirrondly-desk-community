import SwiftUI

struct BurnRateIndicator: View {
    let burnRate: BurnRate?

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "flame.fill")
                .foregroundStyle(Color.cirrondlyWarningOrange)

            if let burnRate {
                Text("$\(burnRate.costPerHour, format: .number.precision(.fractionLength(2)))/hr")
                    .font(Typography.mono(12))
                Text(burnRate.isSafeToStartHeavyTask ? "Safe to start heavy" : "Stay light")
                    .font(Typography.body(12, weight: .semibold))
                    .foregroundStyle(burnRate.isSafeToStartHeavyTask ? Color.cirrondlyGreenAccent : Color.cirrondlyWarningOrange)
            } else {
                Text("Burn rate unavailable")
                    .font(Typography.body(12))
                    .foregroundStyle(Color.cirrondlyBlueDark.opacity(0.7))
            }

            Spacer()
        }
    }
}