import Foundation

@MainActor
extension AppState {
    func storeOpenAIAdminKey(_ key: String) async throws {
        try await storeCredential(key, keyName: "OPENAI_ADMIN_KEY", provider: "OpenAI", detail: "Stored OpenAI admin key in Keychain")
    }

    func clearOpenAIAdminKey() async throws {
        try await clearCredential(
            keyName: "OPENAI_ADMIN_KEY",
            providerID: "openai",
            provider: "OpenAI",
            detail: "Removed OpenAI admin key from Keychain",
            unavailableDetail: "OpenAI live usage requires OPENAI_ADMIN_KEY in Keychain or the app environment."
        )
    }

    func storeAnthropicAdminKey(_ key: String) async throws {
        try await storeCredential(key, keyName: "ANTHROPIC_ADMIN_KEY", provider: "Anthropic", detail: "Stored Anthropic Admin API key in Keychain")
    }

    func clearAnthropicAdminKey() async throws {
        try await clearCredential(
            keyName: "ANTHROPIC_ADMIN_KEY",
            providerID: "anthropic",
            provider: "Anthropic",
            detail: "Removed Anthropic Admin API key from Keychain",
            unavailableDetail: "Anthropic live usage requires ANTHROPIC_ADMIN_KEY in Keychain or the app environment. Use an Admin API key that starts with sk-ant-admin."
        )
    }

    func storeOpenRouterAPIKey(_ key: String) async throws {
        try await storeCredential(key, keyName: "OPENROUTER_API_KEY", provider: "OpenRouter", detail: "Stored OpenRouter API key in Keychain")
    }

    func clearOpenRouterAPIKey() async throws {
        try await clearCredential(
            keyName: "OPENROUTER_API_KEY",
            providerID: "openrouter",
            provider: "OpenRouter",
            detail: "Removed OpenRouter API key from Keychain",
            unavailableDetail: "OpenRouter live credits require OPENROUTER_API_KEY in Keychain or the app environment."
        )
    }

    func storeMiniMaxAPIKey(_ key: String) async throws {
        try await storeCredential(key, keyName: "MINIMAX_API_KEY", provider: "MiniMax", detail: "Stored MiniMax API key in Keychain")
    }

    func clearMiniMaxAPIKey() async throws {
        try await clearCredential(
            keyName: "MINIMAX_API_KEY",
            providerID: "minimax",
            provider: "MiniMax",
            detail: "Removed MiniMax API key from Keychain",
            unavailableDetail: "MiniMax Token Plan quota requires MINIMAX_API_KEY in Keychain or the app environment."
        )
    }

    private func storeCredential(_ value: String, keyName: String, provider: String, detail: String) async throws {
        try await KeychainService.shared.store(value: value, for: keyName)
        addAudit(provider: provider, action: "key.store", detail: detail)
        refreshAll()
    }

    private func clearCredential(
        keyName: String,
        providerID: String,
        provider: String,
        detail: String,
        unavailableDetail: String
    ) async throws {
        try await KeychainService.shared.delete(key: keyName)
        addAudit(provider: provider, action: "key.delete", detail: detail)
        if let index = providers.firstIndex(where: { $0.id == providerID }) {
            providers[index].markSource(.liveUnavailable, detail: unavailableDetail, clearUsage: true)
        }
        persistProviders()
        notifyStatusBarUpdate()
    }
}
