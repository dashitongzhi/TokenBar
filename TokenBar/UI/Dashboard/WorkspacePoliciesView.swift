import SwiftUI

struct WorkspacePoliciesView: View {
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

            if workspace.dailyBudget > 0 {
                ProgressView(value: min(workspace.dailyRatio, 1))
                    .tint(workspace.status.color)
            }

            KeyValueRow(title: appState.localized("dailyBudget"), value: dailyBudgetText)
            KeyValueRow(title: appState.localized("monthlyBudget"), value: monthlyBudgetText)
            KeyValueRow(title: appState.localized("allowedProviders"), value: providerNames)
            KeyValueRow(title: appState.localized("preferredProvider"), value: preferredProviderName)
            KeyValueRow(title: appState.localized("defaultModel"), value: workspace.preferredModel?.isEmpty == false ? workspace.preferredModel ?? "-" : "-")
            KeyValueRow(title: appState.localized("blockedModels"), value: workspace.blockedModels.isEmpty ? "-" : workspace.blockedModels.joined(separator: ", "))
            PerRunCapEditor(workspace: workspace)
            KeyValueRow(title: appState.localized("companyKey"), value: workspace.requireCompanyKey ? appState.localized("required") : appState.localized("optional"))
            if let setupSourceDetail = workspace.setupSourceDetail, setupSourceDetail.isEmpty == false {
                Text(setupSourceDetail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
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

    private var preferredProviderName: String {
        guard let id = workspace.preferredProviderID, id.isEmpty == false else { return "-" }
        return appState.providers.first { $0.id == id }?.name ?? id
    }

    private var dailyBudgetText: String {
        guard workspace.dailyBudget > 0 else { return appState.localized("noBudgetSet") }
        return "$\(appState.formatMoney(workspace.spendToday)) / $\(appState.formatMoney(workspace.dailyBudget))"
    }

    private var monthlyBudgetText: String {
        guard workspace.monthlyBudget > 0 else { return appState.localized("noBudgetSet") }
        return "$\(appState.formatMoney(workspace.spendMonth)) / $\(appState.formatMoney(workspace.monthlyBudget))"
    }
}

private struct PerRunCapEditor: View {
    @EnvironmentObject private var appState: AppState
    var workspace: WorkspacePolicy

    private var capBinding: Binding<Double> {
        Binding(
            get: { workspace.maxEstimatedRunCost },
            set: { appState.updateWorkspaceMaxEstimatedRunCost(id: workspace.id, value: $0) }
        )
    }

    private var step: Double {
        workspace.maxEstimatedRunCost >= 10 ? 1 : 0.05
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(appState.localized("perRunCap"))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                HStack(spacing: 6) {
                    Button {
                        appState.adjustWorkspaceMaxEstimatedRunCost(id: workspace.id, delta: -step)
                    } label: {
                        Image(systemName: "minus")
                            .frame(width: 14, height: 14)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .accessibilityLabel(appState.localized("decreasePerRunCap"))

                    TextField("", value: capBinding, format: .number.precision(.fractionLength(2)))
                        .textFieldStyle(.roundedBorder)
                        .multilineTextAlignment(.trailing)
                        .monospacedDigit()
                        .frame(width: 82)
                        .accessibilityLabel(appState.localized("perRunCap"))

                    Button {
                        appState.adjustWorkspaceMaxEstimatedRunCost(id: workspace.id, delta: step)
                    } label: {
                        Image(systemName: "plus")
                            .frame(width: 14, height: 14)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .accessibilityLabel(appState.localized("increasePerRunCap"))
                }
            }

            Text(appState.localized("perRunCapHelp"))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
