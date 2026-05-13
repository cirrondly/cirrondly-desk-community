import SwiftUI

struct AllSetView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "cloud.fill")
                .font(.system(size: 48))
                .foregroundStyle(Color.cirrondlyGreenAccent)
            Text(L10n.tr("onboarding.allSet.title"))
                .font(Typography.body(20, weight: .semibold))
            Text(L10n.tr("onboarding.allSet.body"))
                .font(Typography.body(14))
                .foregroundStyle(Color.cirrondlyBlack.opacity(0.68))
        }
        .padding(24)
    }
}