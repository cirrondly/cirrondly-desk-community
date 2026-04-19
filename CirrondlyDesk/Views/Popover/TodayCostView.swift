import SwiftUI

struct TodayCostView: View {
    let snapshot: UsageSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Today")
                .font(Typography.body(12, weight: .semibold))
                .foregroundStyle(Color.cirrondlyBlueDark.opacity(0.75))

            Text("$\(snapshot.summary.totalCostTodayUSD, format: .number.precision(.fractionLength(2)))")
                .font(Typography.mono(30, weight: .bold))
                .foregroundStyle(Color.cirrondlyBlueDark)

            Text("\(snapshot.summary.totalTokensToday.formatted()) tokens • \(snapshot.summary.totalRequestsToday.formatted()) requests")
                .font(Typography.mono(12))
                .foregroundStyle(Color.cirrondlyBlueDark.opacity(0.75))
        }
    }
}