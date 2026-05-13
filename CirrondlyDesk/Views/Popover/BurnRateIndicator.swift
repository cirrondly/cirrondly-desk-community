import SwiftUI

struct BurnRateIndicator: View {
    let burnRate: BurnRate?

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "flame.fill")
                .foregroundStyle(Color.cirrondlyWarningOrange)

            if let burnRate {
                Text(L10n.tr("popover.burnRate.ratePerHour", burnRate.costPerHour.formatted(.currency(code: "USD").precision(.fractionLength(0...2)))))
                    .font(Typography.mono(12))
                Text(burnRate.isSafeToStartHeavyTask ? L10n.tr("popover.burnRate.safeHeavy") : L10n.tr("popover.burnRate.stayLight"))
                    .font(Typography.body(12, weight: .semibold))
                    .foregroundStyle(burnRate.isSafeToStartHeavyTask ? Color.cirrondlyGreenAccent : Color.cirrondlyWarningOrange)
            } else {
                Text(L10n.tr("popover.burnRate.unavailable"))
                    .font(Typography.body(12))
                    .foregroundStyle(Color.cirrondlyBlueDark.opacity(0.7))
            }

            Spacer()
        }
    }
}