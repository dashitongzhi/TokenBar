import Foundation

struct ProviderUsageStore {
    private let storeURL: URL

    init(fileManager: FileManager = .default) {
        let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? fileManager.temporaryDirectory
        let directory = support.appendingPathComponent("TokenBar", isDirectory: true)
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        storeURL = directory.appendingPathComponent("providers.json")
    }

    func load(defaults: [ProviderUsage]) -> [ProviderUsage] {
        guard let data = try? Data(contentsOf: storeURL),
              let providers = try? JSONDecoder.tokenBar.decode([ProviderUsage].self, from: data) else {
            return Self.normalized(defaults)
        }
        var merged = Self.normalized(providers)
        for defaultProvider in Self.normalized(defaults) where merged.contains(where: { $0.id == defaultProvider.id }) == false {
            merged.append(defaultProvider)
        }
        return merged
    }

    func save(_ providers: [ProviderUsage]) {
        guard let data = try? JSONEncoder.tokenBar.encode(providers) else { return }
        try? data.write(to: storeURL, options: [.atomic])
    }

    private static func normalized(_ providers: [ProviderUsage]) -> [ProviderUsage] {
        providers.map { provider in
            var normalized = provider
            if normalized.id == "openai" {
                normalized.quotaLimitKnown = normalized.dataSource == .live ? false : normalized.quotaLimitKnown ?? false
                if normalized.dataSource != .live && normalized.dataSource != .localAgent && normalized.dataSource != .ccSwitch {
                    let source = normalized.sourceKind == .error ? UsageDataSource.error : UsageDataSource.liveUnavailable
                    let detail = normalized.sourceKind == .error && normalized.sourceDescription.isEmpty == false
                        ? normalized.sourceDescription
                        : "OpenAI live usage requires OPENAI_ADMIN_KEY in Keychain or the app environment."
                    normalized.markSource(source, detail: detail, clearUsage: true)
                }
                if normalized.dataSource == nil {
                    normalized.markSource(
                        .liveUnavailable,
                        detail: "OpenAI live usage requires OPENAI_ADMIN_KEY in Keychain or the app environment.",
                        clearUsage: true
                    )
                }
            } else if normalized.id == "anthropic" {
                normalized.quotaLimitKnown = normalized.dataSource == .live ? false : normalized.quotaLimitKnown ?? false
                if normalized.dataSource != .live && normalized.dataSource != .localAgent && normalized.dataSource != .ccSwitch {
                    let source = normalized.sourceKind == .error ? UsageDataSource.error : UsageDataSource.liveUnavailable
                    let detail = normalized.sourceKind == .error && normalized.sourceDescription.isEmpty == false
                        ? normalized.sourceDescription
                        : "Anthropic live usage requires ANTHROPIC_ADMIN_KEY in Keychain or the app environment. Use an Admin API key that starts with sk-ant-admin."
                    normalized.markSource(source, detail: detail, clearUsage: true)
                }
                if normalized.dataSource == nil {
                    normalized.markSource(
                        .liveUnavailable,
                        detail: "Anthropic live usage requires ANTHROPIC_ADMIN_KEY in Keychain or the app environment. Use an Admin API key that starts with sk-ant-admin.",
                        clearUsage: true
                    )
                }
            } else if normalized.id == "openrouter" {
                if normalized.dataSource != .localAgent && normalized.dataSource != .ccSwitch {
                    normalized.unit = "credits"
                    normalized.requestCountKnown = false
                }
                normalized.spendTodayKnown = normalized.dataSource == .live ? false : normalized.spendTodayKnown ?? false
                normalized.spendMonthKnown = normalized.dataSource == .live ? false : normalized.spendMonthKnown ?? false
                if normalized.dataSource != .live && normalized.dataSource != .localAgent && normalized.dataSource != .ccSwitch {
                    let source = normalized.sourceKind == .error ? UsageDataSource.error : UsageDataSource.liveUnavailable
                    let detail = normalized.sourceKind == .error && normalized.sourceDescription.isEmpty == false
                        ? normalized.sourceDescription
                        : "OpenRouter live credits require OPENROUTER_API_KEY in Keychain or the app environment."
                    normalized.markSource(source, detail: detail, clearUsage: true)
                }
                if normalized.dataSource == nil {
                    normalized.markSource(
                        .liveUnavailable,
                        detail: "OpenRouter live credits require OPENROUTER_API_KEY in Keychain or the app environment.",
                        clearUsage: true
                    )
                }
            } else if normalized.id == "codex" {
                if normalized.dataSource != .localAgent {
                    normalized.unit = "percent"
                    normalized.limit = normalized.limit > 0 ? normalized.limit : 100
                    normalized.quotaLimitKnown = true
                    normalized.requestCountKnown = false
                    normalized.spendTodayKnown = false
                    normalized.spendMonthKnown = false
                }
                if normalized.dataSource != .live && normalized.dataSource != .localAgent {
                    let source = normalized.sourceKind == .error ? UsageDataSource.error : UsageDataSource.liveUnavailable
                    let detail = normalized.sourceKind == .error && normalized.sourceDescription.isEmpty == false
                        ? normalized.sourceDescription
                        : "Codex login quota requires ~/.codex/auth.json from a signed-in Codex session."
                    normalized.markSource(source, detail: detail, clearUsage: true)
                }
                if normalized.dataSource == nil {
                    normalized.markSource(
                        .liveUnavailable,
                        detail: "Codex login quota requires ~/.codex/auth.json from a signed-in Codex session.",
                        clearUsage: true
                    )
                }
            } else if normalized.id == "minimax" {
                if normalized.dataSource != .ccSwitch {
                    normalized.unit = "percent"
                    normalized.limit = normalized.limit > 0 ? normalized.limit : 100
                    normalized.quotaLimitKnown = normalized.dataSource == .live
                    normalized.requestCountKnown = normalized.dataSource == .ccSwitch ? true : false
                    normalized.spendTodayKnown = normalized.dataSource == .ccSwitch
                    normalized.spendMonthKnown = normalized.dataSource == .ccSwitch
                }
                if normalized.dataSource != .live && normalized.dataSource != .ccSwitch && normalized.dataSource != .localAgent {
                    let source = normalized.sourceKind == .error ? UsageDataSource.error : UsageDataSource.liveUnavailable
                    let detail = normalized.sourceKind == .error && normalized.sourceDescription.isEmpty == false
                        ? normalized.sourceDescription
                        : "MiniMax Token Plan quota requires MINIMAX_API_KEY in Keychain or the app environment."
                    normalized.markSource(source, detail: detail, clearUsage: true)
                }
            } else if normalized.id == "deepseek" {
                if normalized.dataSource != .ccSwitch && normalized.dataSource != .localAgent {
                    normalized.markSource(
                        .liveUnavailable,
                        detail: "DeepSeek balance can be read from CC Switch config when present; TokenBar does not persist keys imported from CC Switch.",
                        clearUsage: true
                    )
                }
            } else if normalized.id == "xiaomi-mimo" {
                if normalized.dataSource != .ccSwitch && normalized.dataSource != .localAgent {
                    normalized.markSource(
                        .unsupported,
                        detail: "Xiaomi MiMo usage is available from CC Switch local proxy rollups when present.",
                        clearUsage: normalized.dataSource == nil
                    )
                }
            } else if normalized.dataSource == nil || (normalized.sourceKind != .unsupported && normalized.sourceKind != .localAgent && normalized.sourceKind != .ccSwitch) {
                normalized.markSource(
                    .unsupported,
                    detail: "TokenBar does not have a live adapter for this provider yet.",
                    clearUsage: normalized.dataSource == nil
                )
            }
            return normalized
        }
    }
}
