import SwiftUI

struct RunConfigurationPanel: View {
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

            Picker(appState.localized("routingMode"), selection: $appState.routingMode) {
                ForEach(RoutingMode.allCases) { mode in
                    Label(mode.title(language: appState.language), systemImage: mode.symbolName).tag(mode)
                }
            }
            .pickerStyle(.segmented)

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

                    ModelSelectionControl()
                }

                GridRow {
                    VStack(alignment: .leading) {
                        Text(appState.localized("estimatedRun"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Slider(value: $appState.estimatedRunCost, in: 0...5, step: 0.05)
                    }

                    VStack(alignment: .leading) {
                        Text(appState.localized("estimatedTokens"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Slider(value: $appState.estimatedTokens, in: 0...500_000, step: 1_000)
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

private struct ModelSelectionControl: View {
    @EnvironmentObject private var appState: AppState

    private var models: [ModelCatalogItem] {
        appState.selectedProviderModelCatalog
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                if models.isEmpty {
                    TextField(appState.localized("model"), text: $appState.selectedModel)
                        .textFieldStyle(.roundedBorder)
                } else {
                    Picker(appState.localized("model"), selection: $appState.selectedModel) {
                        ForEach(models) { item in
                            Text(item.modelID).tag(item.modelID)
                        }
                    }
                    .labelsHidden()
                    .frame(minWidth: 180)
                }

                Button {
                    appState.refreshModelCatalog()
                } label: {
                    Image(systemName: "arrow.down.circle")
                        .frame(width: 14, height: 14)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(appState.isRefreshingModelCatalog)
                .help(appState.localized("pullModels"))
            }

            TextField(appState.localized("manualModelEntry"), text: $appState.selectedModel)
                .textFieldStyle(.roundedBorder)
                .font(.caption)
        }
    }
}
