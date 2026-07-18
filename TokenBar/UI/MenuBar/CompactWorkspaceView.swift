import SwiftUI

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
