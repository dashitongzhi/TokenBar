import Foundation

struct OpenAIUsageSnapshot {
    var tokenTotal: Double
    var tokenToday: Double
    var requestCountToday: Int
    var requestCountMonth: Int
    var currency: String
    var spendToday: Double
    var spendMonth: Double
    var resetAt: Date
    var fetchedAt: Date
    var history: [UsagePoint]
}

struct AnthropicUsageSnapshot {
    var tokenTotal: Double
    var tokenToday: Double
    var requestCountToday: Int
    var requestCountMonth: Int
    var currency: String
    var spendToday: Double
    var spendMonth: Double
    var resetAt: Date
    var fetchedAt: Date
    var history: [UsagePoint]
}

struct OpenRouterCreditsSnapshot {
    var totalUsage: Double
    var totalCredits: Double
    var fetchedAt: Date
    var history: [UsagePoint]
}

struct CodexUsageSnapshot {
    var primaryUsedPercent: Double
    var primaryResetAt: Date
    var fetchedAt: Date
    var history: [UsagePoint]
    var primaryWindowSeconds: TimeInterval?
    var secondaryUsedPercent: Double?
    var secondaryResetAt: Date?
    var secondaryWindowSeconds: TimeInterval?
    var planType: String?
    var allowed: Bool
    var limitReached: Bool
}

struct CCSwitchProviderUsageSnapshot {
    var quotaWindows: [CCSwitchQuotaWindow]
    var fetchedAt: Date
    var tokenTotalMonth: Double
    var monthResetAt: Date
    var history: [UsagePoint]
    var tokenTotalToday: Double
    var requestCountToday: Int
    var requestCountMonth: Int
    var spendToday: Double
    var spendMonth: Double
    var healthAlerts: [ProviderHealthAlert]
    var sourceDetail: String
}

struct CCSwitchQuotaWindow {
    var modelName: String
    var hasKnownIntervalLimit: Bool
    var hasKnownWeeklyLimit: Bool
    var intervalUsedPercent: Double
    var intervalResetAt: Date
}

struct MiniMaxUsageSnapshot {
    static let tokenPlanURL = "https://example.invalid/minimax-token-plan"

    var intervalUsedPercent: Double
    var intervalResetAt: Date
    var fetchedAt: Date
    var history: [UsagePoint]
    var weeklyResetAt: Date
    var primaryModelName: String
    var intervalWindowLabel: String
    var intervalTotalCount: Double
    var intervalUsedCount: Double
    var intervalRemainingPercent: Double?
    var weeklyWindowLabel: String
    var weeklyUsedPercent: Double
    var weeklyTotalCount: Double
    var weeklyUsedCount: Double
    var weeklyRemainingPercent: Double?
    var modelWindows: [MiniMaxModelWindow]
}

struct MiniMaxModelWindow {
    var modelName: String
}
