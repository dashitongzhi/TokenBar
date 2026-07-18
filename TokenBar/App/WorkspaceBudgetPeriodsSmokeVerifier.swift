#if DEBUG
import Foundation

enum WorkspaceBudgetPeriodsSmokeVerifier {
    static func verify() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        let now = try smokeDate(year: 2026, month: 7, day: 12, calendar: calendar)

        let legacyPolicyJSON = """
        {
          "id": "legacy-budget-smoke",
          "name": "Legacy Budget Smoke",
          "pathHint": "~",
          "client": "local",
          "dailyBudget": 10,
          "monthlyBudget": 100,
          "spendToday": 7,
          "spendMonth": 42,
          "allowedProviderIDs": ["openai"],
          "blockedModels": [],
          "maxEstimatedRunCost": 2,
          "requireCompanyKey": false
        }
        """
        guard var legacyPolicy = try? JSONDecoder.tokenBar.decode(
            WorkspacePolicy.self,
            from: Data(legacyPolicyJSON.utf8)
        ) else {
            throw WorkspaceBudgetPeriodsSmokeFailure("Legacy workspace policy JSON no longer decodes.")
        }
        guard legacyPolicy.maxEstimatedTokens == 0,
              legacyPolicy.resetExpiredSpendBuckets(now: now, calendar: calendar),
              legacyPolicy.spendToday == 7,
              legacyPolicy.spendMonth == 42,
              legacyPolicy.spendDayKey == "2026-07-12",
              legacyPolicy.spendMonthKey == "2026-07" else {
            throw WorkspaceBudgetPeriodsSmokeFailure("Legacy workspace spend was not preserved while initializing budget buckets.")
        }

        var workspace = WorkspacePolicy(
            id: "budget-smoke",
            name: "Budget Smoke",
            pathHint: "~",
            client: "local",
            dailyBudget: 10,
            monthlyBudget: 20,
            spendToday: 7,
            spendMonth: 19,
            spendDayKey: "2026-07-11",
            spendMonthKey: "2026-06",
            allowedProviderIDs: ["openai"],
            blockedModels: [],
            maxEstimatedRunCost: 0,
            requireCompanyKey: false
        )
        guard workspace.resetExpiredSpendBuckets(now: now, calendar: calendar),
              workspace.spendToday == 0,
              workspace.spendMonth == 0,
              workspace.spendDayKey == "2026-07-12",
              workspace.spendMonthKey == "2026-07" else {
            throw WorkspaceBudgetPeriodsSmokeFailure("Expired daily and monthly workspace spend was not reset.")
        }

        workspace.spendToday = 1
        workspace.spendMonth = 19
        let decision = PolicyEngine.evaluate(
            input: PolicyEvaluationInput(
                agent: .codex,
                workspaceID: workspace.id,
                providerID: "openai",
                model: "gpt-5",
                estimatedCost: 2,
                estimatedTokens: 0,
                intent: "budget-smoke"
            ),
            workspaces: [workspace],
            selectedWorkspace: workspace,
            providers: [],
            projectedSessionSpend: 2,
            sessionBudget: 10
        )
        guard decision.status == .block, decision.projectedMonthlySpend == 21 else {
            throw WorkspaceBudgetPeriodsSmokeFailure("Monthly workspace budget was not enforced.")
        }

        let alreadyAppliedDecision = PolicyEngine.evaluate(
            input: PolicyEvaluationInput(
                agent: .codex,
                workspaceID: workspace.id,
                providerID: "openai",
                model: "gpt-5",
                estimatedCost: 0,
                estimatedTokens: 0,
                intent: "usage-ingest-smoke"
            ),
            workspaces: [workspace],
            selectedWorkspace: workspace,
            providers: [],
            projectedSessionSpend: 2,
            sessionBudget: 10
        )
        guard alreadyAppliedDecision.projectedDailySpend == 1,
              alreadyAppliedDecision.projectedMonthlySpend == 19 else {
            throw WorkspaceBudgetPeriodsSmokeFailure("Applied local usage was counted again during policy evaluation.")
        }

        workspace.maxEstimatedTokens = 100
        let tokenCapDecision = PolicyEngine.evaluate(
            input: PolicyEvaluationInput(
                agent: .codex,
                workspaceID: workspace.id,
                providerID: "openai",
                model: "gpt-5",
                estimatedCost: 0,
                estimatedTokens: 101,
                intent: "token-cap-smoke"
            ),
            workspaces: [workspace],
            selectedWorkspace: workspace,
            providers: [],
            projectedSessionSpend: 0,
            sessionBudget: 0
        )
        guard tokenCapDecision.status == .block,
              tokenCapDecision.reasons.contains("Estimated run tokens are above the workspace token cap.") else {
            throw WorkspaceBudgetPeriodsSmokeFailure("Workspace raw-token cap was not enforced.")
        }

        guard var provider = AppSeedData.providers().first(where: { $0.id == "openai" }) else {
            throw WorkspaceBudgetPeriodsSmokeFailure("Could not construct provider source smoke data.")
        }
        provider.apply(localUsage: LocalAgentUsageAppliedSnapshot(
            agent: .codex,
            providerID: "openai",
            model: "gpt-5",
            workspaceID: workspace.id,
            sessionKey: "provider-source-smoke",
            sourceName: "smoke",
            costDelta: 0.42,
            tokenDelta: 12_000,
            requestDelta: 1,
            contextTokenTotal: 12_000,
            contextWindowSize: 128_000,
            rateLimitUsedPercentage: nil,
            rateLimitResetAt: nil,
            occurredAt: now,
            sourceDetail: "smoke local usage"
        ))
        provider.apply(snapshot: OpenAIUsageSnapshot(
            tokenTotal: 50_000,
            tokenToday: 20_000,
            requestCountMonth: 3,
            requestCountToday: 2,
            spendToday: 1.2,
            spendMonth: 4.8,
            currency: "usd",
            resetAt: now.addingTimeInterval(86_400),
            fetchedAt: now.addingTimeInterval(60),
            history: []
        ))
        guard provider.sourceKind == .live,
              provider.localAgentUsage?.spendToday == 0.42,
              provider.localAgentUsage?.tokensToday == 12_000 else {
            throw WorkspaceBudgetPeriodsSmokeFailure("Live refresh overwrote local agent usage.")
        }
    }

    private static func smokeDate(year: Int, month: Int, day: Int, calendar: Calendar) throws -> Date {
        guard let date = calendar.date(from: DateComponents(year: year, month: month, day: day)) else {
            throw WorkspaceBudgetPeriodsSmokeFailure("Could not construct the budget smoke-test date.")
        }
        return date
    }
}

private struct WorkspaceBudgetPeriodsSmokeFailure: Error, CustomStringConvertible {
    var description: String

    init(_ description: String) {
        self.description = description
    }
}
#endif
