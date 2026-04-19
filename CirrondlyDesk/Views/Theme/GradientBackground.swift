import SwiftUI

struct GradientBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [.cirrondlyBlueLightest, Color.white], startPoint: .topLeading, endPoint: .bottomTrailing)
            blurCircle(size: CGSize(width: 520, height: 360), opacity: 0.55)
                .position(x: 195, y: 220)
            blurCircle(size: CGSize(width: 160, height: 160), opacity: 0.4)
                .position(x: 40, y: 60)
            blurCircle(size: CGSize(width: 170, height: 170), opacity: 0.35)
                .position(x: 340, y: 100)
            blurCircle(size: CGSize(width: 150, height: 150), opacity: 0.32)
                .position(x: 30, y: 500)
            blurCircle(size: CGSize(width: 160, height: 160), opacity: 0.32)
                .position(x: 355, y: 520)
        }
        .ignoresSafeArea()
    }

    private func blurCircle(size: CGSize, opacity: Double) -> some View {
        Circle()
            .fill(Color.cirrondlyBlueLight.opacity(opacity))
            .frame(width: size.width, height: size.height)
            .blur(radius: 50)
            .blendMode(.multiply)
    }
}