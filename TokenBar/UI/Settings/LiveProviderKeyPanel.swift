import SwiftUI

struct LiveProviderCredentialPanels: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(spacing: 12) {
            LiveProviderKeyPanel(
                providerID: "openai",
                titleKey: "openAILiveUsage",
                fieldKey: "openAIAdminKey",
                symbolName: "brain.head.profile",
                savedKey: "openAIKeySaved",
                clearedKey: "openAIKeyCleared",
                saveAction: appState.storeOpenAIAdminKey,
                clearAction: appState.clearOpenAIAdminKey
            )

            LiveProviderKeyPanel(
                providerID: "anthropic",
                titleKey: "anthropicLiveUsage",
                fieldKey: "anthropicAdminKey",
                symbolName: "sparkles",
                savedKey: "anthropicKeySaved",
                clearedKey: "anthropicKeyCleared",
                saveAction: appState.storeAnthropicAdminKey,
                clearAction: appState.clearAnthropicAdminKey
            )

            LiveProviderKeyPanel(
                providerID: "openrouter",
                titleKey: "openRouterLiveUsage",
                fieldKey: "openRouterAPIKey",
                symbolName: "point.3.connected.trianglepath.dotted",
                savedKey: "openRouterKeySaved",
                clearedKey: "openRouterKeyCleared",
                saveAction: appState.storeOpenRouterAPIKey,
                clearAction: appState.clearOpenRouterAPIKey
            )

            LiveProviderKeyPanel(
                providerID: "minimax",
                titleKey: "miniMaxLiveUsage",
                fieldKey: "miniMaxAPIKey",
                symbolName: "bolt.horizontal.circle.fill",
                savedKey: "miniMaxKeySaved",
                clearedKey: "miniMaxKeyCleared",
                saveAction: appState.storeMiniMaxAPIKey,
                clearAction: appState.clearMiniMaxAPIKey
            )
        }
    }
}

private struct LiveProviderKeyPanel: View {
    @EnvironmentObject private var appState: AppState
    var providerID: String
    var titleKey: String
    var fieldKey: String
    var symbolName: String
    var savedKey: String
    var clearedKey: String
    var saveAction: (String) async throws -> Void
    var clearAction: () async throws -> Void

    @State private var adminKey = ""
    @State private var baseURL = ""
    @State private var message = ""
    @State private var isSaving = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(appState.localized(titleKey), systemImage: symbolName)
                    .font(.headline)
                Spacer()
                if let provider = appState.providers.first(where: { $0.id == providerID }) {
                    SourcePill(source: provider.sourceKind)
                }
            }

            HStack(spacing: 8) {
                SecureField(appState.localized(fieldKey), text: $adminKey)
                    .textFieldStyle(.roundedBorder)

                Button {
                    save()
                } label: {
                    Label(appState.localized("save"), systemImage: "key.fill")
                }
                .disabled(isSaving || adminKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                Button {
                    clear()
                } label: {
                    Label(appState.localized("clear"), systemImage: "trash")
                }
                .disabled(isSaving)

                Button {
                    appState.refreshAll()
                } label: {
                    Label(appState.localized("refresh"), systemImage: "arrow.clockwise")
                }
                .disabled(appState.isRefreshingUsage)
            }

            HStack(spacing: 8) {
                TextField(defaultBaseURL, text: $baseURL)
                    .textFieldStyle(.roundedBorder)
                    .help(appState.localized("baseURL"))

                Button {
                    pullModels()
                } label: {
                    Label(appState.localized("pullModels"), systemImage: "arrow.down.circle")
                }
                .disabled(appState.isRefreshingModelCatalog)
            }

            if message.isEmpty == false {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else if let provider = appState.providers.first(where: { $0.id == providerID }) {
                Text(provider.sourceDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .onAppear {
            baseURL = UserDefaults.standard.string(forKey: baseURLPreferenceKey) ?? defaultBaseURL
        }
    }

    private func save() {
        let trimmed = adminKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return }
        isSaving = true
        Task {
            do {
                try await saveAction(trimmed)
                await MainActor.run {
                    adminKey = ""
                    message = appState.localized(savedKey)
                    isSaving = false
                    pullModels()
                }
            } catch {
                await MainActor.run {
                    message = error.localizedDescription
                    isSaving = false
                }
            }
        }
    }

    private func clear() {
        isSaving = true
        Task {
            do {
                try await clearAction()
                await MainActor.run {
                    message = appState.localized(clearedKey)
                    isSaving = false
                }
            } catch {
                await MainActor.run {
                    message = error.localizedDescription
                    isSaving = false
                }
            }
        }
    }

    private func pullModels() {
        let trimmed = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        UserDefaults.standard.set(trimmed, forKey: baseURLPreferenceKey)
        appState.refreshModelCatalog(providerID: providerID, baseURL: trimmed.isEmpty ? nil : trimmed)
        message = appState.localized("modelCatalogRefreshing")
    }

    private var baseURLPreferenceKey: String {
        "modelBaseURL.\(providerID)"
    }

    private var defaultBaseURL: String {
        switch providerID {
        case "openai": "https://api.openai.com/v1"
        case "anthropic": "https://api.anthropic.com/v1"
        case "openrouter": "https://openrouter.ai/api/v1"
        case "minimax": "https://api.minimax.io/v1"
        default: ""
        }
    }
}
