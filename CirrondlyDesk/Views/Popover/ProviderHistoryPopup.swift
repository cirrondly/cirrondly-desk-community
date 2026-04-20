import AppKit
import Charts
import SwiftUI

@MainActor
final class ProviderHistoryWindowManager {
    private var windows: [String: NSWindow] = [:]
    private var closeObservers: [String: NSObjectProtocol] = [:]

    deinit {
        for observer in closeObservers.values {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    func openHistoryWindow(for provider: ProviderResult, window selectedWindow: Window) {
        let key = windowKey(for: provider, window: selectedWindow)

        if let existingWindow = windows[key] {
            if existingWindow.isMiniaturized {
                existingWindow.deminiaturize(nil)
            }
            existingWindow.orderFrontRegardless()
            existingWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let contentView = ProviderHistoryPopup(provider: provider, window: selectedWindow)
            .preferredColorScheme(.light)
        let hostingController = NSHostingController(rootView: contentView)

        let historyWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 480),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        historyWindow.contentViewController = hostingController
        historyWindow.title = "\(provider.displayName) — \(selectedWindow.kind.title)"
        historyWindow.identifier = NSUserInterfaceItemIdentifier("history.\(key)")
        historyWindow.center()
        historyWindow.minSize = NSSize(width: 560, height: 420)
        historyWindow.appearance = NSAppearance(named: .aqua)
        historyWindow.isReleasedWhenClosed = false
        historyWindow.tabbingMode = .disallowed

        let closeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: historyWindow,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }

            self.windows.removeValue(forKey: key)
            if let observer = self.closeObservers.removeValue(forKey: key) {
                NotificationCenter.default.removeObserver(observer)
            }
        }

        windows[key] = historyWindow
        closeObservers[key] = closeObserver

        historyWindow.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func windowKey(for provider: ProviderResult, window: Window) -> String {
        "\(provider.id)::\(window.id)"
    }
}

private struct HistoryBar: Identifiable {
    let id = UUID()
    let date: Date
    let value: Double
}

struct ProviderHistoryPopup: View {
    let provider: ProviderResult
    let window: Window

    private var bars: [HistoryBar] {
        computeBars(from: provider.dailyHeatmap, window: window)
    }

    private var dayCount: Int {
        historyDayCount(for: window)
    }

    var body: some View {
        ZStack {
            Color.white
                .ignoresSafeArea()

            if bars.isEmpty {
                emptyState
            } else {
                ScrollView(.vertical, showsIndicators: true) {
                    VStack(alignment: .leading, spacing: 22) {
                        VStack(alignment: .leading, spacing: 14) {
                            Text("Daily usage — last \(dayCount) days")
                                .font(Typography.body(18, weight: .semibold))
                                .foregroundStyle(Color.cirrondlyBlack)

                            HistoryBarChart(bars: bars, unit: chartUnitLabel, dayCount: dayCount)
                        }

                        Divider()
                            .overlay(Color.cirrondlyBlueLight.opacity(0.45))

                        if let forecast = window.forecast {
                            ForecastTextBlock(
                                forecast: forecast,
                                remainingAmount: remainingAmount,
                                resetAt: window.resetAt,
                                cycleUnit: cycleUnitLabel,
                                usedAmount: window.used,
                                limitAmount: window.limit
                            )
                        } else {
                            NeutralForecastTextBlock(resetAt: window.resetAt)
                        }

                        Divider()
                            .overlay(Color.cirrondlyBlueLight.opacity(0.45))

                        HistoryStatsSection(window: window)
                    }
                    .padding(24)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .frame(minWidth: 640, minHeight: 480)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "chart.bar")
                .font(.system(size: 40))
                .foregroundStyle(Color.cirrondlyBlueLight)

            Text("Building history...")
                .font(.custom("Inter-SemiBold", size: 16))
                .foregroundStyle(Color.cirrondlyBlack)

            Text("Daily usage data will appear here as you use this provider. Check back in a few days.")
                .font(.custom("Inter-Regular", size: 13))
                .foregroundStyle(Color.cirrondlyBlack.opacity(0.58))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }

    private var cycleUnitLabel: String {
        switch window.unit {
        case .tokens:
            return "tokens"
        case .requests:
            return "requests"
        case .credits:
            return "credits"
        case .dollars:
            return "USD"
        }
    }

    private var chartUnitLabel: String {
        switch window.unit {
        case .tokens:
            return "Tokens"
        case .requests:
            return "Requests"
        case .credits:
            return "Credits"
        case .dollars:
            return "USD"
        }
    }

    private var remainingAmount: Double {
        guard let limit = window.limit else { return 0 }
        return max(0, limit - window.used)
    }
}

private struct HistoryBarChart: View {
    let bars: [HistoryBar]
    let unit: String
    let dayCount: Int

    var body: some View {
        Chart(bars) { bar in
            BarMark(
                x: .value("Day", bar.date, unit: .day),
                y: .value(unit, bar.value)
            )
            .foregroundStyle(Color.cirrondlyGreenAccent)
            .cornerRadius(2)
        }
        .chartXAxis {
            AxisMarks(values: .stride(by: .day, count: xAxisStride)) { value in
                AxisGridLine()
                    .foregroundStyle(Color.cirrondlyBlueLight.opacity(0.45))
                AxisValueLabel {
                    if let date = value.as(Date.self) {
                        Text(xAxisLabel(for: date))
                            .font(.custom("Inter-Regular", size: 11))
                            .foregroundStyle(Color.cirrondlyBlack.opacity(0.58))
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading) { value in
                AxisGridLine()
                    .foregroundStyle(Color.cirrondlyBlueLight.opacity(0.45))
                AxisValueLabel {
                    if let axisValue = value.as(Double.self) {
                        Text(formatYAxisValue(axisValue))
                            .font(.custom("Inter-Regular", size: 11))
                            .foregroundStyle(Color.cirrondlyBlack.opacity(0.58))
                    }
                }
            }
        }
        .chartYScale(domain: 0 ... max(1, maxValue * 1.15))
        .frame(height: 240)
        .padding(.horizontal, 16)
        .padding(.vertical, 18)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.cirrondlyWhiteCard)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.cirrondlyBlueLight.opacity(0.55), lineWidth: 1)
        )
    }

    private var maxValue: Double {
        bars.map(\.value).max() ?? 0
    }

    private var xAxisStride: Int {
        dayCount <= 7 ? 1 : 5
    }

    private func xAxisLabel(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.dateFormat = dayCount <= 7 ? "EEE" : "MMM d"
        return formatter.string(from: date)
    }

    private func formatYAxisValue(_ value: Double) -> String {
        if value.rounded() == value {
            return Int(value).formatted()
        }
        return value.formatted(.number.precision(.fractionLength(0...1)))
    }
}

private struct ForecastTextBlock: View {
    let forecast: Forecast
    let remainingAmount: Double
    let resetAt: Date?
    let cycleUnit: String
    let usedAmount: Double
    let limitAmount: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if forecast.status == .willExceed,
               let timeToDepletion = forecast.timeToDepletion,
               let resetAt {
                Label {
                    Text("At this pace, you'll run out in \(formatDuration(timeToDepletion)), before the reset on \(formatDate(resetAt)). Consider slowing down or upgrading.")
                        .foregroundStyle(Color.cirrondlyCriticalRed)
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(Color.cirrondlyCriticalRed)
                }
                .font(.custom("Inter-Regular", size: 13))
            } else {
                Label {
                    Text(successMessage)
                        .foregroundStyle(Color.cirrondlyBlack)
                } icon: {
                    Image(systemName: "chart.line.uptrend.xyaxis")
                        .foregroundStyle(Color.cirrondlyBlueDark)
                }
                .font(.custom("Inter-Regular", size: 13))
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.cirrondlyBlueLightest)
        .cornerRadius(12)
    }

    private var successMessage: String {
        if let resetAt, let limitAmount {
            return "At current pace, you'll use ~\(Int(forecast.projectedPercentageAtReset.rounded()))% of this cycle. \(formatValue(remainingAmount)) \(cycleUnit) remaining, cycle resets \(formatDate(resetAt))."
        }

        if let resetAt {
            return "At current pace, you'll use ~\(Int(forecast.projectedPercentageAtReset.rounded()))% of this cycle. Current usage is \(formatValue(usedAmount)) \(cycleUnit), cycle resets \(formatDate(resetAt))."
        }

        if let limitAmount {
            return "At current pace, you'll use ~\(Int(forecast.projectedPercentageAtReset.rounded()))% of this cycle. \(formatValue(remainingAmount)) \(cycleUnit) remaining from \(formatValue(limitAmount))."
        }

        return "At current pace, you'll use ~\(Int(forecast.projectedPercentageAtReset.rounded()))% of this cycle."
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let totalSeconds = max(0, Int(seconds.rounded()))
        let days = totalSeconds / 86_400
        let hours = (totalSeconds % 86_400) / 3_600
        let minutes = (totalSeconds % 3_600) / 60

        if days > 0 {
            return "~\(days)d \(hours)h"
        }
        if hours > 0 {
            return "~\(hours)h \(minutes)m"
        }
        return "~\(max(1, minutes))m"
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.dateFormat = "d MMM yyyy 'at' h:mm a"
        return formatter.string(from: date)
    }

    private func formatValue(_ value: Double) -> String {
        if cycleUnit == "USD" {
            return value.formatted(.currency(code: "USD").precision(.fractionLength(0...2)))
        }
        if value.rounded() == value {
            return Int(value).formatted()
        }
        return value.formatted(.number.precision(.fractionLength(0...1)))
    }
}

private struct NeutralForecastTextBlock: View {
    let resetAt: Date?

    var body: some View {
        Label {
            Text(message)
                .foregroundStyle(Color.cirrondlyBlack)
        } icon: {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .foregroundStyle(Color.cirrondlyBlueDark)
        }
        .font(.custom("Inter-Regular", size: 13))
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.cirrondlyBlueLightest)
        .cornerRadius(12)
    }

    private var message: String {
        if let resetAt {
            return "Projection will appear here once this provider reports enough cycle data. Current cycle resets \(TimeHelpers.absoluteResetString(at: resetAt) ?? "soon")."
        }
        return "Projection will appear here once this provider reports enough cycle data."
    }
}

private struct HistoryStatsSection: View {
    let window: Window

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("This cycle so far")
                .font(Typography.body(16, weight: .semibold))
                .foregroundStyle(Color.cirrondlyBlack)

            VStack(alignment: .leading, spacing: 10) {
                HistoryStatRow(title: "Used", value: "\(formatValue(window.used)) \(unitLabel)")
                HistoryStatRow(title: "Remaining", value: remainingValue)
                HistoryStatRow(title: "Reset", value: TimeHelpers.absoluteResetString(at: window.resetAt) ?? "Unavailable")
                HistoryStatRow(title: "Time left", value: TimeHelpers.relativeResetString(until: window.resetAt) ?? "Unavailable")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var remainingValue: String {
        guard let limit = window.limit else { return "Unavailable" }
        return "\(formatValue(max(0, limit - window.used))) \(unitLabel)"
    }

    private var unitLabel: String {
        switch window.unit {
        case .tokens:
            return "tokens"
        case .requests:
            return "requests"
        case .credits:
            return "credits"
        case .dollars:
            return "USD"
        }
    }

    private func formatValue(_ value: Double) -> String {
        switch window.unit {
        case .dollars:
            return value.formatted(.currency(code: "USD").precision(.fractionLength(0...2)))
        case .tokens, .requests, .credits:
            if value.rounded() == value {
                return Int(value).formatted()
            }
            return value.formatted(.number.precision(.fractionLength(0...1)))
        }
    }
}

private struct HistoryStatRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(title)
                .font(Typography.body(12, weight: .semibold))
                .foregroundStyle(Color.cirrondlyBlack.opacity(0.62))

            Spacer(minLength: 12)

            Text(value)
                .font(Typography.body(12))
                .foregroundStyle(Color.cirrondlyBlack)
                .multilineTextAlignment(.trailing)
        }
    }
}

private func computeBars(from heatmap: [DailyCell], window: Window) -> [HistoryBar] {
    Array(
        heatmap
            .sorted { $0.date < $1.date }
            .suffix(historyDayCount(for: window))
            .map { HistoryBar(date: $0.date, value: $0.value) }
    )
}

private func historyDayCount(for window: Window) -> Int {
    switch window.kind {
    case .fiveHour, .weekly:
        return 7
    case .monthly, .custom:
        return 30
    }
}

extension ProviderResult {
    var fallbackHistoryWindow: Window {
        let fallbackUnit: UsageUnit
        if today.requests > 0 {
            fallbackUnit = .requests
        } else if today.tokens > 0 {
            fallbackUnit = .tokens
        } else if today.costUSD > 0 {
            fallbackUnit = .dollars
        } else {
            fallbackUnit = .requests
        }

        return Window(
            kind: .custom("History"),
            used: dailyHeatmap.reduce(0) { partialResult, cell in
                partialResult + cell.value
            },
            limit: nil,
            unit: fallbackUnit,
            percentage: 0,
            resetAt: nil,
            windowStart: nil,
            forecast: nil
        )
    }
}