import Foundation

struct ProviderUsageStore {
    private let document: JSONDocumentStore<[ProviderUsage]>

    init(
        fileManager: FileManager = .default,
        directoryURL: URL? = nil
    ) {
        document = JSONDocumentStore(
            fileName: "providers.json",
            fileManager: fileManager,
            directoryURL: directoryURL
        )
    }

    func load(defaults: [ProviderUsage]) -> [ProviderUsage] {
        let normalizedDefaults = Self.normalized(defaults)
        let providers: [ProviderUsage]
        switch document.load() {
        case .missing:
            return normalizedDefaults
        case .unreadable:
            save(normalizedDefaults)
            return Self.normalized(defaults)
        case .loaded(let saved):
            providers = saved
        }
        var changed = false
        var merged = Self.normalized(providers.filter { provider in
            let keep = Self.legacyDemoProviderIDs.contains(provider.id) == false
            if keep == false { changed = true }
            return keep
        })
        for defaultProvider in normalizedDefaults where merged.contains(where: { $0.id == defaultProvider.id }) == false {
            merged.append(defaultProvider)
            changed = true
        }
        if changed {
            save(merged)
        }
        return merged
    }

    func save(_ providers: [ProviderUsage]) {
        try? document.save(providers)
    }

    private static func normalized(_ providers: [ProviderUsage]) -> [ProviderUsage] {
        providers.map { provider in
            var normalized = provider
            if normalized.sourceKind == .localAgent, normalized.localAgentUsage == nil {
                normalized.localAgentUsage = LocalAgentUsageSummary(
                    tokensToday: normalized.tokensToday ?? 0,
                    requestCountToday: normalized.requestCountToday ?? 0,
                    requestCountMonth: normalized.requestCountMonth ?? 0,
                    spendToday: normalized.spendToday,
                    spendMonth: normalized.spendMonth,
                    lastUpdated: normalized.lastUpdated,
                    sourceDetail: normalized.sourceDescription
                )
            }
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

    private static let legacyDemoProviderIDs: Set<String> = ["cursor", "github", "stripe"]
}
