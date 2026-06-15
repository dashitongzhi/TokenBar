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
                SourcePill(source: provider.sourceKind)
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
                } else if provider.sourceKind == .live {
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
                metric(appState.localized("today"), "$\(appState.formatMoney(provider.spendToday))")
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
        "\(Int(provider.current))"
    }

    private var secondaryUsageText: String {
        if provider.hasKnownQuotaLimit {
            return "/ \(Int(provider.limit)) \(provider.unit)"
        }
        if provider.sourceKind == .live {
            return "\(provider.unit) month-to-date"
        }
        return provider.unit
    }

    private var requestMetricText: String {
        provider.knownRequestCount.map(String.init) ?? "-"
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
