import SwiftUI

struct MainDashboardView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        NavigationSplitView {
            List(selection: $appState.selectedMainSection) {
                ForEach(MainSection.allCases) { section in
                    Label(section.title(language: appState.language), systemImage: section.symbolName)
                        .tag(section)
                }
            }
            .navigationTitle(appState.localized("app.title"))
            .toolbar {
                Button {
                    appState.refreshAll()
                } label: {
                    Label(appState.localized("refresh"), systemImage: "arrow.clockwise")
                }
            }
        } detail: {
            switch appState.selectedMainSection {
            case .guardrail:
                GuardDashboardView()
                    .navigationTitle(appState.localized("guard"))
            case .workspaces:
                WorkspacePoliciesView()
                    .navigationTitle(appState.localized("workspaces"))
            case .summary:
                SummaryOverviewView()
                    .navigationTitle(appState.localized("summary"))
            case .integrations:
                IntegrationsOverviewView()
                    .navigationTitle(appState.localized("integrations"))
            }
        }
        .environmentObject(appState)
    }
}

private struct GuardDashboardView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                PolicyDecisionHero(decision: appState.currentDecision)

                HStack(spacing: 14) {
                    SummaryTile(title: appState.localized("workspaceBudget"), value: workspaceBudgetText, symbol: "folder.badge.gearshape")
                    SummaryTile(title: appState.localized("estimatedRun"), value: "$\(appState.formatMoney(appState.estimatedRunCost))", symbol: "bolt.badge.clock")
                    SummaryTile(title: appState.localized("sessionBudget"), value: "$\(appState.formatMoney(appState.projectedSessionSpend)) / $\(appState.formatMoney(appState.sessionBudget))", symbol: "gauge.with.dots.needle.50percent")
                }

                RunConfigurationPanel()
                RecentDecisionsPanel()
            }
            .padding(20)
        }
    }

    private var workspaceBudgetText: String {
        guard let workspace = appState.selectedWorkspace else { return "-" }
        return "$\(appState.formatMoney(workspace.spendToday)) / $\(appState.formatMoney(workspace.dailyBudget))"
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

private struct RunConfigurationPanel: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label(appState.localized("preflight"), systemImage: "checklist")
                    .font(.headline)
                Spacer()
                Button {
                    appState.runPolicyCheck()
                } label: {
                    Label(appState.localized("checkPolicy"), systemImage: "shield")
                }
            }

            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 12) {
                GridRow {
                    Picker(appState.localized("agent"), selection: $appState.selectedAgent) {
                        ForEach(AgentProvider.allCases) { agent in
                            Label(agent.displayName, systemImage: agent.symbolName).tag(agent)
                        }
                    }

                    Picker(appState.localized("workspace"), selection: $appState.selectedWorkspaceID) {
                        ForEach(appState.workspacePolicies) { workspace in
                            Text(workspace.name).tag(workspace.id)
                        }
                    }
                }

                GridRow {
                    Picker(appState.localized("provider"), selection: $appState.selectedProviderID) {
                        ForEach(appState.providers) { provider in
                            Text(provider.name).tag(provider.id)
                        }
                    }

                    TextField(appState.localized("model"), text: $appState.selectedModel)
                }

                GridRow {
                    VStack(alignment: .leading) {
                        Text(appState.localized("estimatedRun"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Slider(value: $appState.estimatedRunCost, in: 0.05...5, step: 0.05)
                    }

                    VStack(alignment: .leading) {
                        Text(appState.localized("estimatedTokens"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Slider(value: $appState.estimatedTokens, in: 1_000...500_000, step: 1_000)
                    }
                }
            }

            HStack {
                Text("$\(appState.formatMoney(appState.estimatedRunCost))")
                    .monospacedDigit()
                Spacer()
                Text("\(Int(appState.estimatedTokens)) tokens")
                    .monospacedDigit()
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(14)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
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

private struct WorkspacePoliciesView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 340), spacing: 14)], spacing: 14) {
                ForEach(appState.workspacePolicies) { workspace in
                    WorkspacePolicyCard(workspace: workspace)
                }
            }
            .padding(20)
        }
    }
}

private struct WorkspacePolicyCard: View {
    @EnvironmentObject private var appState: AppState
    var workspace: WorkspacePolicy

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(workspace.name)
                            .font(.headline)
                        Text(workspace.pathHint)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: "folder.fill")
                        .foregroundStyle(workspace.status.color)
                }
                Spacer()
                StatusPill(status: workspace.status)
            }

            ProgressView(value: min(workspace.dailyRatio, 1))
                .tint(workspace.status.color)

            KeyValueRow(title: appState.localized("dailyBudget"), value: "$\(appState.formatMoney(workspace.spendToday)) / $\(appState.formatMoney(workspace.dailyBudget))")
            KeyValueRow(title: appState.localized("monthlyBudget"), value: "$\(appState.formatMoney(workspace.spendMonth)) / $\(appState.formatMoney(workspace.monthlyBudget))")
            KeyValueRow(title: appState.localized("allowedProviders"), value: providerNames)
            KeyValueRow(title: appState.localized("blockedModels"), value: workspace.blockedModels.isEmpty ? "-" : workspace.blockedModels.joined(separator: ", "))
            KeyValueRow(title: appState.localized("perRunCap"), value: "$\(appState.formatMoney(workspace.maxEstimatedRunCost))")
            KeyValueRow(title: appState.localized("companyKey"), value: workspace.requireCompanyKey ? appState.localized("required") : appState.localized("optional"))
        }
        .padding(14)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var providerNames: String {
        workspace.allowedProviderIDs.compactMap { id in
            appState.providers.first { $0.id == id }?.name ?? id
        }.joined(separator: ", ")
    }
}

private struct IntegrationsOverviewView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 14) {
                    SummaryTile(
                        title: appState.localized("liveData"),
                        value: "\(appState.liveProviderCount)",
                        symbol: "checkmark.seal.fill"
                    )
                    SummaryTile(
                        title: appState.localized("unsupportedProviders"),
                        value: "\(appState.unsupportedProviderCount)",
                        symbol: "exclamationmark.triangle.fill"
                    )
                    SummaryTile(
                        title: appState.localized("localAPI"),
                        value: appState.localAPISummaryValue,
                        symbol: appState.localAPIStatus.symbolName
                    )
                }

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 420), spacing: 14)], spacing: 14) {
                    ForEach(appState.apiMonitors) { spec in
                        APIMonitorCard(spec: spec)
                    }
                }
            }
            .padding(20)
        }
    }
}

private struct APIMonitorCard: View {
    @EnvironmentObject private var appState: AppState
    var spec: APIMonitorSpec

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(spec.name)
                            .font(.headline)
                        Text(spec.family)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: spec.symbolName)
                        .foregroundStyle(spec.capability.status.color)
                }
                Spacer()
                if let provider = appState.providers.first(where: { $0.id == spec.id }) {
                    SourcePill(source: provider.sourceKind)
                } else {
                    Text(spec.capability.title(language: appState.language))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(spec.capability.status.color)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(spec.capability.status.color.opacity(0.12))
                        .clipShape(Capsule())
                }
            }

            if let provider = appState.providers.first(where: { $0.id == spec.id }),
               provider.sourceDescription.isEmpty == false {
                Text(provider.sourceDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            KeyValueRow(title: appState.localized("models"), value: spec.models.prefix(5).joined(separator: ", "))
            KeyValueRow(title: appState.localized("subscriptionAlert"), value: spec.alertMetric)

            if let request = spec.usageRequest {
                RequestBlock(title: appState.localized("realRequest"), request: request)
            } else {
                Text(spec.note)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                Link(appState.localized("source"), destination: URL(string: spec.docsURL)!)
                Spacer()
                Link("Console", destination: URL(string: spec.subscriptionURL)!)
            }
            .font(.caption.weight(.medium))
        }
        .padding(14)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private struct RequestBlock: View {
    var title: String
    var request: APIRequestTemplate

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
            Text(curl)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
                .lineLimit(6)
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(nsColor: .textBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
    }

    private var curl: String {
        var lines = ["curl -X \(request.method) \"\(request.url)\""]
        lines.append(contentsOf: request.headers.map { "  -H \"\($0)\"" })
        if let body = request.body {
            lines.append("  -d '\(body)'")
        }
        return lines.joined(separator: " \\\n")
    }
}

private struct SummaryOverviewView: View {
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

private struct SummaryTile: View {
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

private struct KeyValueRow: View {
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
