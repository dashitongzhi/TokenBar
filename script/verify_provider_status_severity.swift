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

private enum VerificationFailure: Error, CustomStringConvertible {
    case message(String)

    var description: String {
        switch self {
        case .message(let value):
            return value
        }
    }
}

@main
private enum VerifyProviderStatusSeverity {
    static func main() throws {
        let quotaCriticalWithWarningAlert = provider(
            current: 95,
            limit: 100,
            healthAlerts: [
                ProviderHealthAlert(
                    status: .warning,
                    title: "Provider latency elevated",
                    detail: "Health probe is slow, but quota is already critical."
                )
            ]
        )
        try expect(
            quotaCriticalWithWarningAlert.status == .critical,
            "warning health alert must not downgrade critical quota status."
        )

        let quotaHealthyWithCriticalAlert = provider(
            current: 10,
            limit: 100,
            healthAlerts: [
                ProviderHealthAlert(
                    status: .critical,
                    title: "Provider unavailable",
                    detail: "Health probe cannot reach the provider."
                )
            ]
        )
        try expect(
            quotaHealthyWithCriticalAlert.status == .critical,
            "critical health alert should upgrade healthy quota status."
        )

        print("Verified ProviderUsage.status severity aggregation.")
    }

    private static func provider(
        current: Double,
        limit: Double,
        healthAlerts: [ProviderHealthAlert]
    ) -> ProviderUsage {
        ProviderUsage(
            id: "regression-provider",
            name: "Regression Provider",
            category: "Test",
            symbolName: "checkmark.circle",
            current: current,
            limit: limit,
            unit: "percent",
            spendToday: 0,
            spendMonth: 0,
            resetAt: Date().addingTimeInterval(3600),
            lastUpdated: Date(),
            history: [],
            dataSource: .ccSwitch,
            sourceDetail: "regression fixture",
            sourceUpdatedAt: Date(),
            tokensToday: nil,
            requestCountToday: nil,
            requestCountMonth: nil,
            currencyCode: nil,
            quotaLimitKnown: true,
            requestCountKnown: false,
            spendTodayKnown: false,
            spendMonthKnown: false,
            healthAlerts: healthAlerts
        )
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        if condition() == false {
            throw VerificationFailure.message(message)
        }
    }
}
