import SwiftUI

enum Typography {
    static func body(_ size: CGFloat = 13, weight: Font.Weight = .regular) -> Font {
        .custom(isEmphasized(weight) ? "Inter-SemiBold" : "Inter-Regular", size: size, relativeTo: .body)
    }

    static func display(_ size: CGFloat = 28) -> Font {
        .custom("IslandMoments-Regular", size: size, relativeTo: .title)
    }

    static func mono(_ size: CGFloat = 14, weight: Font.Weight = .medium) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }

    private static func isEmphasized(_ weight: Font.Weight) -> Bool {
        switch weight {
        case .semibold, .bold, .heavy, .black:
            return true
        default:
            return false
        }
    }
}