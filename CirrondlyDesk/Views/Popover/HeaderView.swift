import SwiftUI

struct HeaderView: View {
    let lastUpdated: Date?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top) {
                Image("CloudLogo")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 28, height: 22)

                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.tr("popover.header.greeting", firstName))
                        .font(Typography.display(28))
                        .foregroundStyle(Color.cirrondlyBlueDark)

                    Text(lastUpdated.map { L10n.tr("popover.header.updated", $0.formatted(date: .omitted, time: .shortened)) } ?? L10n.tr("popover.header.waiting"))
                        .font(Typography.body(11))
                        .foregroundStyle(Color.cirrondlyBlueDark.opacity(0.7))
                }

                Spacer()
            }
        }
    }

    private var firstName: String {
        NSFullUserName().split(separator: " ").first.map(String.init) ?? L10n.tr("popover.header.there")
    }
}