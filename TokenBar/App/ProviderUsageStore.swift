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
                if normalized.dataSource != .live {
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
                if normalized.dataSource != .live {
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
                normalized.unit = "credits"
                normalized.requestCountKnown = false
                normalized.spendTodayKnown = normalized.dataSource == .live ? false : normalized.spendTodayKnown ?? false
                normalized.spendMonthKnown = normalized.dataSource == .live ? false : normalized.spendMonthKnown ?? false
                if normalized.dataSource != .live {
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
            } else if normalized.dataSource == nil || normalized.sourceKind != .unsupported {
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
