import Foundation

struct ProviderRefreshAudit: Equatable {
    var provider: String
    var action: String
    var detail: String
}

struct ProviderRefreshOutcome {
    var providers: [ProviderUsage]
    var audits: [ProviderRefreshAudit]
}

struct ProviderRefreshResults {
    var openAI: OpenAIUsageRefreshResult
    var anthropic: AnthropicUsageRefreshResult
    var openRouter: OpenRouterCreditsRefreshResult
    var codex: CodexUsageRefreshResult
    var miniMax: MiniMaxUsageRefreshResult
    var ccSwitch: CCSwitchUsageRefreshResult
}

@MainActor
struct ProviderRefreshModule {
    private let openAI = OpenAIUsageService()
    private let anthropic = AnthropicUsageService()
    private let openRouter = OpenRouterCreditsService()
    private let codex = CodexUsageService()
    private let miniMax = MiniMaxUsageService()
    private let ccSwitch = CCSwitchUsageService()

    func refresh(providers: [ProviderUsage]) async -> ProviderRefreshOutcome {
        async let openAIResult = openAI.refresh()
        async let anthropicResult = anthropic.refresh()
        async let openRouterResult = openRouter.refresh()
        async let codexResult = codex.refresh()
        async let miniMaxResult = miniMax.refresh()
        async let ccSwitchResult = ccSwitch.refresh()

        return apply(ProviderRefreshResults(
            openAI: await openAIResult,
            anthropic: await anthropicResult,
            openRouter: await openRouterResult,
            codex: await codexResult,
            miniMax: await miniMaxResult,
            ccSwitch: await ccSwitchResult
        ), providers: providers)
    }

    func apply(_ results: ProviderRefreshResults, providers: [ProviderUsage]) -> ProviderRefreshOutcome {
        var state = RefreshState(providers: providers)
        state.applyOpenAI(results.openAI)
        state.applyAnthropic(results.anthropic)
        state.applyOpenRouter(results.openRouter)
        state.applyCodex(results.codex)
        state.applyCCSwitch(results.ccSwitch)
        state.applyMiniMax(results.miniMax)
        return ProviderRefreshOutcome(providers: state.providers, audits: state.audits)
    }
}

private struct RefreshState {
    var providers: [ProviderUsage]
    var audits: [ProviderRefreshAudit] = []

    mutating func applyOpenAI(_ result: OpenAIUsageRefreshResult) {
        let index = ensureSeededProvider("openai")
        switch result {
        case .success(let snapshot):
            providers[index].apply(snapshot: snapshot)
            audit("OpenAI", "usage.live", "Fetched \(Int(snapshot.tokenTotal)) tokens, \(snapshot.requestCountMonth) requests, and \(snapshot.currency.uppercased()) \(money(snapshot.spendMonth)) month-to-date")
        case .unavailable(let detail):
            providers[index].markSource(.liveUnavailable, detail: detail, clearUsage: true)
            audit("OpenAI", "usage.needs_key", "Live usage refresh skipped because no admin key is available")
        case .failure(let detail):
            providers[index].markSource(.error, detail: detail)
            audit("OpenAI", "usage.error", detail)
        }
    }

    mutating func applyAnthropic(_ result: AnthropicUsageRefreshResult) {
        let index = ensureSeededProvider("anthropic")
        switch result {
        case .success(let snapshot):
            providers[index].apply(snapshot: snapshot)
            audit("Anthropic", "usage.live", "Fetched \(Int(snapshot.tokenTotal)) tokens and \(snapshot.currency.uppercased()) \(money(snapshot.spendMonth)) month-to-date")
        case .unavailable(let detail):
            providers[index].markSource(.liveUnavailable, detail: detail, clearUsage: true)
            audit("Anthropic", "usage.needs_key", "Live usage refresh skipped because no Anthropic Admin API key is available")
        case .failure(let detail):
            providers[index].markSource(.error, detail: detail)
            audit("Anthropic", "usage.error", detail)
        }
    }

    mutating func applyOpenRouter(_ result: OpenRouterCreditsRefreshResult) {
        let index = ensureSeededProvider("openrouter")
        switch result {
        case .success(let snapshot):
            providers[index].apply(snapshot: snapshot)
            audit("OpenRouter", "credits.live", "Fetched \(money(snapshot.totalUsage)) used of \(money(snapshot.totalCredits)) credits")
        case .unavailable(let detail):
            providers[index].markSource(.liveUnavailable, detail: detail, clearUsage: true)
            audit("OpenRouter", "credits.needs_key", "Live credits refresh skipped because no OpenRouter API key is available")
        case .failure(let detail):
            providers[index].markSource(.error, detail: detail)
            audit("OpenRouter", "credits.error", detail)
        }
    }

    mutating func applyCodex(_ result: CodexUsageRefreshResult) {
        let index = ensureSeededProvider("codex")
        switch result {
        case .success(let snapshot):
            providers[index].apply(snapshot: snapshot)
            let primary = quotaWindowLabel(seconds: snapshot.primaryWindowSeconds, fallback: "5-hour")
            let secondary = snapshot.secondaryUsedPercent.map {
                ", \(quotaWindowLabel(seconds: snapshot.secondaryWindowSeconds, fallback: "7-day")) \(Int($0))%"
            } ?? ""
            audit("Codex", "quota.live", "Fetched Codex quota: \(primary) \(Int(snapshot.primaryUsedPercent))%\(secondary)")
        case .unavailable(let detail):
            if providers[index].sourceKind != .localAgent {
                providers[index].markSource(.liveUnavailable, detail: detail, clearUsage: true)
            }
            audit("Codex", "quota.needs_auth", "Codex quota refresh skipped because no local Codex auth is available")
        case .failure(let detail):
            providers[index].markSource(.error, detail: detail)
            audit("Codex", "quota.error", detail)
        }
    }

    mutating func applyCCSwitch(_ result: CCSwitchUsageRefreshResult) {
        switch result {
        case .success(let snapshot):
            for providerSnapshot in snapshot.providers {
                let index = ensureProvider(for: providerSnapshot)
                providers[index].name = providerSnapshot.displayName
                providers[index].category = providerSnapshot.category
                providers[index].symbolName = providerSnapshot.symbolName
                providers[index].apply(snapshot: providerSnapshot)
            }
            audit("CC Switch", "usage.local", "Loaded \(snapshot.providers.count) provider rollups from CC Switch")
        case .unavailable(let detail):
            audit("CC Switch", "usage.unavailable", detail)
        case .failure(let detail):
            audit("CC Switch", "usage.error", detail)
        }
    }

    mutating func applyMiniMax(_ result: MiniMaxUsageRefreshResult) {
        let index = ensureSeededProvider("minimax")
        switch result {
        case .success(let snapshot):
            if providers[index].sourceKind != .ccSwitch {
                providers[index].apply(snapshot: snapshot)
            } else {
                providers[index].sourceDetail = "\(providers[index].sourceDescription) MiniMax Token Plan quota also refreshed: current \(snapshot.intervalWindowLabel) \(Int(snapshot.intervalUsedPercent))% used, weekly \(snapshot.weeklyWindowLabel) \(Int(snapshot.weeklyUsedPercent))% used."
                providers[index].sourceUpdatedAt = snapshot.fetchedAt
            }
            audit("MiniMax", "quota.live", "Fetched MiniMax Token Plan quota: current \(Int(snapshot.intervalUsedPercent))%, weekly \(Int(snapshot.weeklyUsedPercent))%")
        case .unavailable(let detail):
            let hasFallback = MiniMaxQuotaAuditSemantics.hasCCSwitchQuotaFallback(
                sourceKindRawValue: providers[index].sourceKind.rawValue,
                unit: providers[index].unit,
                hasKnownQuotaLimit: providers[index].hasKnownQuotaLimit
            )
            let result = MiniMaxQuotaAuditSemantics.unavailableAudit(hasCCSwitchQuotaFallback: hasFallback)
            if hasFallback == false {
                providers[index].markSource(.liveUnavailable, detail: detail, clearUsage: true)
            }
            audit("MiniMax", result.action, result.detail)
        case .failure(let detail):
            if providers[index].sourceKind != .ccSwitch {
                providers[index].markSource(.error, detail: detail)
            }
            audit("MiniMax", "quota.error", detail)
        }
    }

    private mutating func ensureSeededProvider(_ providerID: String) -> Int {
        if let index = providers.firstIndex(where: { $0.id == providerID }) {
            return index
        }
        let seed = AppSeedData.providers().first { $0.id == providerID }
            ?? AppSeedData.provider(
                id: providerID,
                name: providerID,
                category: "AI & API",
                symbol: "network",
                current: 0,
                limit: 0,
                unit: "tokens",
                spendToday: 0,
                spendMonth: 0,
                resetHours: 24 * 30
            )
        let seedOrder = AppSeedData.providers().firstIndex { $0.id == providerID } ?? providers.count
        let insertionIndex = min(seedOrder, providers.count)
        providers.insert(seed, at: insertionIndex)
        return insertionIndex
    }

    private mutating func ensureProvider(for snapshot: CCSwitchProviderUsageSnapshot) -> Int {
        if let index = providers.firstIndex(where: { $0.id == snapshot.providerID }) {
            return index
        }
        providers.append(AppSeedData.provider(
            id: snapshot.providerID,
            name: snapshot.displayName,
            category: snapshot.category,
            symbol: snapshot.symbolName,
            current: 0,
            limit: 0,
            unit: "tokens",
            spendToday: 0,
            spendMonth: 0,
            resetHours: 24 * 30,
            dataSource: .ccSwitch,
            sourceDetail: snapshot.sourceDetail
        ))
        return providers.count - 1
    }

    private mutating func audit(_ provider: String, _ action: String, _ detail: String) {
        audits.append(ProviderRefreshAudit(provider: provider, action: action, detail: detail))
    }

    private func money(_ value: Double) -> String {
        String(format: "%.2f", value)
    }

    private func quotaWindowLabel(seconds: TimeInterval?, fallback: String) -> String {
        guard let seconds, seconds > 0 else { return fallback }
        if seconds >= 86_400 {
            let days = max(Int(round(seconds / 86_400)), 1)
            return days == 1 ? "1-day" : "\(days)-day"
        }
        if seconds >= 3_600 {
            let hours = max(Int(round(seconds / 3_600)), 1)
            return hours == 1 ? "1-hour" : "\(hours)-hour"
        }
        let minutes = max(Int(round(seconds / 60)), 1)
        return minutes == 1 ? "1-minute" : "\(minutes)-minute"
    }
}
