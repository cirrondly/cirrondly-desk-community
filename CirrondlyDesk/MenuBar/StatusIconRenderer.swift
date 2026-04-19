import AppKit
import SwiftUI

enum MenuBarMode: String, CaseIterable, Identifiable {
    case minimal
    case percentage
    case burnRate
    case providerPercentage

    var id: String { rawValue }

    var title: String {
        switch self {
        case .minimal:
            return "Minimal"
        case .percentage:
            return "Percentage"
        case .burnRate:
            return "Burn rate"
        case .providerPercentage:
            return "Provider + %"
        }
    }
}

enum StatusIconRenderer {
    static func image(for snapshot: UsageSnapshot?) -> NSImage {
        let configuration = NSImage.SymbolConfiguration(pointSize: 15, weight: .semibold)
        let mode = MenuBarMode(rawValue: UserDefaults.standard.string(forKey: "general.menuBarMode") ?? MenuBarMode.minimal.rawValue) ?? .minimal
        let baseImage = baseImage(for: snapshot, mode: mode, configuration: configuration)
        let canvas = NSImage(size: NSSize(width: 25, height: 25))
        canvas.lockFocus()

        let iconRect = fittedRect(for: baseImage.size, in: NSRect(x: 1.25, y: 2.5, width: 20.75, height: 17.5))
        baseImage.draw(in: iconRect)

        if !isStale(snapshot), snapshot != nil {
            statusColor(for: snapshot).setFill()
            NSBezierPath(ovalIn: NSRect(x: 14.25, y: 1.1, width: 4.6, height: 4.6)).fill()
        }

        if isStale(snapshot) {
            let badge = NSImage(systemSymbolName: "exclamationmark.triangle.fill", accessibilityDescription: nil)?.withSymbolConfiguration(.init(pointSize: 7, weight: .bold))
            NSColor.systemGray.setFill()
            badge?.draw(in: NSRect(x: 11.5, y: 0, width: 8.5, height: 8.5))
        }

        canvas.unlockFocus()
        canvas.isTemplate = false
        return canvas
    }

    static func title(for snapshot: UsageSnapshot?) -> String {
        let mode = MenuBarMode(rawValue: UserDefaults.standard.string(forKey: "general.menuBarMode") ?? MenuBarMode.minimal.rawValue) ?? .minimal
        guard let snapshot else { return "" }

        let percentage = Int(snapshot.summary.worstPercentage.rounded())
        switch mode {
        case .minimal:
            return ""
        case .percentage:
            return percentage > 0 ? "\(percentage)%" : ""
        case .burnRate:
            if let burnRate = snapshot.providers.compactMap(\.burnRate).max(by: { ($0.remainingMinutes ?? 0) < ($1.remainingMinutes ?? 0) }), let remaining = burnRate.remainingMinutes, remaining > 0 {
                if remaining >= 60 {
                    return "~\(remaining / 60)h"
                }
                return "~\(remaining)m"
            }
            return percentage > 0 ? "\(percentage)%" : ""
        case .providerPercentage:
            return percentage > 0 ? "\(percentage)%" : ""
        }
    }

    static func toolTip(for snapshot: UsageSnapshot?) -> String {
        guard let snapshot else { return "Cirrondly Desk" }
        guard let worstProvider = snapshot.summary.worstProvider,
              let provider = snapshot.providers.first(where: { $0.identifier == worstProvider }),
              let window = provider.primaryWindow else {
            return "Cirrondly Desk"
        }

        return "Highest active usage: \(provider.displayName) \(window.kind.title) \(Int(window.percentage.rounded()))%"
    }

    private static func statusColor(for snapshot: UsageSnapshot?) -> NSColor {
        guard let snapshot else { return .systemGray }
        if isStale(snapshot) { return .systemGray }

        switch snapshot.summary.worstPercentage {
        case 90...:
            return NSColor(Color.cirrondlyCriticalRed)
        case 70...:
            return NSColor(Color.cirrondlyWarningOrange)
        default:
            return NSColor(Color.cirrondlyGreenAccent)
        }
    }

    private static func isStale(_ snapshot: UsageSnapshot?) -> Bool {
        guard let snapshot else { return true }
        return Date().timeIntervalSince(snapshot.generatedAt) > 600
    }

    private static func baseImage(for snapshot: UsageSnapshot?, mode: MenuBarMode, configuration: NSImage.SymbolConfiguration) -> NSImage {
        if mode == .providerPercentage,
           let identifier = snapshot?.summary.worstProvider,
           let providerImage = ProviderIconCatalog.image(for: identifier) {
            return providerImage
        }

        return NSImage(named: "MenuBarIcon")
            ?? NSImage(systemSymbolName: "cloud.fill", accessibilityDescription: "Cirrondly Desk")?.withSymbolConfiguration(configuration)
            ?? NSImage(size: NSSize(width: 18, height: 18))
    }

    private static func fittedRect(for sourceSize: NSSize, in bounds: NSRect) -> NSRect {
        guard sourceSize.width > 0, sourceSize.height > 0 else { return bounds }

        let widthScale = bounds.width / sourceSize.width
        let heightScale = bounds.height / sourceSize.height
        let scale = min(widthScale, heightScale)
        let fittedSize = NSSize(width: sourceSize.width * scale, height: sourceSize.height * scale)

        return NSRect(
            x: bounds.midX - (fittedSize.width / 2),
            y: bounds.midY - (fittedSize.height / 2),
            width: fittedSize.width,
            height: fittedSize.height
        )
    }
}