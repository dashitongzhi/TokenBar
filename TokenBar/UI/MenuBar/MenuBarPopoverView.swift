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
                    CompactRuntimeSnapshotView()
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
