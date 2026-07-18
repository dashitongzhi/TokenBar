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
@MainActor
private enum VerifyLocalAPIProviderHealthQuotas {
    static func main() throws {
        try verifyScenario(
            provider: provider(
                id: "deepseek",
                name: "DeepSeek",
                healthAlerts: [
                    ProviderHealthAlert(
                        status: .critical,
                        title: "Negative provider balance",
                        detail: "DeepSeek balance is USD -1.20."
                    )
                ]
            ),
            expectedStatus: .critical,
            expectedAlertTitle: "Negative provider balance"
        )

        try verifyScenario(
            provider: provider(
                id: "ccswitch-codex",
                name: "CC Switch Codex",
                healthAlerts: [
                    ProviderHealthAlert(
                        status: .warning,
                        title: "4 consecutive CC Switch failures",
                        detail: "CC Switch Codex has 4 consecutive failed CC Switch route checks."
                    )
                ]
            ),
            expectedStatus: .warning,
            expectedAlertTitle: "4 consecutive CC Switch failures"
        )

        try verifyScenario(
            provider: provider(
                id: "ccswitch-codex",
                name: "CC Switch Codex",
                healthAlerts: [
                    ProviderHealthAlert(
                        status: .critical,
                        title: "10 consecutive CC Switch failures",
                        detail: "CC Switch Codex has 10 consecutive failed CC Switch route checks."
                    )
                ]
            ),
            expectedStatus: .critical,
            expectedAlertTitle: "10 consecutive CC Switch failures"
        )

        try verifyTypedNullContracts()

        print("Verified typed local API wire contracts and provider-health quota statuses.")
    }

    private static func verifyTypedNullContracts() throws {
        let decision = PolicyDecision(
            timestamp: Date(timeIntervalSince1970: 1_700_000_000),
            status: .allow,
            agent: .codex,
            workspaceID: "wire-contract",
            workspaceName: "Wire Contract",
            providerID: "openai",
            model: "gpt-wire",
            estimatedCost: 0.1,
            projectedDailySpend: 0.1,
            projectedMonthlySpend: 0.1,
            reasons: ["fixture"],
            recommendation: "continue",
            fallbackProviderID: nil
        )
        let workspace = WorkspacePolicy(
            id: "wire-contract",
            name: "Wire Contract",
            pathHint: "~",
            client: "local",
            dailyBudget: 0,
            monthlyBudget: 0,
            spendToday: 0,
            spendMonth: 0,
            allowedProviderIDs: ["openai"],
            blockedModels: [],
            maxEstimatedRunCost: 0,
            requireCompanyKey: false
        )
        let policy = try expectDictionary(JSONSerialization.jsonObject(
            with: try LocalAPIPayloadBuilder.policyJSON(currentDecision: decision, workspacePolicies: [workspace])
        ))
        let decisionPayload = try expectDictionary(policy["decision"])
        try expect(decisionPayload["fallbackProvider"] is NSNull, "nil fallback provider must encode as JSON null")
        try expect(decisionPayload["smartRouting"] is NSNull, "nil smart routing recommendation must encode as JSON null")
        let workspaces = try expectArray(policy["workspaces"], "workspaces")
        let workspacePayload = try expectDictionary(workspaces.first)
        try expect(workspacePayload["spendDayKey"] is NSNull, "nil spend day key must encode as JSON null")
        try expect(workspacePayload["preferredModel"] is NSNull, "nil preferred model must encode as JSON null")

        let run = SmartRoutingRunRecord(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
            recordedAt: Date(timeIntervalSince1970: 1_700_000_000),
            occurredAt: Date(timeIntervalSince1970: 1_700_000_000),
            agent: .codex,
            taskIntent: "wire",
            providerID: "openai",
            model: "gpt-wire",
            workspaceID: nil,
            workspaceName: nil,
            workspacePath: nil,
            sessionID: nil,
            taskID: nil,
            estimatedCost: 0,
            actualCost: 0,
            estimatedCostKnown: false,
            actualCostKnown: false,
            estimatedTokens: 0,
            actualTokens: 0,
            estimatedTokensKnown: false,
            actualTokensKnown: false,
            inputTokens: nil,
            outputTokens: nil,
            requestCount: nil,
            signal: .unknown,
            followUpRequired: false,
            selectedBy: nil,
            alternatives: [],
            routingReason: nil,
            metadata: [:]
        )
        let routingDocument = try expectDictionary(JSONSerialization.jsonObject(
            with: try LocalAPIPayloadBuilder.smartRoutingRunJSON(record: run)
        ))
        let routingRun = try expectDictionary(routingDocument["routingRun"])
        try expect(routingRun["estimatedCost"] is NSNull, "unknown estimated cost must encode as JSON null")
        try expect(routingRun["actualTokens"] is NSNull, "unknown actual tokens must encode as JSON null")
    }

    private static func verifyScenario(
        provider: ProviderUsage,
        expectedStatus: UsageStatus,
        expectedAlertTitle: String
    ) throws {
        let data = try LocalAPIPayloadBuilder.mcpSnapshotJSON(
            providers: [provider],
            filteredProviderID: provider.id
        )
        let payload = try expectDictionary(JSONSerialization.jsonObject(with: data))
        let quotas = try expectArray(payload["quotas"], "quotas")
        try expect(quotas.count == 1, "expected one filtered quota entry for \(provider.id)")

        let quota = try expectDictionary(quotas[0])
        try expect(quota["platform"] as? String == provider.id, "quota platform should be \(provider.id)")
        try expect(
            quota["status"] as? String == expectedStatus.rawValue,
            "\(provider.id) status should be \(expectedStatus.rawValue)"
        )

        let alerts = try expectArray(quota["healthAlerts"], "healthAlerts")
        let matchingAlert = try alerts
            .map(expectDictionary)
            .first { $0["title"] as? String == expectedAlertTitle }
        try expect(matchingAlert != nil, "\(provider.id) should include alert \(expectedAlertTitle)")
        try expect(
            matchingAlert?["status"] as? String == expectedStatus.rawValue,
            "\(provider.id) alert status should be \(expectedStatus.rawValue)"
        )
    }

    private static func provider(
        id: String,
        name: String,
        healthAlerts: [ProviderHealthAlert]
    ) -> ProviderUsage {
        ProviderUsage(
            id: id,
            name: name,
            category: "CC Switch",
            symbolName: "network",
            current: 5,
            limit: 100,
            unit: "percent",
            spendToday: 0,
            spendMonth: 0,
            resetAt: Date().addingTimeInterval(3600),
            lastUpdated: Date(),
            history: [],
            dataSource: .ccSwitch,
            sourceDetail: "provider-health regression fixture",
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

    private static func expectDictionary(_ value: Any?) throws -> [String: Any] {
        guard let dictionary = value as? [String: Any] else {
            throw VerificationFailure.message("expected dictionary")
        }
        return dictionary
    }

    private static func expectArray(_ value: Any?, _ name: String) throws -> [Any] {
        guard let array = value as? [Any] else {
            throw VerificationFailure.message("expected \(name) array")
        }
        return array
    }

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        if condition() == false {
            throw VerificationFailure.message(message)
        }
    }
}
