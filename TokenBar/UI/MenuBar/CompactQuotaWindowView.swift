import SwiftUI

struct CompactQuotaWindowView: View {
    @EnvironmentObject private var appState: AppState

    private var rows: [ProviderUsage] {
        Array(appState.providers.filter { provider in
            provider.sourceKind == .live || provider.sourceKind == .ccSwitch || provider.id == "codex" || provider.id == "minimax"
        }.prefix(5))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(appState.localized("quotaWindows"), systemImage: "gauge.with.dots.needle.50percent")
                    .font(.headline)
                Spacer()
                Button {
                    appState.refreshAll()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .help(appState.localized("refresh"))
            }

            if rows.isEmpty {
                Text(appState.localized("quotaWindowsEmpty"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ForEach(rows) { provider in
                    QuotaWindowRow(provider: provider)
                }
            }
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private struct QuotaWindowRow: View {
    @EnvironmentObject private var appState: AppState
    var provider: ProviderUsage

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: provider.symbolName)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(provider.status.color)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(provider.name)
                        .font(.caption.weight(.semibold))
                    SourcePill(source: provider.sourceKind)
                        .scaleEffect(0.84, anchor: .leading)
                    if provider.displayHealthAlert != nil {
                        StatusPill(status: provider.status)
                            .scaleEffect(0.84, anchor: .leading)
                    }
                }
                Text(detailText)
                    .font(.caption2)
                    .foregroundStyle(provider.displayHealthAlert == nil ? .secondary : provider.status.color)
                    .lineLimit(2)
            }

            Spacer(minLength: 8)

            Text(metricText)
                .font(.caption.monospacedDigit().weight(.semibold))
                .foregroundStyle(provider.status.color)
        }
        .padding(.vertical, 2)
    }

    private var metricText: String {
        if provider.displayHealthAlert != nil {
            return provider.status.rawValue.uppercased()
        }
        if provider.hasKnownQuotaLimit {
            if provider.unit == "percent" {
                return "\(Int(provider.current))%"
            }
            if provider.unit == "credits" {
                return appState.formatMoney(provider.current)
            }
            return "\(Int(provider.current))"
        }
        if provider.todayTokenCount > 0 {
            return "\(Int(provider.todayTokenCount)) tok"
        }
        return "-"
    }

    private var detailText: String {
        if let alert = provider.displayHealthAlert {
            return alert.detail
        }
        return provider.sourceDescription.isEmpty ? appState.localized("noLiveQuotaYet") : provider.sourceDescription
    }
}
