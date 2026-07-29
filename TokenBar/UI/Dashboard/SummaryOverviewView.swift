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
            KeyValueRow(title: appState.localized("spend"), value: spendText)
            KeyValueRow(title: appState.localized("tokens"), value: tokensText)
            KeyValueRow(title: appState.localized("requests"), value: requestsText)
            KeyValueRow(title: appState.localized("projected"), value: "—")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var spendText: String {
        guard summary.id != "weekly", hasKnownSpend else { return "—" }
        return "$\(appState.formatMoney(summary.spend))"
    }

    private var tokensText: String {
        guard summary.id != "weekly", hasKnownTokens else { return "—" }
        return "\(Int(summary.tokens))"
    }

    private var requestsText: String {
        guard summary.id != "weekly", hasKnownRequests else { return "—" }
        return "\(summary.requests)"
    }

    private var hasKnownSpend: Bool {
        switch summary.id {
        case "daily": appState.providers.contains { $0.hasKnownSpendToday }
        case "monthly": appState.providers.contains { $0.hasKnownSpendMonth }
        default: false
        }
    }

    private var hasKnownTokens: Bool {
        switch summary.id {
        case "daily": appState.providers.contains { $0.tokensToday != nil }
        case "monthly": appState.modelUsageRollups.isEmpty == false
        default: false
        }
    }

    private var hasKnownRequests: Bool {
        switch summary.id {
        case "daily": appState.providers.contains { $0.knownTodayRequestCount != nil }
        case "monthly": appState.providers.contains { $0.knownRequestCount != nil }
        default: false
        }
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
