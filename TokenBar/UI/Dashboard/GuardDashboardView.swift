import SwiftUI

struct GuardDashboardView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                PolicyDecisionHero(decision: appState.currentDecision)

                HStack(spacing: 14) {
                    SummaryTile(title: appState.localized("workspaceBudget"), value: workspaceBudgetText, symbol: "folder.badge.gearshape")
                    SummaryTile(title: appState.localized("estimatedRun"), value: "$\(appState.formatMoney(appState.estimatedRunCost))", symbol: "bolt.badge.clock")
                    SummaryTile(title: appState.localized("sessionBudget"), value: sessionBudgetText, symbol: "gauge.with.dots.needle.50percent")
                }

                RunConfigurationPanel()
                RecentDecisionsPanel()
            }
            .padding(20)
        }
    }

    private var workspaceBudgetText: String {
        guard let workspace = appState.selectedWorkspace else { return "-" }
        guard workspace.dailyBudget > 0 else { return appState.localized("noBudgetSet") }
        return "$\(appState.formatMoney(workspace.spendToday)) / $\(appState.formatMoney(workspace.dailyBudget))"
    }

    private var sessionBudgetText: String {
        guard appState.sessionBudget > 0 else { return appState.localized("noSessionBudget") }
        return "$\(appState.formatMoney(appState.projectedSessionSpend)) / $\(appState.formatMoney(appState.sessionBudget))"
    }
}

private struct PolicyDecisionHero: View {
    @EnvironmentObject private var appState: AppState
    var decision: PolicyDecision

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: decision.status.symbolName)
                    .font(.system(size: 36, weight: .semibold))
                    .foregroundStyle(decision.status.usageStatus.color)
                    .frame(width: 48)

                VStack(alignment: .leading, spacing: 5) {
                    Text(title)
                        .font(.title2.weight(.semibold))
                    Text("\(decision.agent.displayName) · \(decision.workspaceName) · \(decision.model)")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                StatusPill(status: decision.status.usageStatus)
            }

            VStack(alignment: .leading, spacing: 8) {
                ForEach(decision.reasons, id: \.self) { reason in
                    Label(reason, systemImage: "smallcircle.filled.circle")
                        .font(.callout)
                }
            }

            Text(decision.recommendation)
                .font(.callout.weight(.medium))
                .fixedSize(horizontal: false, vertical: true)

            if let recommendation = decision.smartRoutingRecommendation {
                SmartRoutingRecommendationView(recommendation: recommendation)
            }

            HStack {
                metric(appState.localized("projectedToday"), "$\(appState.formatMoney(decision.projectedDailySpend))")
                Divider()
                metric(appState.localized("estimatedRun"), "$\(appState.formatMoney(decision.estimatedCost))")
                Divider()
                metric(appState.localized("fallback"), fallbackText)
            }
            .frame(height: 46)
        }
        .padding(18)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var title: String {
        switch decision.status {
        case .allow: appState.localized("decisionAllow")
        case .warn: appState.localized("decisionWarn")
        case .block: appState.localized("decisionBlock")
        }
    }

    private var fallbackText: String {
        guard let id = decision.fallbackProviderID else { return "-" }
        return appState.providers.first { $0.id == id }?.name ?? id
    }

    private func metric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.callout.monospacedDigit().weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.78)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct SmartRoutingRecommendationView: View {
    @EnvironmentObject private var appState: AppState
    var recommendation: SmartRoutingRecommendation

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Label(appState.localized("smartRouting"), systemImage: "point.3.connected.trianglepath.dotted")
                    .font(.caption.weight(.semibold))
                Spacer()
                Text("\(Int(recommendation.confidence * 100))%")
                    .font(.caption.monospacedDigit().weight(.medium))
                    .foregroundStyle(.secondary)
            }

            Text("\(recommendation.providerID) / \(recommendation.model)")
                .font(.callout.monospaced().weight(.semibold))
                .lineLimit(1)
                .truncationMode(.middle)

            Text(recommendation.reason)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 12) {
                metric(appState.localized("evidence"), "\(recommendation.evidenceRunCount)")
                metric(appState.localized("winRate"), "\(Int(recommendation.winRate * 100))%")
                metric(appState.localized("estimatedRun"), "$\(appState.formatMoney(recommendation.estimatedCost))")
            }
        }
        .padding(10)
        .background(Color.accentColor.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func metric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption.monospacedDigit().weight(.medium))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct RecentDecisionsPanel: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(appState.localized("recentDecisions"), systemImage: "clock.arrow.circlepath")
                .font(.headline)

            ForEach(appState.recentDecisions.prefix(6)) { decision in
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: decision.status.symbolName)
                        .foregroundStyle(decision.status.usageStatus.color)
                        .frame(width: 18)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(decision.status.rawValue.uppercased()) · \(decision.workspaceName)")
                            .font(.caption.weight(.semibold))
                        Text("\(decision.agent.displayName) · \(decision.providerID) · \(decision.model)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(decision.timestamp, style: .time)
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(14)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
