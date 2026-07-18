import SwiftUI

struct CompactDecisionView: View {
    @EnvironmentObject private var appState: AppState
    var decision: PolicyDecision

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: decision.status.symbolName)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(decision.status.usageStatus.color)
                    .frame(width: 30)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.headline)
                    Text("\(decision.workspaceName) · \(decision.model)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                StatusPill(status: decision.status.usageStatus)
            }

            Text(decision.recommendation)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)

            if let recommendation = decision.smartRoutingRecommendation {
                CompactSmartRoutingRecommendationView(recommendation: recommendation)
            }

            Button {
                appState.runPolicyCheck()
            } label: {
                Label(appState.localized("checkPolicy"), systemImage: "shield")
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(12)
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
}

private struct CompactSmartRoutingRecommendationView: View {
    @EnvironmentObject private var appState: AppState
    var recommendation: SmartRoutingRecommendation

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(appState.localized("smartRouting"), systemImage: "point.3.connected.trianglepath.dotted")
                .font(.caption.weight(.semibold))
            Text("\(recommendation.providerID) / \(recommendation.model)")
                .font(.caption.monospaced().weight(.medium))
                .lineLimit(1)
                .truncationMode(.middle)
            Text("\(appState.localized("confidence")) \(Int(recommendation.confidence * 100))% · \(appState.localized("evidence")) \(recommendation.evidenceRunCount)")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(8)
        .background(Color.accentColor.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
