import SwiftUI
import AppKit

struct MenuBarPopoverView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(spacing: 12) {
                    CompactDecisionView(decision: appState.currentDecision)
                    InsightPanel()
                    if appState.focusModeEnabled || appState.sessionBudget > 0 {
                        FocusBudgetView(compact: true)
                    }
                    CompactQuotaWindowView()
                    CompactModelUsageView()
                    ForEach(appState.workspacePolicies.prefix(2)) { workspace in
                        CompactWorkspaceView(workspace: workspace)
                    }
                    AuditPanel(limit: 4)
                }
                .padding(14)
            }
            footer
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image("TokenBarGlyph")
                .resizable()
                .scaledToFit()
                .frame(width: 28, height: 26)
            VStack(alignment: .leading, spacing: 1) {
                Text(appState.localized("app.title"))
                    .font(.headline)
                Text(appState.localized("productTagline"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Button {
                appState.refreshAll()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .help(appState.localized("refresh"))
        }
        .padding(14)
        .background(.thinMaterial)
    }

    private var footer: some View {
        HStack {
            Text("\(appState.currentDecision.status.rawValue.uppercased()) · \(appState.currentDecision.workspaceName)")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Button(appState.localized("settings")) {
                NSApp.activate(ignoringOtherApps: true)
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
            }
            Button(appState.localized("quit")) {
                NSApp.terminate(nil)
            }
        }
        .padding(14)
        .background(.thinMaterial)
    }
}

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

struct CompactWorkspaceView: View {
    @EnvironmentObject private var appState: AppState
    var workspace: WorkspacePolicy

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(workspace.name, systemImage: "folder.fill")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(budgetText)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            if workspace.dailyBudget > 0 {
                ProgressView(value: min(workspace.dailyRatio, 1))
                    .tint(workspace.status.color)
            }
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var budgetText: String {
        guard workspace.dailyBudget > 0 else { return appState.localized("noBudgetSet") }
        return "$\(appState.formatMoney(workspace.spendToday)) / $\(appState.formatMoney(workspace.dailyBudget))"
    }
}

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
                    if provider.primaryHealthAlert != nil {
                        StatusPill(status: provider.status)
                            .scaleEffect(0.84, anchor: .leading)
                    }
                }
                Text(detailText)
                    .font(.caption2)
                    .foregroundStyle(provider.primaryHealthAlert == nil ? .secondary : provider.status.color)
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
        if provider.primaryHealthAlert != nil {
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
        if let alert = provider.primaryHealthAlert {
            return alert.detail
        }
        return provider.sourceDescription.isEmpty ? appState.localized("noLiveQuotaYet") : provider.sourceDescription
    }
}

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
