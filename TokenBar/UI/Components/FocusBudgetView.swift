import SwiftUI

struct FocusBudgetView: View {
    @EnvironmentObject private var appState: AppState
    var compact = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(appState.localized("focusMode"), systemImage: "scope")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text(appState.budgetStatus == .healthy ? appState.localized("budgetSafe") : appState.localized("budgetAtRisk"))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(appState.budgetStatus.color)
            }

            HStack(alignment: .firstTextBaseline) {
                if appState.sessionBudget > 0 {
                    Text("$\(appState.formatMoney(appState.sessionSpend))")
                        .font(compact ? .title3.weight(.semibold) : .title2.weight(.semibold))
                    Text("/ $\(appState.formatMoney(appState.sessionBudget))")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                } else {
                    Text(appState.localized("noSessionBudget"))
                        .font(compact ? .headline : .title3.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(appState.focusModeEnabled ? appState.localized("stop") : appState.localized("start")) {
                    appState.focusModeEnabled.toggle()
                }
                Button {
                    appState.resetSessionBudget()
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                }
                .help("Reset")
            }

            if appState.sessionBudget > 0 {
                ProgressView(value: min(appState.budgetRatio, 1))
                    .tint(appState.budgetStatus.color)
            }
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
