import Foundation

enum AppSeedData {
    static func providers() -> [ProviderUsage] {
        [
            provider(
                id: "openai",
                name: "OpenAI",
                category: "AI & API",
                symbol: "brain.head.profile",
                current: 0,
                limit: 0,
                unit: "tokens",
                spendToday: 0,
                spendMonth: 0,
                resetHours: 24 * 30,
                dataSource: .liveUnavailable,
                sourceDetail: "OpenAI live usage requires OPENAI_ADMIN_KEY in Keychain or the app environment."
            ),
            provider(
                id: "anthropic",
                name: "Anthropic",
                category: "AI & API",
                symbol: "sparkles",
                current: 0,
                limit: 0,
                unit: "tokens",
                spendToday: 0,
                spendMonth: 0,
                resetHours: 24 * 30,
                dataSource: .liveUnavailable,
                sourceDetail: "Anthropic live usage requires ANTHROPIC_ADMIN_KEY in Keychain or the app environment. Use an Admin API key that starts with sk-ant-admin."
            ),
            provider(
                id: "openrouter",
                name: "OpenRouter",
                category: "AI & API",
                symbol: "point.3.connected.trianglepath.dotted",
                current: 0,
                limit: 0,
                unit: "credits",
                spendToday: 0,
                spendMonth: 0,
                resetHours: 24 * 30,
                dataSource: .liveUnavailable,
                sourceDetail: "OpenRouter live credits require OPENROUTER_API_KEY in Keychain or the app environment."
            ),
            provider(
                id: "codex",
                name: "Codex",
                category: "AI Tool",
                symbol: "terminal.fill",
                current: 0,
                limit: 100,
                unit: "percent",
                spendToday: 0,
                spendMonth: 0,
                resetHours: 5,
                dataSource: .liveUnavailable,
                sourceDetail: "Codex login quota requires ~/.codex/auth.json from a signed-in Codex session."
            ),
            provider(
                id: "minimax",
                name: "MiniMax",
                category: "AI & API",
                symbol: "bolt.horizontal.circle.fill",
                current: 0,
                limit: 0,
                unit: "percent",
                spendToday: 0,
                spendMonth: 0,
                resetHours: 24 * 30,
                dataSource: .liveUnavailable,
                sourceDetail: "MiniMax Token Plan quota requires MINIMAX_API_KEY in Keychain or the app environment."
            ),
            provider(
                id: "deepseek",
                name: "DeepSeek",
                category: "AI & API",
                symbol: "scope",
                current: 0,
                limit: 0,
                unit: "tokens",
                spendToday: 0,
                spendMonth: 0,
                resetHours: 24 * 30,
                dataSource: .liveUnavailable,
                sourceDetail: "DeepSeek balance can be read from CC Switch config when present; TokenBar does not persist keys imported from CC Switch."
            ),
            provider(
                id: "xiaomi-mimo",
                name: "Xiaomi MiMo",
                category: "AI & API",
                symbol: "waveform.path.ecg",
                current: 0,
                limit: 0,
                unit: "tokens",
                spendToday: 0,
                spendMonth: 0,
                resetHours: 24 * 30,
                dataSource: .unsupported,
                sourceDetail: "Xiaomi MiMo usage is available from CC Switch local proxy rollups when present."
            )
        ]
    }

    static func workspacePolicies(inference: WorkspacePolicyInference? = nil) -> [WorkspacePolicy] {
        let inferred = inference ?? WorkspacePolicyInference(
            allowedProviderIDs: ["openai", "anthropic", "openrouter"],
            preferredProviderID: "openai",
            preferredModel: "gpt-5",
            maxEstimatedRunCost: 1.50,
            setupSourceDetail: "Default local policy. No Codex, Claude, or CC Switch model configuration was found yet.",
            configuredModelCount: 0,
            inferredFromPaths: []
        )
        return [
            WorkspacePolicy(
                id: "local-workspace",
                name: "Local Workspace",
                pathHint: "~",
                client: "local",
                dailyBudget: 0,
                monthlyBudget: 0,
                spendToday: 0,
                spendMonth: 0,
                allowedProviderIDs: inferred.allowedProviderIDs,
                blockedModels: [],
                maxEstimatedRunCost: inferred.maxEstimatedRunCost,
                requireCompanyKey: false,
                preferredProviderID: inferred.preferredProviderID,
                preferredModel: inferred.preferredModel,
                setupSourceDetail: inferred.setupSourceDetail,
                configuredModelCount: inferred.configuredModelCount,
                inferredFromPaths: inferred.inferredFromPaths
            )
        ]
    }

    static func auditEvents() -> [AuditEvent] {
        []
    }

    static func provider(
        id: String,
        name: String,
        category: String,
        symbol: String,
        current: Double,
        limit: Double,
        unit: String,
        spendToday: Double,
        spendMonth: Double,
        resetHours: Double,
        dataSource: UsageDataSource = .unsupported,
        sourceDetail: String? = nil
    ) -> ProviderUsage {
        let now = Date()
        let history = [UsagePoint(timestamp: now, value: current)]
        return ProviderUsage(
            id: id,
            name: name,
            category: category,
            symbolName: symbol,
            current: current,
            limit: limit,
            unit: unit,
            spendToday: spendToday,
            spendMonth: spendMonth,
            resetAt: now.addingTimeInterval(resetHours * 3600),
            lastUpdated: now,
            history: history,
            dataSource: dataSource,
            sourceDetail: sourceDetail ?? "TokenBar does not have a live adapter for this provider yet.",
            sourceUpdatedAt: now,
            requestCountKnown: false,
            spendTodayKnown: dataSource == .live,
            spendMonthKnown: dataSource == .live
        )
    }
}
