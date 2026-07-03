import SwiftUI

struct ProviderCardView: View {
    @EnvironmentObject private var appState: AppState
    var provider: ProviderUsage

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(provider.name)
                            .font(.subheadline.weight(.semibold))
                        Text(provider.category)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: provider.symbolName)
                        .foregroundStyle(provider.status.color)
                }
                Spacer()
                if provider.status != .healthy {
                    StatusPill(status: provider.status)
                }
                SourcePill(source: provider.sourceKind)
            }

            if let alert = provider.displayHealthAlert {
                ProviderHealthAlertView(alert: alert)
            }

            if provider.sourceDescription.isEmpty == false {
                Text(provider.sourceDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineLimit(2)
            }

            HStack(alignment: .firstTextBaseline) {
                Text(primaryUsageText)
                    .font(.title3.weight(.semibold))
                Text(secondaryUsageText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                if provider.hasKnownQuotaLimit {
                    Text("\(Int(provider.usageRatio * 100))%")
                        .font(.callout.monospacedDigit().weight(.medium))
                } else if provider.sourceKind == .live || provider.sourceKind == .localAgent || provider.sourceKind == .ccSwitch {
                    Text(provider.displayCurrency)
                        .font(.callout.monospacedDigit().weight(.medium))
                        .foregroundStyle(.secondary)
                }
            }

            if provider.hasKnownQuotaLimit {
                ProgressView(value: min(provider.usageRatio, 1))
                    .tint(provider.status.color)
            }

            MiniTrendLine(points: provider.history, color: provider.status.color)
                .frame(height: 46)

            HStack {
                metric(appState.localized("today"), todaySpendText)
                Spacer()
                metric(appState.localized("requests"), requestMetricText)
                Spacer()
                metric(appState.localized("burnRate"), "\(Int(provider.burnRatePerHour))/h")
            }
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var primaryUsageText: String {
        if provider.unit == "credits" {
            return appState.formatMoney(provider.current)
        }
        return "\(Int(provider.current))"
    }

    private var secondaryUsageText: String {
        if provider.hasKnownQuotaLimit {
            if provider.unit == "credits" {
                return "/ \(appState.formatMoney(provider.limit)) \(provider.unit)"
            }
            return "/ \(Int(provider.limit)) \(provider.unit)"
        }
        if provider.sourceKind == .live {
            return "\(provider.unit) month-to-date"
        }
        if provider.sourceKind == .localAgent {
            return provider.hasKnownQuotaLimit ? provider.unit : "\(provider.unit) local"
        }
        if provider.sourceKind == .ccSwitch {
            return "\(provider.unit) via CC Switch"
        }
        return provider.unit
    }

    private var requestMetricText: String {
        provider.knownRequestCount.map(String.init) ?? "-"
    }

    private var todaySpendText: String {
        provider.hasKnownSpendToday ? "$\(appState.formatMoney(provider.spendToday))" : "-"
    }

    private func metric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption.monospacedDigit().weight(.medium))
        }
    }
}

private struct ProviderHealthAlertView: View {
    var alert: ProviderHealthAlert

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: alert.status.symbolName)
                .foregroundStyle(alert.status.color)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 2) {
                Text(alert.title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(alert.status.color)
                Text(alert.detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
        }
        .padding(8)
        .background(alert.status.color.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}
