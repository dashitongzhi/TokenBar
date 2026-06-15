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
            provider(id: "cursor", name: "Cursor", category: "AI Tool", symbol: "cursorarrow.motionlines", current: 0, limit: 100, unit: "requests", spendToday: 0, spendMonth: 0, resetHours: 24 * 30),
            provider(id: "github", name: "GitHub Copilot", category: "Developer Tool", symbol: "chevron.left.forwardslash.chevron.right", current: 0, limit: 100, unit: "requests", spendToday: 0, spendMonth: 0, resetHours: 24 * 30),
            provider(id: "stripe", name: "Stripe", category: "Payments", symbol: "creditcard.fill", current: 0, limit: 5_000, unit: "events", spendToday: 0, spendMonth: 0, resetHours: 24 * 30)
        ]
    }

    static func workspacePolicies() -> [WorkspacePolicy] {
        [
            WorkspacePolicy(
                id: "client-app",
                name: "Client App",
                pathHint: "~/project/client-app",
                client: "Acme",
                dailyBudget: 6,
                monthlyBudget: 180,
                spendToday: 4.7,
                spendMonth: 96.2,
                allowedProviderIDs: ["anthropic", "openrouter", "github"],
                blockedModels: ["opus"],
                maxEstimatedRunCost: 1.5,
                requireCompanyKey: true
            ),
            WorkspacePolicy(
                id: "personal-lab",
                name: "Personal Lab",
                pathHint: "~/project/lab",
                client: "Personal",
                dailyBudget: 3,
                monthlyBudget: 60,
                spendToday: 0.8,
                spendMonth: 18.4,
                allowedProviderIDs: ["openai", "openrouter", "deepseek", "cursor"],
                blockedModels: [],
                maxEstimatedRunCost: 0.75,
                requireCompanyKey: false
            ),
            WorkspacePolicy(
                id: "production-fix",
                name: "Production Fix",
                pathHint: "~/work/prod",
                client: "Ops",
                dailyBudget: 12,
                monthlyBudget: 300,
                spendToday: 2.1,
                spendMonth: 144.9,
                allowedProviderIDs: ["anthropic", "openai", "github"],
                blockedModels: [],
                maxEstimatedRunCost: 3,
                requireCompanyKey: true
            )
        ]
    }

    static func auditEvents() -> [AuditEvent] {
        [
            AuditEvent(timestamp: .now.addingTimeInterval(-420), provider: "OpenAI", action: "usage.needs_key", detail: "Live usage starts after OPENAI_ADMIN_KEY is available"),
            AuditEvent(timestamp: .now.addingTimeInterval(-720), provider: "Anthropic", action: "usage.needs_key", detail: "Live usage starts after ANTHROPIC_ADMIN_KEY is available"),
            AuditEvent(timestamp: .now.addingTimeInterval(-900), provider: "Providers", action: "usage.unsupported", detail: "Providers without live adapters stay visible but are marked unsupported"),
            AuditEvent(timestamp: .now.addingTimeInterval(-1400), provider: "Keychain", action: "key.lookup", detail: "Keychain stores credential handles locally")
        ]
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
            requestCountKnown: false
        )
    }
}
