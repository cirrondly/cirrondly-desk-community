import SwiftUI

struct ContributionHeatmap: View {
    let cells: [DailyCell]
    var accentColor: Color = .cirrondlyGreenAccent

    private let columnCount = 13
    private let rowCount = 7
    private let cellSize: CGFloat = 11
    private let cellSpacing: CGFloat = 4

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Recent activity")
                    .font(Typography.body(10, weight: .semibold))
                    .foregroundStyle(Color.cirrondlyBlueDark.opacity(0.66))

                Spacer()

                Text(isPlaceholder ? "Waiting for local history" : "Last 13 weeks")
                    .font(Typography.body(10))
                    .foregroundStyle(Color.cirrondlyBlueDark.opacity(0.52))
            }

            HStack(alignment: .top, spacing: cellSpacing) {
                ForEach(Array(weeks.enumerated()), id: \.offset) { _, week in
                    VStack(spacing: cellSpacing) {
                        ForEach(week) { cell in
                            RoundedRectangle(cornerRadius: 3)
                                .fill(fill(for: cell.intensity))
                                .frame(width: cellSize, height: cellSize)
                        }
                    }
                }
            }
        }
    }

    private var isPlaceholder: Bool {
        cells.isEmpty
    }

    private var normalizedCells: [DailyCell] {
        let desiredCount = columnCount * rowCount
        let source = cells.isEmpty ? placeholderCells : Array(cells.suffix(desiredCount))
        let padding = max(0, desiredCount - source.count)
        return Array(repeating: placeholderCell, count: padding) + source
    }

    private var weeks: [[DailyCell]] {
        stride(from: 0, to: normalizedCells.count, by: rowCount).map { offset in
            Array(normalizedCells[offset..<min(offset + rowCount, normalizedCells.count)])
        }
    }

    private var placeholderCells: [DailyCell] {
        let total = columnCount * rowCount
        let start = Calendar.current.date(byAdding: .day, value: -(total - 1), to: TimeHelpers.startOfDay(for: Date())) ?? Date()

        return (0..<total).compactMap { index in
            guard let date = Calendar.current.date(byAdding: .day, value: index, to: start) else {
                return nil
            }
            return DailyCell(date: date, value: 0, intensity: .zero)
        }
    }

    private var placeholderCell: DailyCell {
        DailyCell(date: .distantPast, value: 0, intensity: .zero)
    }

    private func fill(for intensity: UsageIntensity) -> Color {
        switch intensity {
        case .zero:
            return Color.cirrondlyBlueLight.opacity(0.18)
        case .low:
            return accentColor.opacity(0.26)
        case .medium:
            return accentColor.opacity(0.42)
        case .high:
            return accentColor.opacity(0.62)
        case .peak:
            return accentColor
        }
    }
}