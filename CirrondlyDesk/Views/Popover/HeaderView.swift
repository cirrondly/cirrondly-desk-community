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
                    Text("Hey, \(firstName)")
                        .font(Typography.display(28))
                        .foregroundStyle(Color.cirrondlyBlueDark)

                    Text(lastUpdated.map { "Updated \($0.formatted(date: .omitted, time: .shortened))" } ?? "Waiting for the first refresh")
                        .font(Typography.body(11))
                        .foregroundStyle(Color.cirrondlyBlueDark.opacity(0.7))
                }

                Spacer()
            }
        }
    }

    private var firstName: String {
        NSFullUserName().split(separator: " ").first.map(String.init) ?? "there"
    }
}