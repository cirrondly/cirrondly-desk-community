import SwiftUI

struct WelcomeView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(L10n.tr("onboarding.welcome.title"))
                .font(Typography.display(30))
            Text(L10n.tr("onboarding.welcome.body"))
                .font(Typography.body(14))
        }
        .padding(24)
    }
}