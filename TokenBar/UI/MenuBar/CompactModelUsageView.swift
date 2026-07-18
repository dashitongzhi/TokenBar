import SwiftUI

struct CompactModelUsageView: View {
    @EnvironmentObject private var appState: AppState

    private var rows: [ModelUsageRollup] {
        Array(appState.visibleModelUsageRollups.prefix(5))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(appState.localized("modelUsage"), systemImage: "cpu")
                    .font(.headline)
                Spacer()
                Text(appState.localized("today"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if rows.isEmpty {
                Text(appState.localized("modelUsageEmpty"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ForEach(rows) { row in
                    ModelUsageRow(row: row)
                }
            }
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private struct ModelUsageRow: View {
    @EnvironmentObject private var appState: AppState
    var row: ModelUsageRollup

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: row.agent.symbolName)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(row.hasUsage ? Color.accentColor : .secondary)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 3) {
                Text(row.model)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 3) {
                Text(primaryMetric)
                    .font(.caption.monospacedDigit().weight(.semibold))
                Text(secondaryMetric)
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    private var subtitle: String {
        let provider = appState.providers.first { $0.id == row.providerID }?.name ?? row.providerID
        let source = row.source == .configured ? appState.localized("configuredModel") : appState.localized("localUsage")
        return "\(row.agent.displayName) · \(provider) · \(source)"
    }

    private var primaryMetric: String {
        row.hasUsage ? "$\(appState.formatMoney(row.spendToday))" : "-"
    }

    private var secondaryMetric: String {
        if row.tokensToday > 0 {
            return "\(Int(row.tokensToday)) tok"
        }
        if row.source == .configured {
            return appState.localized("configured")
        }
        return "-"
    }
}
