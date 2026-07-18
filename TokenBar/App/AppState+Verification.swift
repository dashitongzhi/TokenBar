import Foundation

#if DEBUG
@MainActor
extension AppState {
    func verifyMiniMaxCCSwitchFallbackAuditSmoke() throws {
        let originalProviders = providers
        let originalAuditEvents = auditEvents
        let wasPersistenceSuppressed = isPersistenceSuppressedForVerification
        isPersistenceSuppressedForVerification = true

        defer {
            isPersistenceSuppressedForVerification = wasPersistenceSuppressed
            providers = originalProviders
            auditEvents = originalAuditEvents
            persistProviders()
            auditEventStore.save(originalAuditEvents)
        }

        let now = Date(timeIntervalSince1970: 1_735_689_600)
        providers = AppSeedData.providers()
        auditEvents = []
        apply(
            openAIResult: .unavailable("smoke: no OpenAI admin key"),
            anthropicResult: .unavailable("smoke: no Anthropic admin key"),
            openRouterResult: .unavailable("smoke: no OpenRouter API key"),
            codexResult: .unavailable("smoke: no Codex auth"),
            miniMaxResult: .unavailable("smoke: no direct MiniMax key"),
            ccSwitchResult: .success(CCSwitchUsageSnapshot(
                providers: [CCSwitchProviderUsageSnapshot(
                    providerID: "minimax",
                    displayName: "MiniMax",
                    category: "CC Switch",
                    symbolName: "bolt.horizontal.circle.fill",
                    tokenTotalToday: 0,
                    tokenTotalMonth: 0,
                    requestCountToday: 0,
                    requestCountMonth: 0,
                    spendToday: 0,
                    spendMonth: 0,
                    dailySpendLimit: nil,
                    monthlySpendLimit: nil,
                    monthResetAt: now.addingTimeInterval(86_400 * 30),
                    quotaWindows: [CCSwitchQuotaWindow(
                        providerID: "minimax",
                        providerDisplayName: "MiniMax",
                        modelName: "MiniMax-M1",
                        intervalUsedCount: 25,
                        intervalTotalCount: 100,
                        intervalUsedPercent: 25,
                        intervalRemainingPercent: nil,
                        intervalStartAt: now,
                        intervalResetAt: now.addingTimeInterval(18_000),
                        weeklyUsedCount: 125,
                        weeklyTotalCount: 1_000,
                        weeklyUsedPercent: 12.5,
                        weeklyRemainingPercent: nil,
                        weeklyStartAt: now,
                        weeklyResetAt: now.addingTimeInterval(604_800)
                    )],
                    history: [],
                    healthAlerts: [],
                    sourceDetail: "smoke: MiniMax quota from CC Switch provider key",
                    fetchedAt: now
                )],
                fetchedAt: now
            ))
        )

        guard let miniMaxProvider = providers.first(where: { $0.id == "minimax" }) else {
            throw MiniMaxCCSwitchFallbackAuditSmokeFailure("MiniMax provider was not present after app refresh apply.")
        }
        guard miniMaxProvider.sourceKind == .ccSwitch, miniMaxProvider.unit == "percent", miniMaxProvider.hasKnownQuotaLimit else {
            throw MiniMaxCCSwitchFallbackAuditSmokeFailure("MiniMax provider did not keep the CC Switch percent quota fallback.")
        }
        let miniMaxAudits = auditEvents.filter { $0.provider == "MiniMax" }
        guard miniMaxAudits.contains(where: { $0.action == "quota.fallback" }) else {
            throw MiniMaxCCSwitchFallbackAuditSmokeFailure("AppState did not record quota.fallback for the MiniMax CC Switch fallback.")
        }
        guard miniMaxAudits.contains(where: { $0.action == "quota.needs_key" }) == false else {
            throw MiniMaxCCSwitchFallbackAuditSmokeFailure("AppState recorded quota.needs_key even though CC Switch had MiniMax percent quota.")
        }
    }

    func verifyWorkspaceBudgetPeriodsSmoke() throws {
        try WorkspaceBudgetPeriodsSmokeVerifier.verify()
    }

    private func apply(
        openAIResult: OpenAIUsageRefreshResult,
        anthropicResult: AnthropicUsageRefreshResult,
        openRouterResult: OpenRouterCreditsRefreshResult,
        codexResult: CodexUsageRefreshResult,
        miniMaxResult: MiniMaxUsageRefreshResult,
        ccSwitchResult: CCSwitchUsageRefreshResult
    ) {
        applyProviderRefreshOutcome(providerRefreshModule.apply(
            ProviderRefreshResults(
                openAI: openAIResult,
                anthropic: anthropicResult,
                openRouter: openRouterResult,
                codex: codexResult,
                miniMax: miniMaxResult,
                ccSwitch: ccSwitchResult
            ),
            providers: providers
        ))
    }
}

private struct MiniMaxCCSwitchFallbackAuditSmokeFailure: Error, CustomStringConvertible {
    var description: String

    init(_ description: String) {
        self.description = description
    }
}
#endif
