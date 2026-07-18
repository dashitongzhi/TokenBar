import SwiftUI

struct SummaryOverviewView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 14) {
                    ForEach(appState.summaries) { summary in
                        SummaryPeriodCard(summary: summary)
                    }
                }

                InsightPanel()

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 320), spacing: 14)], spacing: 14) {
                    ForEach(appState.providers) { provider in
                        ProviderCardView(provider: provider)
                    }
                }
            }
            .padding(20)
        }
    }
}

private struct SummaryPeriodCard: View {
    @EnvironmentObject private var appState: AppState
    var summary: UsageSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(summary.title)
                .font(.headline)
            KeyValueRow(title: appState.localized("spend"), value: "$\(appState.formatMoney(summary.spend))")
            KeyValueRow(title: appState.localized("tokens"), value: "\(Int(summary.tokens))")
            KeyValueRow(title: appState.localized("requests"), value: "\(summary.requests)")
            KeyValueRow(title: appState.localized("projected"), value: "$\(appState.formatMoney(summary.projectedSpend))")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

struct SummaryTile: View {
    var title: String
    var value: String
    var symbol: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(.tint)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3.monospacedDigit().weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

struct KeyValueRow: View {
    var title: String
    var value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer(minLength: 12)
            Text(value)
                .font(.caption.weight(.medium))
                .multilineTextAlignment(.trailing)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
