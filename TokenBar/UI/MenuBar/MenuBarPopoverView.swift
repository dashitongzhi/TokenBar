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
                    FocusBudgetView(compact: true)
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
            Image(systemName: "chart.bar.xaxis")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.tint)
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

struct CompactWorkspaceView: View {
    @EnvironmentObject private var appState: AppState
    var workspace: WorkspacePolicy

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(workspace.name, systemImage: "folder.fill")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text("$\(appState.formatMoney(workspace.spendToday)) / $\(appState.formatMoney(workspace.dailyBudget))")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: min(workspace.dailyRatio, 1))
                .tint(workspace.status.color)
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
