import SwiftUI

extension Color {
    static let cirrondlyGreenAccent = Color(hex: "13ECB6")
    static let cirrondlyBlueLightest = Color(hex: "EAF2FF")
    static let cirrondlyBlueLight = Color(hex: "B8CEF4")
    static let cirrondlyBlueMid = Color(hex: "6EA4FF")
    static let cirrondlyBlueDark = Color(hex: "1C53B0")
    static let cirrondlyBlack = Color(hex: "282828")
    static let cirrondlyWhiteCard = Color(hex: "F8FBFF")
    static let cirrondlyWhiteInput = Color(hex: "E2E8F0")
    static let cirrondlyWarningOrange = Color(hex: "F59E0B")
    static let cirrondlyCriticalRed = Color(hex: "DC2626")

    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let red = Double((int >> 16) & 0xFF) / 255
        let green = Double((int >> 8) & 0xFF) / 255
        let blue = Double(int & 0xFF) / 255
        self.init(.sRGB, red: red, green: green, blue: blue, opacity: 1)
    }
}