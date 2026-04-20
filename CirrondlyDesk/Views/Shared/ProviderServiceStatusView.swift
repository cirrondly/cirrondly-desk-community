import SwiftUI

enum ProviderServiceStatusStyle {
    case dot
    case pill
}

struct ProviderServiceStatusView: View {
    @EnvironmentObject private var container: DependencyContainer
    @Environment(\.openURL) private var openURL

    let providerID: String
    var style: ProviderServiceStatusStyle = .pill

    @State private var isShowingAlert = false

    var body: some View {
        switch style {
        case .dot:
            dotBody
        case .pill:
            pillBody
        }
    }

    private var status: ProviderServiceStatus {
        container.serviceStatusMonitor.status(for: providerID)
    }

    private var dotBody: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(indicatorColor)
                .frame(width: 8, height: 8)

            if status.showsAlert {
                Button {
                    isShowingAlert = true
                } label: {
                    Image(systemName: status.health == .outage ? "exclamationmark.octagon.fill" : "exclamationmark.triangle.fill")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(indicatorColor)
                }
                .buttonStyle(.plain)
                .popover(isPresented: $isShowingAlert, arrowEdge: .bottom) {
                    alertPopover
                }
            }
        }
        .help(status.message)
    }

    private var pillBody: some View {
        Group {
            if let url = status.statusPageURL {
                Button {
                    openURL(url)
                } label: {
                    pillLabel
                }
                .buttonStyle(.plain)
            } else {
                pillLabel
            }
        }
        .help(status.message)
    }

    private var pillLabel: some View {
        ServiceStatusChip(
            status: status.health,
            onTap: status.statusPageURL.map { url in
                { openURL(url) }
            }
        )
    }

    private var alertPopover: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(status.label, systemImage: status.health == .outage ? "exclamationmark.octagon.fill" : "exclamationmark.triangle.fill")
                .font(Typography.body(13, weight: .semibold))
                .foregroundStyle(indicatorColor)

            Text(status.message)
                .font(Typography.body(11))
                .foregroundStyle(Color.cirrondlyBlueDark.opacity(0.82))
                .fixedSize(horizontal: false, vertical: true)

            if let checkedAt = status.checkedAt {
                Text("Checked \(RelativeDateTimeFormatter().localizedString(for: checkedAt, relativeTo: Date()))")
                    .font(Typography.body(10))
                    .foregroundStyle(Color.cirrondlyBlueDark.opacity(0.58))
            }

            if let url = status.statusPageURL {
                Button("Open status page") {
                    openURL(url)
                    isShowingAlert = false
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .tint(indicatorColor)
            }
        }
        .padding(14)
        .frame(width: 260, alignment: .leading)
        .background(Color.cirrondlyWhiteCard)
    }

    private var indicatorColor: Color {
        switch status.health {
        case .checking:
            return Color.cirrondlyBlueMid
        case .operational:
            return Color.cirrondlyGreenAccent
        case .degraded:
            return Color.cirrondlyWarningOrange
        case .outage:
            return Color.cirrondlyCriticalRed
        case .unknown:
            return Color.cirrondlyBlueDark.opacity(0.55)
        }
    }
}

struct ServiceStatusChip: View {
    let status: ProviderServiceHealth
    let onTap: (() -> Void)?

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(dotColor)
                .frame(width: 6, height: 6)

            Text(label)
                .font(.custom("Inter-Regular", size: 12))
                .foregroundStyle(Color.cirrondlyBlack)

            if onTap != nil {
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 10, weight: .regular))
                    .foregroundStyle(Color.cirrondlyBlack.opacity(0.4))
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(Color.clear)
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.cirrondlyBlack.opacity(0.15), lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .onTapGesture {
            onTap?()
        }
    }

    private var dotColor: Color {
        switch status {
        case .checking:
            return Color.cirrondlyBlueMid
        case .operational:
            return Color.cirrondlyGreenAccent
        case .degraded:
            return Color.cirrondlyWarningOrange
        case .outage:
            return Color.cirrondlyCriticalRed
        case .unknown:
            return Color.cirrondlyBlack.opacity(0.3)
        }
    }

    private var label: String {
        status.label
    }
}

struct ProviderServiceStatusPageButton: View {
    @EnvironmentObject private var container: DependencyContainer
    @Environment(\.openURL) private var openURL

    let providerID: String

    var body: some View {
        Group {
            if let url = status.statusPageURL {
                Button {
                    openURL(url)
                } label: {
                    Label("Status page", systemImage: "arrow.up.right.square")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .tint(tint)
            } else {
                Label("No public status page", systemImage: "slash.circle")
                    .font(Typography.body(11, weight: .semibold))
                    .foregroundStyle(Color.cirrondlyBlueDark.opacity(0.45))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(Color.cirrondlyBlueLightest.opacity(0.8), in: Capsule())
            }
        }
        .help(status.message)
    }

    private var status: ProviderServiceStatus {
        container.serviceStatusMonitor.status(for: providerID)
    }

    private var tint: Color {
        switch status.health {
        case .checking:
            return Color.cirrondlyBlueMid
        case .operational:
            return Color.cirrondlyGreenAccent
        case .degraded:
            return Color.cirrondlyWarningOrange
        case .outage:
            return Color.cirrondlyCriticalRed
        case .unknown:
            return Color.cirrondlyBlueDark.opacity(0.55)
        }
    }
}