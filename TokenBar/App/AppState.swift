import Foundation
import Combine
import AppKit

@MainActor
final class AppState: ObservableObject {
    static let shared = AppState()

    @Published var language: AppLanguage {
        didSet { savePreferencesAndNotify() }
    }

    @Published var statusBarContent: StatusBarContent {
        didSet { savePreferencesAndNotify() }
    }

    @Published var routingMode: RoutingMode {
        didSet {
            rebuildPolicyInput()
            savePreferencesAndNotify()
        }
    }

    @Published var selectedProviderID: String {
        didSet {
            markExplicitSelection(\.hasExplicitSelectedProviderPreference)
            rebuildPolicyInput()
            savePreferencesAndNotify()
        }
    }

    @Published var selectedMainSection: MainSection {
        didSet { savePreferencesAndNotify() }
    }

    @Published var selectedWorkspaceID: String {
        didSet {
            markExplicitSelection(\.hasExplicitSelectedWorkspacePreference)
            rebuildPolicyInput()
            savePreferencesAndNotify()
        }
    }

    @Published var selectedAgent: AgentProvider {
        didSet {
            markExplicitSelection(\.hasExplicitSelectedAgentPreference)
            rebuildPolicyInput()
            savePreferencesAndNotify()
        }
    }

    @Published var selectedModel: String {
        didSet {
            markExplicitSelection(\.hasExplicitSelectedModelPreference)
            rebuildPolicyInput()
            savePreferencesAndNotify()
        }
    }

    @Published var estimatedRunCost: Double {
        didSet {
            rebuildPolicyInput()
            savePreferencesAndNotify()
        }
    }

    @Published var estimatedTokens: Double {
        didSet {
            rebuildPolicyInput()
            savePreferencesAndNotify()
        }
    }

    @Published var customStatusText: String {
        didSet { savePreferencesAndNotify() }
    }

    @Published var sessionBudget: Double {
        didSet { savePreferencesAndNotify() }
    }

    @Published var sessionSpend: Double {
        didSet { savePreferencesAndNotify() }
    }

    @Published var focusModeEnabled: Bool {
        didSet { savePreferencesAndNotify() }
    }

    @Published var localAPIEnabled: Bool {
        didSet {
            savePreferencesAndNotify()
            LocalAPIServer.shared.syncWithPreference()
        }
    }

    @Published var selectedAppIcon: AppIconChoice {
        didSet {
            savePreferencesAndNotify()
            applySelectedAppIcon()
        }
    }

    @Published private(set) var providers: [ProviderUsage] = []
    @Published private(set) var apiMonitors: [APIMonitorSpec] = APIMonitorCatalog.all
    @Published private(set) var workspacePolicies: [WorkspacePolicy] = []
    @Published private(set) var currentPolicyInput = PolicyEvaluationInput(
        agent: .codex,
        workspaceID: "local-workspace",
        providerID: "openai",
        model: "unspecified",
        estimatedCost: 0,
        estimatedTokens: 0,
        intent: "code"
    )
    @Published private(set) var currentDecision = PolicyDecision(
        timestamp: .now,
        status: .allow,
        agent: .codex,
        workspaceID: "local-workspace",
        workspaceName: "Local Workspace",
        providerID: "openai",
        model: "unspecified",
        estimatedCost: 0,
        projectedDailySpend: 0,
        reasons: ["Workspace, provider, model, and budget are inside policy."],
        recommendation: "Select a model before running an agent.",
        fallbackProviderID: "anthropic"
    )
    @Published private(set) var recentDecisions: [PolicyDecision] = []
    @Published private(set) var auditEvents: [AuditEvent] = []
    @Published private(set) var modelUsageRollups: [ModelUsageRollup] = []
    @Published private(set) var modelCatalogItems: [ModelCatalogItem] = []
    @Published private(set) var lastRefresh: Date = .now
    @Published private(set) var isRefreshingUsage = false
    @Published private(set) var isRefreshingModelCatalog = false
    @Published private(set) var modelCatalogMessage = ""
    @Published private(set) var localAPIStatus: LocalAPIStatus = .stopped

    private let preferencesStore = AppPreferencesStore()
    private let providerStore = ProviderUsageStore()
    private let workspacePolicyStore = WorkspacePolicyStore()
    private let auditEventStore = AuditEventStore()
    private let localAgentUsageLedgerStore = LocalAgentUsageLedgerStore()
    private let smartRoutingLedgerStore = SmartRoutingLedgerStore()
    private let localModelUsageStore = LocalModelUsageStore()
    private let agentModelConfigurationService = AgentModelConfigurationService()
    private let providerModelCatalogService = ProviderModelCatalogService()
    private let openAIUsageService = OpenAIUsageService()
    private let anthropicUsageService = AnthropicUsageService()
    private let openRouterCreditsService = OpenRouterCreditsService()
    private let codexUsageService = CodexUsageService()
    private let miniMaxUsageService = MiniMaxUsageService()
    private let ccSwitchUsageService = CCSwitchUsageService()
    private var hasExplicitSelectedProviderPreference = false
    private var hasExplicitSelectedWorkspacePreference = false
    private var hasExplicitSelectedAgentPreference = false
    private var hasExplicitSelectedModelPreference = false
    private var isApplyingInferredSelections = false

    private init() {
        let savedPreferences = preferencesStore.load()
        hasExplicitSelectedProviderPreference = savedPreferences.hasSelectedProviderPreference
        hasExplicitSelectedWorkspacePreference = savedPreferences.hasSelectedWorkspacePreference
        hasExplicitSelectedAgentPreference = savedPreferences.hasSelectedAgentPreference
        hasExplicitSelectedModelPreference = savedPreferences.hasSelectedModelPreference
        language = savedPreferences.language
        statusBarContent = savedPreferences.statusBarContent
        routingMode = savedPreferences.routingMode
        selectedMainSection = savedPreferences.selectedMainSection
        selectedProviderID = savedPreferences.selectedProviderID
        selectedWorkspaceID = savedPreferences.selectedWorkspaceID
        selectedAgent = savedPreferences.selectedAgent
        selectedModel = savedPreferences.selectedModel
        estimatedRunCost = savedPreferences.estimatedRunCost
        estimatedTokens = savedPreferences.estimatedTokens
        customStatusText = savedPreferences.customStatusText
        sessionBudget = savedPreferences.sessionBudget
        sessionSpend = savedPreferences.sessionSpend
        focusModeEnabled = savedPreferences.focusModeEnabled
        localAPIEnabled = savedPreferences.localAPIEnabled
        selectedAppIcon = savedPreferences.selectedAppIcon

        let configuredModelRows = agentModelConfigurationService.readConfiguredModels()
        let configuredCatalogItems = agentModelConfigurationService.readConfiguredModelCatalogItems()
            + ccSwitchUsageService.configuredModelCatalogItems()
        let inferredPolicy = AgentModelConfigurationService.inferWorkspacePolicy(
            configuredRows: configuredModelRows,
            catalogItems: configuredCatalogItems,
            fallbackPath: UserHomeDirectory.url.path
        )

        providers = providerStore.load(defaults: AppSeedData.providers())
        workspacePolicies = workspacePolicyStore.load(defaults: AppSeedData.workspacePolicies(inference: inferredPolicy))
        auditEvents = auditEventStore.load(defaults: AppSeedData.auditEvents())
        normalizeSelectionsAfterLoad()
        mergeModelUsageRollups(localModelUsageStore.load())
        mergeModelCatalogItems(configuredCatalogItems, replacingProviderID: nil)
        rebuildPolicyInput()
        currentDecision = evaluatePolicy(input: currentPolicyInput, shouldRecord: false)
        recentDecisions = [currentDecision]
        applySelectedAppIcon()
    }

    var selectedProvider: ProviderUsage? {
        providers.first { $0.id == selectedProviderID } ?? providers.first
    }

    var selectedWorkspace: WorkspacePolicy? {
        workspacePolicies.first { $0.id == selectedWorkspaceID } ?? workspacePolicies.first
    }

    var policyStatus: UsageStatus {
        currentDecision.status.usageStatus
    }

    var projectedSessionSpend: Double {
        guard sessionBudget > 0 else { return 0 }
        return sessionSpend + estimatedRunCost
    }

    var allowedProviderNames: String {
        guard let workspace = selectedWorkspace else { return "" }
        let names = workspace.allowedProviderIDs.compactMap { id in providers.first { $0.id == id }?.name }
        return names.joined(separator: ", ")
    }

    var totalSpendMonth: Double {
        providers.reduce(0) { $0 + ($1.hasKnownSpendMonth ? $1.spendMonth : 0) }
    }

    var totalSpendToday: Double {
        providers.reduce(0) { $0 + ($1.hasKnownSpendToday ? $1.spendToday : 0) }
    }

    var liveProviderCount: Int {
        providers.filter(\.isUsageConnected).count
    }

    var unsupportedProviderCount: Int {
        providers.filter { $0.sourceKind == .unsupported || $0.sourceKind == .liveUnavailable || $0.sourceKind == .error }.count
    }

    var mostUrgentProvider: ProviderUsage? {
        providers.sorted {
            if $0.status != $1.status {
                return statusRank($0.status) > statusRank($1.status)
            }
            return $0.usageRatio > $1.usageRatio
        }.first
    }

    var budgetRatio: Double {
        guard sessionBudget > 0 else { return 0 }
        return min(sessionSpend / sessionBudget, 1.5)
    }

    var visibleModelUsageRollups: [ModelUsageRollup] {
        modelUsageRollups.sorted { lhs, rhs in
            if lhs.hasUsage != rhs.hasUsage { return lhs.hasUsage }
            if lhs.spendToday != rhs.spendToday { return lhs.spendToday > rhs.spendToday }
            if lhs.tokensToday != rhs.tokensToday { return lhs.tokensToday > rhs.tokensToday }
            return lhs.lastUpdated > rhs.lastUpdated
        }
    }

    var selectedProviderModelCatalog: [ModelCatalogItem] {
        modelCatalog(for: selectedProviderID)
    }

    var budgetStatus: UsageStatus {
        if budgetRatio >= 1 { return .critical }
        if budgetRatio >= 0.8 { return .warning }
        return .healthy
    }

    var dailySummary: UsageSummary {
        usageSummary(id: "daily", title: localized("daily"), multiplier: 1, requestDivisor: 1)
    }

    var weeklySummary: UsageSummary {
        usageSummary(id: "weekly", title: localized("weekly"), multiplier: 7, requestDivisor: 4)
    }

    var monthlySummary: UsageSummary {
        UsageSummary(
            id: "monthly",
            title: localized("monthly"),
            spend: totalSpendMonth,
            tokens: providers.reduce(0) { $0 + $1.current },
            requests: providers.reduce(0) { $0 + ($1.knownRequestCount ?? 0) },
            projectedSpend: totalSpendToday * 30
        )
    }

    var summaries: [UsageSummary] {
        [dailySummary, weeklySummary, monthlySummary]
    }

    var automaticMonitorCount: Int {
        apiMonitors.filter { $0.capability == .automatic }.count
    }

    var warningMonitorCount: Int {
        apiMonitors.filter { $0.capability != .automatic }.count
    }

    func localized(_ key: String) -> String {
        L10n.t(key, language)
    }

    var localAPIStatusTitle: String {
        switch localAPIStatus {
        case .disabled:
            localized("localAPIDisabled")
        case .starting:
            localized("localAPIStarting")
        case .running:
            localized("localAPIRunning")
        case .stopped:
            localized("localAPIStopped")
        case .failed:
            localized("localAPIFailed")
        }
    }

    var localAPIStatusDetail: String {
        switch localAPIStatus {
        case .disabled:
            localized("localAPIDisabledDetail")
        case .starting(let port):
            String(format: localized("localAPIStartingDetail"), port)
        case .running(let port):
            String(format: localized("localAPIRunningDetail"), port)
        case .stopped:
            localized("localAPIStoppedDetail")
        case .failed(let message):
            message.isEmpty ? localized("localAPIFailedDetail") : message
        }
    }

    var localAPISummaryValue: String {
        switch localAPIStatus {
        case .running(let port), .starting(let port):
            "\(port)"
        case .disabled:
            localized("off")
        case .stopped:
            localized("stopped")
        case .failed:
            localized("failed")
        }
    }

    func setLocalAPIStatus(_ status: LocalAPIStatus) {
        guard localAPIStatus != status else { return }
        localAPIStatus = status
        notifyStatusBarUpdate()
    }

    func refreshAll() {
        guard isRefreshingUsage == false else { return }
        isRefreshingUsage = true
        reloadModelUsageRollups()
        reloadModelCatalogFromLocalSources()

        Task {
            async let openAIResult = openAIUsageService.refresh()
            async let anthropicResult = anthropicUsageService.refresh()
            async let openRouterResult = openRouterCreditsService.refresh()
            async let codexResult = codexUsageService.refresh()
            async let miniMaxResult = miniMaxUsageService.refresh()
            async let ccSwitchResult = ccSwitchUsageService.refresh()
            apply(
                openAIResult: await openAIResult,
                anthropicResult: await anthropicResult,
                openRouterResult: await openRouterResult,
                codexResult: await codexResult,
                miniMaxResult: await miniMaxResult,
                ccSwitchResult: await ccSwitchResult
            )
        }
    }

    func storeOpenAIAdminKey(_ key: String) async throws {
        try await KeychainService.shared.store(value: key, for: "OPENAI_ADMIN_KEY")
        addAudit(provider: "OpenAI", action: "key.store", detail: "Stored OpenAI admin key in Keychain")
        refreshAll()
    }

    func clearOpenAIAdminKey() async throws {
        try await KeychainService.shared.delete(key: "OPENAI_ADMIN_KEY")
        addAudit(provider: "OpenAI", action: "key.delete", detail: "Removed OpenAI admin key from Keychain")
        if let index = providers.firstIndex(where: { $0.id == "openai" }) {
            providers[index].markSource(
                .liveUnavailable,
                detail: "OpenAI live usage requires OPENAI_ADMIN_KEY in Keychain or the app environment.",
                clearUsage: true
            )
        }
        persistProviders()
        notifyStatusBarUpdate()
    }

    func storeAnthropicAdminKey(_ key: String) async throws {
        try await KeychainService.shared.store(value: key, for: "ANTHROPIC_ADMIN_KEY")
        addAudit(provider: "Anthropic", action: "key.store", detail: "Stored Anthropic Admin API key in Keychain")
        refreshAll()
    }

    func clearAnthropicAdminKey() async throws {
        try await KeychainService.shared.delete(key: "ANTHROPIC_ADMIN_KEY")
        addAudit(provider: "Anthropic", action: "key.delete", detail: "Removed Anthropic Admin API key from Keychain")
        if let index = providers.firstIndex(where: { $0.id == "anthropic" }) {
            providers[index].markSource(
                .liveUnavailable,
                detail: "Anthropic live usage requires ANTHROPIC_ADMIN_KEY in Keychain or the app environment. Use an Admin API key that starts with sk-ant-admin.",
                clearUsage: true
            )
        }
        persistProviders()
        notifyStatusBarUpdate()
    }

    func storeOpenRouterAPIKey(_ key: String) async throws {
        try await KeychainService.shared.store(value: key, for: "OPENROUTER_API_KEY")
        addAudit(provider: "OpenRouter", action: "key.store", detail: "Stored OpenRouter API key in Keychain")
        refreshAll()
    }

    func clearOpenRouterAPIKey() async throws {
        try await KeychainService.shared.delete(key: "OPENROUTER_API_KEY")
        addAudit(provider: "OpenRouter", action: "key.delete", detail: "Removed OpenRouter API key from Keychain")
        if let index = providers.firstIndex(where: { $0.id == "openrouter" }) {
            providers[index].markSource(
                .liveUnavailable,
                detail: "OpenRouter live credits require OPENROUTER_API_KEY in Keychain or the app environment.",
                clearUsage: true
            )
        }
        persistProviders()
        notifyStatusBarUpdate()
    }

    func storeMiniMaxAPIKey(_ key: String) async throws {
        try await KeychainService.shared.store(value: key, for: "MINIMAX_API_KEY")
        addAudit(provider: "MiniMax", action: "key.store", detail: "Stored MiniMax API key in Keychain")
        refreshAll()
    }

    func clearMiniMaxAPIKey() async throws {
        try await KeychainService.shared.delete(key: "MINIMAX_API_KEY")
        addAudit(provider: "MiniMax", action: "key.delete", detail: "Removed MiniMax API key from Keychain")
        if let index = providers.firstIndex(where: { $0.id == "minimax" }) {
            providers[index].markSource(
                .liveUnavailable,
                detail: "MiniMax Token Plan quota requires MINIMAX_API_KEY in Keychain or the app environment.",
                clearUsage: true
            )
        }
        persistProviders()
        notifyStatusBarUpdate()
    }

    func resetSessionBudget() {
        sessionSpend = 0
        focusModeEnabled = true
        addAudit(provider: localized("focusMode"), action: "budget.reset", detail: "Session budget meter reset")
        notifyStatusBarUpdate()
    }

    func runPolicyCheck() {
        rebuildPolicyInput()
        currentDecision = evaluatePolicy(input: currentPolicyInput, shouldRecord: true)
        notifyStatusBarUpdate()
    }

    func refreshModelCatalog(providerID: String? = nil, baseURL: String? = nil) {
        guard isRefreshingModelCatalog == false else { return }
        let targetProviderID = providerID ?? selectedProviderID
        isRefreshingModelCatalog = true
        modelCatalogMessage = localized("modelCatalogRefreshing")

        Task {
            let remote = await providerModelCatalogService.fetch(providerID: targetProviderID, baseURL: baseURL)
            await MainActor.run {
                self.applyModelCatalogResult(remote, providerID: targetProviderID)
            }
        }
    }

    func modelCatalog(for providerID: String) -> [ModelCatalogItem] {
        modelCatalogItems
            .filter { $0.providerID == providerID || providerAliases(providerID).contains($0.providerID) }
            .sorted { lhs, rhs in
                if lhs.source != rhs.source {
                    return sourceRank(lhs.source) < sourceRank(rhs.source)
                }
                return lhs.modelID.localizedStandardCompare(rhs.modelID) == .orderedAscending
            }
    }

    func addProvider(template: ProbeTemplate) {
        guard providers.contains(where: { $0.id == template.platform }) == false else { return }
        providers.append(AppSeedData.provider(
            id: template.platform,
            name: template.displayName,
            category: template.category,
            symbol: template.symbolName,
            current: 0,
            limit: 10_000,
            unit: template.unit,
            spendToday: 0,
            spendMonth: 0,
            resetHours: 24 * 14
        ))
        selectedProviderID = template.platform
        addAudit(provider: template.displayName, action: "provider.add", detail: "Provider metadata added; API key belongs in Keychain")
        persistProviders()
    }

    func evaluatePolicy(
        input: PolicyEvaluationInput,
        shouldRecord: Bool = true,
        workspacePolicies evaluationWorkspacePolicies: [WorkspacePolicy]? = nil
    ) -> PolicyDecision {
        let activeWorkspacePolicies = evaluationWorkspacePolicies ?? workspacePolicies
        var decision = PolicyEngine.evaluate(
            input: input,
            workspaces: activeWorkspacePolicies,
            selectedWorkspace: selectedWorkspace,
            providers: providers,
            projectedSessionSpend: projectedSessionSpend,
            sessionBudget: sessionBudget
        )
        decision.routingMode = routingMode
        if routingMode == .smartRouting {
            applySmartRoutingRecommendation(to: &decision, input: input, workspacePolicies: activeWorkspacePolicies)
        }

        if shouldRecord {
            recentDecisions.insert(decision, at: 0)
            if recentDecisions.count > 20 {
                recentDecisions.removeLast(recentDecisions.count - 20)
            }
            addAudit(provider: input.agent.displayName, action: "policy.\(decision.status.rawValue)", detail: "\(decision.workspaceName) · \(input.model) · $\(formatMoney(input.estimatedCost))")
        }

        return decision
    }

    private func applySmartRoutingRecommendation(
        to decision: inout PolicyDecision,
        input: PolicyEvaluationInput,
        workspacePolicies evaluationWorkspacePolicies: [WorkspacePolicy]
    ) {
        guard let recommendation = smartRoutingRecommendation(for: input, workspacePolicies: evaluationWorkspacePolicies) else {
            decision.reasons.append("Smart Routing is enabled, but no eligible model route is available yet.")
            return
        }

        decision.smartRoutingRecommendation = recommendation
        let routeLabel = "\(providerDisplayName(recommendation.providerID)) / \(recommendation.model)"
        if decision.status == .block {
            decision.reasons.append("Smart Routing found \(routeLabel), but the guard policy still blocks this run.")
            return
        }

        if recommendation.providerID != input.providerID || recommendation.model != input.model {
            decision.reasons.append("Smart Routing recommends \(routeLabel).")
            decision.recommendation = "Smart Routing recommends \(routeLabel). \(recommendation.reason)"
        } else {
            decision.reasons.append("Smart Routing agrees with the selected route.")
        }
    }

    private func smartRoutingRecommendation(
        for input: PolicyEvaluationInput,
        workspacePolicies evaluationWorkspacePolicies: [WorkspacePolicy]
    ) -> SmartRoutingRecommendation? {
        let workspace = evaluationWorkspacePolicies.first { $0.id == input.workspaceID } ?? selectedWorkspace
        let stats = smartRoutingLedgerStore.stats()
        let scored = smartRoutingCandidates(input: input, workspace: workspace, stats: stats).compactMap { candidate -> ScoredSmartRoutingCandidate? in
            let route = bestRouteStats(for: candidate, intent: input.intent, stats: stats.routeStats)
            guard let candidateInput = smartRoutingPolicyInput(for: candidate, baseInput: input, route: route, workspace: workspace) else {
                return nil
            }

            let candidateDecision = PolicyEngine.evaluate(
                input: candidateInput,
                workspaces: evaluationWorkspacePolicies,
                selectedWorkspace: selectedWorkspace,
                providers: providers,
                projectedSessionSpend: sessionSpend + candidateInput.estimatedCost,
                sessionBudget: sessionBudget
            )
            guard candidateDecision.status != .block else {
                return nil
            }
            return ScoredSmartRoutingCandidate(
                candidate: candidate,
                score: smartRoutingScore(candidate: candidate, route: route),
                route: route,
                estimatedCost: candidateInput.estimatedCost
            )
        }
        .sorted {
            if $0.score != $1.score { return $0.score > $1.score }
            if ($0.route?.runCount ?? 0) != ($1.route?.runCount ?? 0) { return ($0.route?.runCount ?? 0) > ($1.route?.runCount ?? 0) }
            return $0.candidate.model.localizedStandardCompare($1.candidate.model) == .orderedAscending
        }

        guard let best = scored.first else { return nil }
        let route = best.route
        let runCount = route?.runCount ?? 0
        let winRate = route?.winRate ?? 0
        let alternatives = scored.dropFirst().prefix(3).map { "\($0.candidate.providerID)/\($0.candidate.model)" }
        let reason: String
        if let route, route.runCount > 0 {
            reason = "Based on \(route.runCount) recorded \(route.taskIntent) runs with \(Int(route.winRate * 100))% win rate."
        } else if best.candidate.sourceRank <= 1 {
            reason = "Based on configured local agent models and current policy constraints."
        } else {
            reason = "Based on the current selected route and provider health."
        }

        return SmartRoutingRecommendation(
            providerID: best.candidate.providerID,
            model: best.candidate.model,
            taskIntent: input.intent,
            confidence: min(max(best.score, 0.1), 0.95),
            evidenceRunCount: runCount,
            winRate: winRate,
            estimatedCost: best.estimatedCost,
            reason: reason,
            alternatives: alternatives
        )
    }

    private func smartRoutingPolicyInput(
        for candidate: SmartRoutingCandidate,
        baseInput: PolicyEvaluationInput,
        route: SmartRoutingRouteStats?,
        workspace: WorkspacePolicy?
    ) -> PolicyEvaluationInput? {
        guard candidate.model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false,
              candidate.model != "unspecified"
        else {
            return nil
        }

        let estimatedCost = estimatedCost(candidate: candidate, route: route, baseInput: baseInput)
        if estimatedCost == nil, (workspace?.maxEstimatedRunCost ?? 0) > 0 {
            return nil
        }

        var candidateInput = baseInput
        candidateInput.providerID = candidate.providerID
        candidateInput.model = candidate.model
        candidateInput.estimatedCost = estimatedCost ?? 0
        return candidateInput
    }

    private func smartRoutingCandidates(input: PolicyEvaluationInput, workspace: WorkspacePolicy?, stats: SmartRoutingStatsSnapshot) -> [SmartRoutingCandidate] {
        var candidates: [SmartRoutingCandidate] = []

        func add(providerID: String?, model: String?, sourceRank: Int) {
            let provider = normalizedProviderID(providerID, model: model, agent: input.agent)
            let model = normalizedModel(model, providerID: provider)
            guard model != "unspecified" else { return }
            candidates.append(SmartRoutingCandidate(providerID: provider, model: model, sourceRank: sourceRank))
        }

        add(providerID: input.providerID, model: input.model, sourceRank: 2)
        add(providerID: workspace?.preferredProviderID, model: workspace?.preferredModel, sourceRank: 0)
        for row in modelUsageRollups {
            add(providerID: row.providerID, model: row.model, sourceRank: row.source == .localAgent ? 0 : 1)
        }
        for item in modelCatalogItems {
            add(providerID: item.providerID, model: item.modelID, sourceRank: item.source == .localAgentConfig ? 1 : 2)
        }
        for route in stats.routeStats.prefix(30) {
            add(providerID: route.providerID, model: route.model, sourceRank: 0)
        }

        var seen = Set<String>()
        return candidates.filter { candidate in
            let key = "\(candidate.providerID)|\(candidate.model.lowercased())"
            guard seen.contains(key) == false else { return false }
            seen.insert(key)
            return true
        }
    }

    private func bestRouteStats(for candidate: SmartRoutingCandidate, intent: String, stats: [SmartRoutingRouteStats]) -> SmartRoutingRouteStats? {
        stats
            .filter { route in
                route.providerID == candidate.providerID &&
                route.model.caseInsensitiveCompare(candidate.model) == .orderedSame
            }
            .sorted {
                let lhsExact = $0.taskIntent.caseInsensitiveCompare(intent) == .orderedSame
                let rhsExact = $1.taskIntent.caseInsensitiveCompare(intent) == .orderedSame
                if lhsExact != rhsExact { return lhsExact }
                if $0.runCount != $1.runCount { return $0.runCount > $1.runCount }
                return $0.winRate > $1.winRate
            }
            .first
    }

    private func smartRoutingScore(candidate: SmartRoutingCandidate, route: SmartRoutingRouteStats?) -> Double {
        var score = max(0.1, 0.35 - Double(candidate.sourceRank) * 0.07)
        if let route {
            score = 0.35 + route.winRate * 0.45 + min(Double(route.runCount) / 10, 1) * 0.15 - route.followUpRate * 0.2
        }
        if let provider = providers.first(where: { $0.id == candidate.providerID }) {
            switch provider.status {
            case .healthy: score += 0.08
            case .warning: score -= 0.04
            case .critical: score -= 0.16
            }
        }
        return score
    }

    private func estimatedCost(candidate: SmartRoutingCandidate, route: SmartRoutingRouteStats?, baseInput: PolicyEvaluationInput) -> Double? {
        if let route, route.runCount > 0, route.actualCostTotal > 0 {
            return route.actualCostTotal / Double(route.runCount)
        }
        if candidate.providerID == baseInput.providerID &&
            candidate.model.caseInsensitiveCompare(baseInput.model) == .orderedSame {
            return baseInput.estimatedCost
        }
        return nil
    }

    private func providerDisplayName(_ providerID: String) -> String {
        providers.first { $0.id == providerID }?.name ?? providerID
    }

    func updateWorkspaceMaxEstimatedRunCost(id: String, value: Double) {
        guard value.isFinite else { return }
        var updated = workspacePolicies
        guard let index = updated.firstIndex(where: { $0.id == id }) else { return }
        updated[index].maxEstimatedRunCost = max(value, 0.01)
        workspacePolicies = updated
        persistWorkspacePolicies()
        rebuildPolicyInput()
        notifyStatusBarUpdate()
    }

    func adjustWorkspaceMaxEstimatedRunCost(id: String, delta: Double) {
        guard let workspace = workspacePolicies.first(where: { $0.id == id }) else { return }
        updateWorkspaceMaxEstimatedRunCost(id: id, value: workspace.maxEstimatedRunCost + delta)
    }

    func policyJSON() -> Data {
        LocalAPIPayloadBuilder.policyJSON(currentDecision: currentDecision, workspacePolicies: workspacePolicies)
    }

    func policyDecisionJSON(input: PolicyEvaluationInput) -> Data {
        let transientWorkspacePolicies = workspacePoliciesForPolicyEvaluation(input)
        let decision = evaluatePolicy(input: input, shouldRecord: false, workspacePolicies: transientWorkspacePolicies)
        currentDecision = decision
        return LocalAPIPayloadBuilder.policyDecisionJSON(decision)
    }

    func ingestLocalAgentUsageJSON(input: LocalAgentUsageIngest) -> Data {
        let snapshot = applyLocalAgentUsage(input)
        let policyInput = PolicyEvaluationInput(
            agent: snapshot.agent,
            workspaceID: snapshot.workspaceID ?? selectedWorkspaceID,
            providerID: snapshot.providerID,
            model: snapshot.model,
            estimatedCost: snapshot.costDelta,
            estimatedTokens: Int(snapshot.tokenDelta),
            intent: "local_usage_ingest"
        )
        currentDecision = evaluatePolicy(input: policyInput, shouldRecord: false)
        return LocalAPIPayloadBuilder.localAgentUsageJSON(snapshot: snapshot, decision: currentDecision)
    }

    func ingestClaudeStatuslineJSON(data: Data) -> Data {
        guard let input = Self.claudeStatuslineInput(from: data) else {
            return Data(#"{"error":"invalid_claude_statusline_input"}"#.utf8)
        }
        return ingestLocalAgentUsageJSON(input: input)
    }

    func recordSmartRoutingRunJSON(input: SmartRoutingRunInput) -> Data {
        let record = smartRoutingLedgerStore.record(
            input,
            fallbackWorkspaceID: selectedWorkspaceID,
            fallbackAgent: selectedAgent
        )
        addAudit(
            provider: record.agent.displayName,
            action: "routing.\(record.signal.rawValue)",
            detail: "\(record.taskIntent) · \(record.providerID)/\(record.model) · $\(formatMoney(record.actualCost))"
        )
        return LocalAPIPayloadBuilder.smartRoutingRunJSON(record: record)
    }

    func smartRoutingStatsJSON() -> Data {
        LocalAPIPayloadBuilder.smartRoutingStatsJSON(snapshot: smartRoutingLedgerStore.stats())
    }

    func mcpSnapshotJSON(filteredProviderID: String? = nil) -> Data {
        LocalAPIPayloadBuilder.mcpSnapshotJSON(providers: providers, filteredProviderID: filteredProviderID)
    }

    func paceJSON(providerID: String) -> Data {
        guard let provider = providers.first(where: { $0.id == providerID }) else {
            return Data(#"{"error":"provider_not_found"}"#.utf8)
        }
        return LocalAPIPayloadBuilder.paceJSON(provider: provider, recommendation: insightText())
    }

    func statusBarText() -> String {
        switch statusBarContent {
        case .iconOnly:
            return ""
        case .customText:
            return customStatusText.isEmpty ? "TokenBar" : customStatusText
        case .guardDecision:
            return "\(currentDecision.status.rawValue.uppercased()) \(currentDecision.workspaceName)"
        case .activeWorkspace:
            guard let selectedWorkspace else { return "Workspace" }
            return selectedWorkspace.dailyBudget > 0
                ? "\(selectedWorkspace.name) $\(formatMoney(selectedWorkspace.spendToday))"
                : selectedWorkspace.name
        case .totalSpend:
            return totalSpendMonth > 0 ? "$\(formatMoney(totalSpendMonth))" : "TokenBar"
        case .sessionBudget:
            return sessionBudget > 0 ? "$\(formatMoney(sessionSpend)) / $\(formatMoney(sessionBudget))" : "TokenBar"
        }
    }

    func statusBarColor() -> NSColor {
        switch statusBarContent {
        case .guardDecision:
            return policyStatus.nsColor
        case .activeWorkspace:
            return selectedWorkspace?.status.nsColor ?? .controlAccentColor
        case .sessionBudget:
            return budgetStatus.nsColor
        case .totalSpend:
            return mostUrgentProvider?.status.nsColor ?? .controlAccentColor
        case .customText, .iconOnly:
            return selectedProvider?.status.nsColor ?? .controlAccentColor
        }
    }

    func statusBarSymbolName() -> String {
        switch statusBarContent {
        case .guardDecision:
            return currentDecision.status.symbolName
        case .activeWorkspace:
            return "folder.badge.gearshape"
        case .sessionBudget:
            return budgetStatus.symbolName
        case .totalSpend:
            return mostUrgentProvider?.status.symbolName ?? "chart.line.uptrend.xyaxis"
        case .customText:
            return "sparkles"
        case .iconOnly:
            return selectedProvider?.status.symbolName ?? "chart.bar.fill"
        }
    }

    func insightText() -> String {
        if currentDecision.status == .block {
            return language == .english
            ? "Policy blocked this run. Fix the provider, model, or workspace budget before continuing."
            : "策略已阻止本次运行。继续前请调整平台、模型或工作区预算。"
        }

        if currentDecision.status == .warn {
            return language == .english
            ? currentDecision.recommendation
            : "当前运行有预算或策略风险，建议切换到更便宜的模型或拆分任务。"
        }

        if budgetStatus == .critical {
            return language == .english
            ? "Session budget is already spent. Pause agent runs or switch to a lower-cost model."
            : "会话预算已经用完。建议暂停 Agent 批量任务，或切换到低成本模型。"
        }

        if let urgent = mostUrgentProvider, urgent.status != .healthy {
            if let alert = urgent.primaryHealthAlert {
                return language == .english
                ? "\(urgent.name) is \(alert.status.rawValue): \(alert.detail)"
                : "\(urgent.name) \(alert.status == .critical ? "严重" : "警告")：\(alert.detail)"
            }
            let hours = urgent.predictedExhaustion.map { max($0.timeIntervalSinceNow / 3600, 0) } ?? 0
            return language == .english
            ? "\(urgent.name) is trending hot. At the current pace it may run out in \(String(format: "%.1f", hours))h."
            : "\(urgent.name) 消耗偏快。按当前速度约 \(String(format: "%.1f", hours)) 小时后可能耗尽。"
        }

        return language == .english
        ? "Usage is within budget. Keep total spend in the menu bar for broad monitoring, or pin a provider during focused work."
        : "当前使用量在预算内。日常可显示总花费，专注工作时可固定某个平台。"
    }

    func formatMoney(_ value: Double) -> String {
        String(format: "%.2f", value)
    }

    func applySelectedAppIcon() {
        guard let image = NSImage(named: selectedAppIcon.assetName) else { return }
        NSApplication.shared.applicationIconImage = image
    }

    func shortCountdown(to date: Date) -> String {
        let seconds = max(date.timeIntervalSinceNow, 0)
        if seconds < 3600 {
            return "\(Int(seconds / 60))m"
        }
        if seconds < 86_400 {
            return "\(Int(seconds / 3600))h"
        }
        return "\(Int(seconds / 86_400))d"
    }

    private func savePreferencesAndNotify() {
        preferencesStore.save(AppPreferencesSnapshot(
            language: language,
            statusBarContent: statusBarContent,
            routingMode: routingMode,
            selectedMainSection: selectedMainSection,
            selectedProviderID: selectedProviderID,
            selectedWorkspaceID: selectedWorkspaceID,
            selectedAgent: selectedAgent,
            selectedModel: selectedModel,
            estimatedRunCost: estimatedRunCost,
            estimatedTokens: estimatedTokens,
            customStatusText: customStatusText,
            sessionBudget: sessionBudget,
            sessionSpend: sessionSpend,
            focusModeEnabled: focusModeEnabled,
            localAPIEnabled: localAPIEnabled,
            selectedAppIcon: selectedAppIcon,
            hasSelectedProviderPreference: hasExplicitSelectedProviderPreference,
            hasSelectedWorkspacePreference: hasExplicitSelectedWorkspacePreference,
            hasSelectedAgentPreference: hasExplicitSelectedAgentPreference,
            hasSelectedModelPreference: hasExplicitSelectedModelPreference
        ))
        notifyStatusBarUpdate()
    }

    private func normalizeSelectionsAfterLoad() {
        isApplyingInferredSelections = true
        defer { isApplyingInferredSelections = false }

        for providerID in workspacePolicies.flatMap(\.allowedProviderIDs) {
            ensureProviderExists(providerID: providerID)
        }
        if hasExplicitSelectedWorkspacePreference == false,
           let inferredWorkspace = workspacePolicies.first(where: { $0.preferredProviderID != nil || $0.preferredModel != nil }) {
            selectedWorkspaceID = inferredWorkspace.id
        }
        if providers.contains(where: { $0.id == selectedProviderID }) == false {
            hasExplicitSelectedProviderPreference = false
            selectedProviderID = providers.first?.id ?? "openai"
        }
        if workspacePolicies.contains(where: { $0.id == selectedWorkspaceID }) == false {
            hasExplicitSelectedWorkspacePreference = false
            selectedWorkspaceID = workspacePolicies.first?.id ?? "local-workspace"
        }
        if hasExplicitSelectedProviderPreference == false,
           let preferredProviderID = selectedWorkspace?.preferredProviderID,
           preferredProviderID.isEmpty == false {
            ensureProviderExists(providerID: preferredProviderID)
            selectedProviderID = preferredProviderID
        }
        if selectedModel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            hasExplicitSelectedModelPreference = false
        }
        if hasExplicitSelectedModelPreference == false,
           let preferredModel = selectedWorkspace?.preferredModel,
           preferredModel.isEmpty == false {
            selectedModel = preferredModel
        }
        if hasExplicitSelectedAgentPreference == false {
            selectedAgent = defaultAgent(providerID: selectedProviderID)
        }
        if sessionBudget <= 0 {
            sessionSpend = 0
            focusModeEnabled = false
        }
    }

    private func markExplicitSelection(_ keyPath: ReferenceWritableKeyPath<AppState, Bool>) {
        guard isApplyingInferredSelections == false else { return }
        self[keyPath: keyPath] = true
    }

    private func notifyStatusBarUpdate() {
        NotificationCenter.default.post(name: .tokenBarStateDidChange, object: self)
    }

    private func addAudit(provider: String, action: String, detail: String) {
        auditEvents.insert(AuditEvent(timestamp: .now, provider: provider, action: action, detail: detail), at: 0)
        if auditEvents.count > 100 {
            auditEvents.removeLast(auditEvents.count - 100)
        }
        auditEventStore.save(auditEvents)
    }

    private func persistProviders() {
        providerStore.save(providers)
    }

    private func persistWorkspacePolicies() {
        workspacePolicyStore.save(workspacePolicies)
    }

    private func rebuildPolicyInput() {
        currentPolicyInput = PolicyEvaluationInput(
            agent: selectedAgent,
            workspaceID: selectedWorkspaceID,
            providerID: selectedProviderID,
            model: selectedModel,
            estimatedCost: estimatedRunCost,
            estimatedTokens: Int(estimatedTokens),
            intent: "agent-run"
        )
        currentDecision = evaluatePolicy(input: currentPolicyInput, shouldRecord: false)
    }

    private func apply(
        openAIResult: OpenAIUsageRefreshResult,
        anthropicResult: AnthropicUsageRefreshResult,
        openRouterResult: OpenRouterCreditsRefreshResult,
        codexResult: CodexUsageRefreshResult,
        miniMaxResult: MiniMaxUsageRefreshResult,
        ccSwitchResult: CCSwitchUsageRefreshResult
    ) {
        defer {
            lastRefresh = .now
            isRefreshingUsage = false
            currentDecision = evaluatePolicy(input: currentPolicyInput, shouldRecord: false)
            persistProviders()
            if CommandLine.arguments.contains("--tokenbar-verify-local-api") == false {
                NotificationService.shared.notifyIfNeeded(appState: self)
            }
            notifyStatusBarUpdate()
        }

        applyOpenAIResult(openAIResult)
        applyAnthropicResult(anthropicResult)
        applyOpenRouterResult(openRouterResult)
        applyCodexResult(codexResult)
        applyCCSwitchResult(ccSwitchResult)
        applyMiniMaxResult(miniMaxResult)
    }

    private func applyOpenAIResult(_ result: OpenAIUsageRefreshResult) {
        ensureOpenAIProviderExists()
        guard let index = providers.firstIndex(where: { $0.id == "openai" }) else { return }

        switch result {
        case .success(let snapshot):
            providers[index].apply(snapshot: snapshot)
            addAudit(provider: "OpenAI", action: "usage.live", detail: "Fetched \(Int(snapshot.tokenTotal)) tokens, \(snapshot.requestCountMonth) requests, and \(snapshot.currency.uppercased()) \(formatMoney(snapshot.spendMonth)) month-to-date")
        case .unavailable(let detail):
            providers[index].markSource(.liveUnavailable, detail: detail, clearUsage: true)
            addAudit(provider: "OpenAI", action: "usage.needs_key", detail: "Live usage refresh skipped because no admin key is available")
        case .failure(let detail):
            providers[index].markSource(.error, detail: detail)
            addAudit(provider: "OpenAI", action: "usage.error", detail: detail)
        }
    }

    private func applyAnthropicResult(_ result: AnthropicUsageRefreshResult) {
        ensureAnthropicProviderExists()
        guard let index = providers.firstIndex(where: { $0.id == "anthropic" }) else { return }

        switch result {
        case .success(let snapshot):
            providers[index].apply(snapshot: snapshot)
            addAudit(provider: "Anthropic", action: "usage.live", detail: "Fetched \(Int(snapshot.tokenTotal)) tokens and \(snapshot.currency.uppercased()) \(formatMoney(snapshot.spendMonth)) month-to-date")
        case .unavailable(let detail):
            providers[index].markSource(.liveUnavailable, detail: detail, clearUsage: true)
            addAudit(provider: "Anthropic", action: "usage.needs_key", detail: "Live usage refresh skipped because no Anthropic Admin API key is available")
        case .failure(let detail):
            providers[index].markSource(.error, detail: detail)
            addAudit(provider: "Anthropic", action: "usage.error", detail: detail)
        }
    }

    private func applyOpenRouterResult(_ result: OpenRouterCreditsRefreshResult) {
        ensureOpenRouterProviderExists()
        guard let index = providers.firstIndex(where: { $0.id == "openrouter" }) else { return }

        switch result {
        case .success(let snapshot):
            providers[index].apply(snapshot: snapshot)
            addAudit(provider: "OpenRouter", action: "credits.live", detail: "Fetched \(formatMoney(snapshot.totalUsage)) used of \(formatMoney(snapshot.totalCredits)) credits")
        case .unavailable(let detail):
            providers[index].markSource(.liveUnavailable, detail: detail, clearUsage: true)
            addAudit(provider: "OpenRouter", action: "credits.needs_key", detail: "Live credits refresh skipped because no OpenRouter API key is available")
        case .failure(let detail):
            providers[index].markSource(.error, detail: detail)
            addAudit(provider: "OpenRouter", action: "credits.error", detail: detail)
        }
    }

    private func applyCodexResult(_ result: CodexUsageRefreshResult) {
        ensureCodexProviderExists()
        guard let index = providers.firstIndex(where: { $0.id == "codex" }) else { return }

        switch result {
        case .success(let snapshot):
            providers[index].apply(snapshot: snapshot)
            let primaryLabel = quotaWindowLabel(seconds: snapshot.primaryWindowSeconds, fallback: "5-hour")
            let secondary = snapshot.secondaryUsedPercent.map {
                ", \(quotaWindowLabel(seconds: snapshot.secondaryWindowSeconds, fallback: "7-day")) \(Int($0))%"
            } ?? ""
            addAudit(provider: "Codex", action: "quota.live", detail: "Fetched Codex quota: \(primaryLabel) \(Int(snapshot.primaryUsedPercent))%\(secondary)")
        case .unavailable(let detail):
            if providers[index].sourceKind != .localAgent {
                providers[index].markSource(.liveUnavailable, detail: detail, clearUsage: true)
            }
            addAudit(provider: "Codex", action: "quota.needs_auth", detail: "Codex quota refresh skipped because no local Codex auth is available")
        case .failure(let detail):
            providers[index].markSource(.error, detail: detail)
            addAudit(provider: "Codex", action: "quota.error", detail: detail)
        }
    }

    private func applyMiniMaxResult(_ result: MiniMaxUsageRefreshResult) {
        ensureMiniMaxProviderExists()
        guard let index = providers.firstIndex(where: { $0.id == "minimax" }) else { return }

        switch result {
        case .success(let snapshot):
            if providers[index].sourceKind != .ccSwitch {
                providers[index].apply(snapshot: snapshot)
            } else {
                providers[index].sourceDetail = "\(providers[index].sourceDescription) MiniMax Token Plan quota also refreshed: current \(snapshot.intervalWindowLabel) \(Int(snapshot.intervalUsedPercent))% used, weekly \(snapshot.weeklyWindowLabel) \(Int(snapshot.weeklyUsedPercent))% used."
                providers[index].sourceUpdatedAt = snapshot.fetchedAt
            }
            addAudit(provider: "MiniMax", action: "quota.live", detail: "Fetched MiniMax Token Plan quota: current \(Int(snapshot.intervalUsedPercent))%, weekly \(Int(snapshot.weeklyUsedPercent))%")
        case .unavailable(let detail):
            if providers[index].sourceKind != .ccSwitch {
                providers[index].markSource(.liveUnavailable, detail: detail, clearUsage: true)
            }
            addAudit(provider: "MiniMax", action: "quota.needs_key", detail: "MiniMax quota refresh skipped because no API key is available")
        case .failure(let detail):
            if providers[index].sourceKind != .ccSwitch {
                providers[index].markSource(.error, detail: detail)
            }
            addAudit(provider: "MiniMax", action: "quota.error", detail: detail)
        }
    }

    private func applyCCSwitchResult(_ result: CCSwitchUsageRefreshResult) {
        switch result {
        case .success(let snapshot):
            for providerSnapshot in snapshot.providers {
                ensureProviderExists(providerID: providerSnapshot.providerID)
                if let index = providers.firstIndex(where: { $0.id == providerSnapshot.providerID }) {
                    providers[index].name = providerSnapshot.displayName
                    providers[index].category = providerSnapshot.category
                    providers[index].symbolName = providerSnapshot.symbolName
                    providers[index].apply(snapshot: providerSnapshot)
                }
            }
            addAudit(provider: "CC Switch", action: "usage.local", detail: "Loaded \(snapshot.providers.count) provider rollups from CC Switch")
        case .unavailable(let detail):
            addAudit(provider: "CC Switch", action: "usage.unavailable", detail: detail)
        case .failure(let detail):
            addAudit(provider: "CC Switch", action: "usage.error", detail: detail)
        }
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

    private func ensureOpenAIProviderExists() {
        guard providers.contains(where: { $0.id == "openai" }) == false else { return }
        providers.insert(AppSeedData.provider(
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
        ), at: 0)
    }

    private func ensureAnthropicProviderExists() {
        guard providers.contains(where: { $0.id == "anthropic" }) == false else { return }
        providers.insert(AppSeedData.provider(
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
        ), at: min(providers.count, 1))
    }

    private func ensureOpenRouterProviderExists() {
        guard providers.contains(where: { $0.id == "openrouter" }) == false else { return }
        providers.insert(AppSeedData.provider(
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
        ), at: min(providers.count, 2))
    }

    private func ensureCodexProviderExists() {
        guard providers.contains(where: { $0.id == "codex" }) == false else { return }
        providers.insert(AppSeedData.provider(
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
        ), at: min(providers.count, 3))
    }

    private func ensureMiniMaxProviderExists() {
        guard providers.contains(where: { $0.id == "minimax" }) == false else { return }
        providers.insert(AppSeedData.provider(
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
        ), at: min(providers.count, 4))
    }

    private func applyLocalAgentUsage(_ input: LocalAgentUsageIngest) -> LocalAgentUsageAppliedSnapshot {
        let now = input.occurredAt ?? .now
        let providerID = normalizedProviderID(input.providerID, model: input.model, agent: input.agent)
        let agent = input.agent ?? defaultAgent(providerID: providerID)
        let model = normalizedModel(input.model, providerID: providerID)
        let workspaceID = upsertWorkspacePolicy(from: input, providerID: providerID)
        ensureProviderExists(providerID: providerID)

        let contextTokenTotal = Double(input.totalTokens ?? ((input.inputTokens ?? 0) + (input.outputTokens ?? 0)))
        let cumulativeCost = max(input.costUSD ?? 0, 0)
        let cumulativeRequests = max(input.requestCount ?? 0, 0)
        let sessionKey = localUsageSessionKey(input: input, agent: agent, providerID: providerID, model: model, workspaceID: workspaceID)
        let isCumulative = input.cumulative ?? true
        let delta = isCumulative
            ? localAgentUsageLedgerStore.apply(
                sessionKey: sessionKey,
                cumulativeCost: cumulativeCost,
                cumulativeTokens: contextTokenTotal,
                cumulativeRequestCount: cumulativeRequests,
                now: now
            )
            : LocalAgentUsageDelta(costUSD: cumulativeCost, tokens: contextTokenTotal, requestCount: cumulativeRequests)
        let detail = localUsageSourceDetail(input: input, providerID: providerID, costDelta: delta.costUSD, tokenDelta: delta.tokens)
        let snapshot = LocalAgentUsageAppliedSnapshot(
            agent: agent,
            providerID: providerID,
            model: model,
            workspaceID: workspaceID,
            sessionKey: sessionKey,
            sourceName: input.source ?? "local_agent",
            costDelta: delta.costUSD,
            tokenDelta: delta.tokens,
            requestDelta: delta.requestCount,
            contextTokenTotal: contextTokenTotal,
            contextWindowSize: input.contextWindowSize.map(Double.init),
            rateLimitUsedPercentage: input.rateLimitUsedPercentage,
            rateLimitResetAt: input.rateLimitResetAt,
            occurredAt: now,
            sourceDetail: detail
        )

        if let providerIndex = providers.firstIndex(where: { $0.id == providerID }) {
            providers[providerIndex].apply(localUsage: snapshot)
        }
        if let workspaceID, let workspaceIndex = workspacePolicies.firstIndex(where: { $0.id == workspaceID }) {
            workspacePolicies[workspaceIndex].spendToday += delta.costUSD
            workspacePolicies[workspaceIndex].spendMonth += delta.costUSD
        }
        addAudit(
            provider: agent.displayName,
            action: "usage.local",
            detail: "\(model) · \(providerID) · +$\(formatMoney(delta.costUSD)) · +\(Int(delta.tokens)) tokens"
        )
        mergeModelUsageRollups(localModelUsageStore.apply(snapshot: snapshot))
        persistProviders()
        persistWorkspacePolicies()
        notifyStatusBarUpdate()
        return snapshot
    }

    private func upsertWorkspacePolicy(from input: LocalAgentUsageIngest, providerID: String) -> String? {
        let workspaceID = input.workspaceID ?? workspaceIDMatching(path: input.currentDirectory ?? input.workspacePath)
        guard let workspaceID, workspaceID.isEmpty == false else { return selectedWorkspaceID }

        if let index = workspacePolicies.firstIndex(where: { $0.id == workspaceID }) {
            workspacePolicies[index].name = input.workspaceName ?? workspacePolicies[index].name
            workspacePolicies[index].pathHint = input.workspacePath ?? input.currentDirectory ?? workspacePolicies[index].pathHint
            workspacePolicies[index].client = input.workspaceClient ?? workspacePolicies[index].client
            workspacePolicies[index].dailyBudget = input.dailyBudget ?? workspacePolicies[index].dailyBudget
            workspacePolicies[index].monthlyBudget = input.monthlyBudget ?? workspacePolicies[index].monthlyBudget
            workspacePolicies[index].maxEstimatedRunCost = input.maxEstimatedRunCost ?? workspacePolicies[index].maxEstimatedRunCost
            workspacePolicies[index].allowedProviderIDs = input.allowedProviderIDs ?? workspacePolicies[index].allowedProviderIDs
            workspacePolicies[index].blockedModels = input.blockedModels ?? workspacePolicies[index].blockedModels
            workspacePolicies[index].requireCompanyKey = input.requireCompanyKey ?? workspacePolicies[index].requireCompanyKey
            workspacePolicies[index].preferredProviderID = workspacePolicies[index].preferredProviderID ?? providerID
            workspacePolicies[index].preferredModel = workspacePolicies[index].preferredModel ?? normalizedModel(input.model, providerID: providerID)
        } else {
            var allowedProviderIDs = ["anthropic", "openai", "openrouter"]
            if allowedProviderIDs.contains(providerID) == false {
                allowedProviderIDs.append(providerID)
            }
            workspacePolicies.append(WorkspacePolicy(
                id: workspaceID,
                name: input.workspaceName ?? titleFromWorkspaceID(workspaceID),
                pathHint: input.workspacePath ?? input.currentDirectory ?? "~",
                client: input.workspaceClient ?? "local",
                dailyBudget: input.dailyBudget ?? 0,
                monthlyBudget: input.monthlyBudget ?? 0,
                spendToday: 0,
                spendMonth: 0,
                allowedProviderIDs: input.allowedProviderIDs ?? allowedProviderIDs,
                blockedModels: input.blockedModels ?? [],
                maxEstimatedRunCost: input.maxEstimatedRunCost ?? 0,
                requireCompanyKey: input.requireCompanyKey ?? false,
                preferredProviderID: providerID,
                preferredModel: normalizedModel(input.model, providerID: providerID),
                setupSourceDetail: "Created from local agent usage ingestion.",
                configuredModelCount: nil,
                inferredFromPaths: [input.transcriptPath, input.currentDirectory].compactMap { $0 }
            ))
        }

        return workspaceID
    }

    private func workspacePoliciesForPolicyEvaluation(_ input: PolicyEvaluationInput) -> [WorkspacePolicy] {
        guard input.hasTransientWorkspacePolicyFields else {
            return workspacePolicies
        }

        var evaluationWorkspacePolicies = workspacePolicies
        if let index = workspacePolicies.firstIndex(where: { $0.id == input.workspaceID }) {
            evaluationWorkspacePolicies[index].name = input.workspaceName ?? evaluationWorkspacePolicies[index].name
            evaluationWorkspacePolicies[index].pathHint = input.workspacePath ?? evaluationWorkspacePolicies[index].pathHint
            evaluationWorkspacePolicies[index].client = input.workspaceClient ?? evaluationWorkspacePolicies[index].client
            evaluationWorkspacePolicies[index].dailyBudget = input.dailyBudget ?? evaluationWorkspacePolicies[index].dailyBudget
            evaluationWorkspacePolicies[index].monthlyBudget = input.monthlyBudget ?? evaluationWorkspacePolicies[index].monthlyBudget
            evaluationWorkspacePolicies[index].maxEstimatedRunCost = input.maxEstimatedRunCost ?? evaluationWorkspacePolicies[index].maxEstimatedRunCost
            evaluationWorkspacePolicies[index].allowedProviderIDs = input.allowedProviderIDs ?? evaluationWorkspacePolicies[index].allowedProviderIDs
            evaluationWorkspacePolicies[index].blockedModels = input.blockedModels ?? evaluationWorkspacePolicies[index].blockedModels
            evaluationWorkspacePolicies[index].requireCompanyKey = input.requireCompanyKey ?? evaluationWorkspacePolicies[index].requireCompanyKey
            evaluationWorkspacePolicies[index].preferredProviderID = input.preferredProviderID ?? input.providerID
            evaluationWorkspacePolicies[index].preferredModel = input.preferredModel ?? input.model
            evaluationWorkspacePolicies[index].setupSourceDetail = evaluationWorkspacePolicies[index].setupSourceDetail ?? "Evaluated from tokenbar.yml via local policy check."
        } else {
            evaluationWorkspacePolicies.append(WorkspacePolicy(
                id: input.workspaceID,
                name: input.workspaceName ?? titleFromWorkspaceID(input.workspaceID),
                pathHint: input.workspacePath ?? "~",
                client: input.workspaceClient ?? "local",
                dailyBudget: input.dailyBudget ?? 0,
                monthlyBudget: input.monthlyBudget ?? 0,
                spendToday: 0,
                spendMonth: 0,
                allowedProviderIDs: input.allowedProviderIDs ?? [input.providerID],
                blockedModels: input.blockedModels ?? [],
                maxEstimatedRunCost: input.maxEstimatedRunCost ?? 0,
                requireCompanyKey: input.requireCompanyKey ?? false,
                preferredProviderID: input.preferredProviderID ?? input.providerID,
                preferredModel: input.preferredModel ?? input.model,
                setupSourceDetail: "Evaluated from tokenbar.yml via local policy check.",
                configuredModelCount: nil,
                inferredFromPaths: [input.workspacePath].compactMap { $0 }
            ))
        }

        return evaluationWorkspacePolicies
    }

    private func ensureProviderExists(providerID: String) {
        guard providers.contains(where: { $0.id == providerID }) == false else { return }
        switch providerID {
        case "openai":
            ensureOpenAIProviderExists()
        case "anthropic":
            ensureAnthropicProviderExists()
        case "openrouter":
            ensureOpenRouterProviderExists()
        case "codex":
            ensureCodexProviderExists()
        case "minimax":
            ensureMiniMaxProviderExists()
        case "deepseek":
            providers.append(AppSeedData.provider(
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
            ))
        case "xiaomi-mimo":
            providers.append(AppSeedData.provider(
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
            ))
        default:
            providers.append(AppSeedData.provider(
                id: providerID,
                name: titleFromWorkspaceID(providerID),
                category: "AI & API",
                symbol: "network",
                current: 0,
                limit: 0,
                unit: "tokens",
                spendToday: 0,
                spendMonth: 0,
                resetHours: 24 * 30,
                dataSource: .localAgent,
                sourceDetail: "Local agent usage was ingested through TokenBar's local API."
            ))
        }
    }

    private func normalizedProviderID(_ providerID: String?, model: String?, agent: AgentProvider?) -> String {
        let provider = providerID?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let provider, provider.isEmpty == false { return provider }
        let model = model?.lowercased() ?? ""
        if model.contains("claude") { return "anthropic" }
        if model.contains("gpt") || model.contains("o1") || model.contains("o3") || model.contains("o4") { return "openai" }
        if model.contains("minimax") { return "minimax" }
        if model.contains("deepseek") { return "deepseek" }
        if model.contains("gemini") { return "google" }
        if model.contains("mistral") { return "mistral" }
        if model.contains("kimi") { return "kimi" }
        if model.contains("mimo") || model.contains("xiaomi") { return "xiaomi-mimo" }
        if model.contains("glm") { return "glm" }
        if model.contains("qwen") { return "qwen" }
        switch agent {
        case .claudeCode:
            return "anthropic"
        case .codex:
            return "openai"
        default:
            return selectedProviderID
        }
    }

    private func defaultAgent(providerID: String) -> AgentProvider {
        switch providerID {
        case "anthropic":
            return .claudeCode
        case "openai":
            return .codex
        default:
            return .custom
        }
    }

    private func normalizedModel(_ model: String?, providerID: String) -> String {
        let value = model?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if value.isEmpty == false { return value }
        switch providerID {
        case "anthropic": return "claude-sonnet"
        case "openai": return "gpt-5"
        case "minimax": return "minimax-m1"
        case "deepseek": return "deepseek-chat"
        case "google": return "gemini-2.5-pro"
        case "mistral": return "mistral-large-latest"
        case "kimi": return "kimi-k2"
        case "glm": return "glm-4.5"
        default: return "unspecified"
        }
    }

    private func localUsageSessionKey(input: LocalAgentUsageIngest, agent: AgentProvider, providerID: String, model: String, workspaceID: String?) -> String {
        if let sessionID = input.sessionID, sessionID.isEmpty == false { return sessionID }
        if let transcriptPath = input.transcriptPath, transcriptPath.isEmpty == false { return transcriptPath }
        return [agent.rawValue, providerID, model, workspaceID ?? "workspace", input.currentDirectory ?? ""].joined(separator: "|")
    }

    private func workspaceIDMatching(path: String?) -> String? {
        guard let path, path.isEmpty == false else { return nil }
        let expanded = NSString(string: path).expandingTildeInPath
        return workspacePolicies.first { policy in
            let policyPath = NSString(string: policy.pathHint).expandingTildeInPath
            return expanded.hasPrefix(policyPath) || policyPath.hasPrefix(expanded)
        }?.id
    }

    private func titleFromWorkspaceID(_ value: String) -> String {
        let words = value.replacingOccurrences(of: "_", with: "-").split(separator: "-")
        guard words.isEmpty == false else { return "Workspace" }
        return words.map { word in
            word.prefix(1).uppercased() + word.dropFirst()
        }.joined(separator: " ")
    }

    private func localUsageSourceDetail(input: LocalAgentUsageIngest, providerID: String, costDelta: Double, tokenDelta: Double) -> String {
        let source = input.source ?? "local agent"
        var parts = ["\(source) usage ingested locally for \(providerID)."]
        if input.contextWindowSize != nil {
            parts.append("Context tokens are from the local session; provider billing still belongs to the provider console.")
        } else {
            parts.append("Token and cost totals are local agent data, not a provider-admin usage API.")
        }
        parts.append("Applied +$\(formatMoney(costDelta)) and +\(Int(tokenDelta)) tokens after session de-duplication.")
        if let rateLimitUsedPercentage = input.rateLimitUsedPercentage {
            parts.append("Reported rate-limit use: \(Int(rateLimitUsedPercentage))%.")
        }
        return parts.joined(separator: " ")
    }

    private func reloadModelUsageRollups() {
        mergeModelUsageRollups(localModelUsageStore.load())
    }

    private func reloadModelCatalogFromLocalSources() {
        let localItems = agentModelConfigurationService.readConfiguredModelCatalogItems()
            + ccSwitchUsageService.configuredModelCatalogItems()
        mergeModelCatalogItems(localItems, replacingProviderID: nil)
    }

    private func applyModelCatalogResult(_ result: ProviderModelCatalogResult, providerID: String) {
        isRefreshingModelCatalog = false
        switch result {
        case .success(let items):
            mergeModelCatalogItems(items, replacingProviderID: providerID)
            modelCatalogMessage = items.isEmpty
                ? localized("modelCatalogEmpty")
                : String(format: localized("modelCatalogLoadedFormat"), items.count)
            addAudit(provider: providerID, action: "models.refresh", detail: "Fetched \(items.count) models")
        case .unavailable(let detail):
            modelCatalogMessage = detail
            addAudit(provider: providerID, action: "models.unavailable", detail: detail)
        case .failure(let detail):
            modelCatalogMessage = detail
            addAudit(provider: providerID, action: "models.error", detail: detail)
        }
        notifyStatusBarUpdate()
    }

    private func mergeModelCatalogItems(_ items: [ModelCatalogItem], replacingProviderID: String?) {
        var merged = modelCatalogItems
        if let replacingProviderID {
            let aliases = providerAliases(replacingProviderID).union([replacingProviderID])
            merged.removeAll { aliases.contains($0.providerID) && $0.source == .providerAPI }
        }
        merged.append(contentsOf: items)

        var bestByKey: [String: ModelCatalogItem] = [:]
        for item in merged where item.modelID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
            let key = [item.providerID, item.modelID.lowercased()].joined(separator: "|")
            if let existing = bestByKey[key] {
                if sourceRank(item.source) < sourceRank(existing.source) {
                    bestByKey[key] = item
                }
            } else {
                bestByKey[key] = item
            }
        }
        modelCatalogItems = bestByKey.values.sorted {
            if $0.providerID != $1.providerID {
                return $0.providerID < $1.providerID
            }
            if $0.source != $1.source {
                return sourceRank($0.source) < sourceRank($1.source)
            }
            return $0.modelID.localizedStandardCompare($1.modelID) == .orderedAscending
        }
    }

    private func mergeModelUsageRollups(_ localRows: [ModelUsageRollup]) {
        let configuredRows = agentModelConfigurationService.readConfiguredModels()
        let localKeys = Set(localRows.map { modelUsageMergeKey($0) })
        let visibleConfiguredRows = configuredRows.filter { localKeys.contains(modelUsageMergeKey($0)) == false }
        modelUsageRollups = localRows + visibleConfiguredRows
    }

    private func modelUsageMergeKey(_ rollup: ModelUsageRollup) -> String {
        [rollup.agent.rawValue, rollup.providerID, rollup.model.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()].joined(separator: "|")
    }

    private func sourceRank(_ source: ModelCatalogSource) -> Int {
        switch source {
        case .providerAPI: 0
        case .ccSwitchConfig: 1
        case .localAgentConfig: 2
        }
    }

    private func providerAliases(_ providerID: String) -> Set<String> {
        switch providerID {
        case "google", "gemini":
            return ["google", "gemini"]
        case "ccswitch-codex", "codex":
            return ["ccswitch-codex", "codex", "openai"]
        default:
            return [providerID]
        }
    }

    private static func claudeStatuslineInput(from data: Data) -> LocalAgentUsageIngest? {
        guard let object = try? JSONSerialization.jsonObject(with: data) else { return nil }
        let model = nestedString(object, path: ["model", "id"])
            ?? nestedString(object, path: ["model", "name"])
            ?? stringValue(forAnyKey: ["model_id", "modelId", "model"], in: object)
        let inputTokens = intValue(forAnyKey: ["input_tokens", "inputTokens"], in: object)
        let outputTokens = intValue(forAnyKey: ["output_tokens", "outputTokens"], in: object)
        let cacheCreationTokens = intValue(forAnyKey: ["cache_creation_input_tokens", "cacheCreationInputTokens"], in: object) ?? 0
        let cacheReadTokens = intValue(forAnyKey: ["cache_read_input_tokens", "cacheReadInputTokens"], in: object) ?? 0
        let explicitTotalTokens = intValue(forAnyKey: ["total_tokens", "totalTokens", "tokens_used", "tokensUsed"], in: object)
        let computedTotalTokens = [inputTokens, outputTokens].compactMap { $0 }.reduce(0, +) + cacheCreationTokens + cacheReadTokens
        let totalTokens = explicitTotalTokens ?? (computedTotalTokens > 0 ? computedTotalTokens : nil)
        let sessionID = stringValue(forAnyKey: ["session_id", "sessionId"], in: object)
        let transcriptPath = stringValue(forAnyKey: ["transcript_path", "transcriptPath"], in: object)
        let currentDirectory = nestedString(object, path: ["workspace", "current_dir"])
            ?? nestedString(object, path: ["workspace", "currentDirectory"])
            ?? stringValue(forAnyKey: ["current_dir", "currentDirectory", "cwd"], in: object)

        return LocalAgentUsageIngest(
            agent: .claudeCode,
            providerID: nil,
            model: model,
            workspaceID: nil,
            workspaceName: nil,
            workspacePath: currentDirectory,
            workspaceClient: nil,
            dailyBudget: nil,
            monthlyBudget: nil,
            maxEstimatedRunCost: nil,
            allowedProviderIDs: nil,
            blockedModels: nil,
            requireCompanyKey: nil,
            sessionID: sessionID,
            source: "Claude Code statusline",
            currentDirectory: currentDirectory,
            transcriptPath: transcriptPath,
            costUSD: doubleValue(forAnyKey: ["total_cost_usd", "totalCostUSD", "cost_usd", "costUSD"], in: object),
            inputTokens: inputTokens,
            outputTokens: outputTokens,
            totalTokens: totalTokens,
            contextWindowSize: intValue(forAnyKey: ["context_window_size", "contextWindowSize"], in: object),
            requestCount: intValue(forAnyKey: ["request_count", "requestCount"], in: object),
            occurredAt: dateValue(forAnyKey: ["timestamp", "occurred_at", "occurredAt"], in: object),
            rateLimitUsedPercentage: doubleValue(forAnyKey: ["used_percentage", "usedPercentage", "rate_limit_used_percentage", "rateLimitUsedPercentage"], in: object),
            rateLimitResetAt: dateValue(forAnyKey: ["reset_at", "resetAt", "rate_limit_reset_at", "rateLimitResetAt"], in: object),
            cumulative: true
        )
    }

    private static func nestedString(_ object: Any, path: [String]) -> String? {
        var cursor = object
        for key in path {
            guard let dictionary = cursor as? [String: Any], let next = dictionary[key] else { return nil }
            cursor = next
        }
        return cursor as? String
    }

    private static func stringValue(forAnyKey keys: [String], in object: Any) -> String? {
        guard let value = firstValue(forAnyKey: keys, in: object) else { return nil }
        if let string = value as? String { return string.isEmpty ? nil : string }
        return "\(value)"
    }

    private static func intValue(forAnyKey keys: [String], in object: Any) -> Int? {
        guard let value = firstValue(forAnyKey: keys, in: object) else { return nil }
        if let int = value as? Int { return int }
        if let double = value as? Double { return Int(double) }
        if let string = value as? String { return Int(string) }
        return nil
    }

    private static func doubleValue(forAnyKey keys: [String], in object: Any) -> Double? {
        guard let value = firstValue(forAnyKey: keys, in: object) else { return nil }
        if let double = value as? Double { return double }
        if let int = value as? Int { return Double(int) }
        if let string = value as? String { return Double(string) }
        return nil
    }

    private static func dateValue(forAnyKey keys: [String], in object: Any) -> Date? {
        guard let value = firstValue(forAnyKey: keys, in: object) else { return nil }
        if let date = value as? Date { return date }
        if let seconds = value as? TimeInterval { return Date(timeIntervalSince1970: seconds) }
        guard let string = value as? String else { return nil }
        if let date = ISO8601DateFormatter().date(from: string) { return date }
        if let seconds = TimeInterval(string) { return Date(timeIntervalSince1970: seconds) }
        return nil
    }

    private static func firstValue(forAnyKey keys: [String], in object: Any) -> Any? {
        if let dictionary = object as? [String: Any] {
            for key in keys {
                if let value = dictionary[key] {
                    return value
                }
            }
            for value in dictionary.values {
                if let found = firstValue(forAnyKey: keys, in: value) {
                    return found
                }
            }
        } else if let array = object as? [Any] {
            for value in array {
                if let found = firstValue(forAnyKey: keys, in: value) {
                    return found
                }
            }
        }
        return nil
    }

    private func usageSummary(id: String, title: String, multiplier: Double, requestDivisor: Double) -> UsageSummary {
        let spend = totalSpendToday * multiplier
        let tokens = providers.reduce(0) { $0 + ($1.todayTokenCount > 0 ? $1.todayTokenCount * multiplier : $1.burnRatePerHour * 24 * multiplier) }
        let requests = providers.reduce(0) { $0 + Int(Double($1.knownTodayRequestCount ?? 0) * multiplier / requestDivisor) }
        return UsageSummary(id: id, title: title, spend: spend, tokens: tokens, requests: requests, projectedSpend: spend * 1.12)
    }

    private func statusRank(_ status: UsageStatus) -> Int {
        switch status {
        case .healthy: 0
        case .warning: 1
        case .critical: 2
        }
    }

}

private struct SmartRoutingCandidate {
    var providerID: String
    var model: String
    var sourceRank: Int
}

private struct ScoredSmartRoutingCandidate {
    var candidate: SmartRoutingCandidate
    var score: Double
    var route: SmartRoutingRouteStats?
    var estimatedCost: Double
}

private extension PolicyEvaluationInput {
    var hasTransientWorkspacePolicyFields: Bool {
        allowedProviderIDs != nil ||
            blockedModels != nil ||
            dailyBudget != nil ||
            monthlyBudget != nil ||
            maxEstimatedRunCost != nil ||
            requireCompanyKey != nil ||
            workspaceName != nil ||
            workspacePath != nil ||
            preferredProviderID != nil ||
            preferredModel != nil
    }
}

extension Notification.Name {
    static let tokenBarStateDidChange = Notification.Name("TokenBarStateDidChange")
}

extension JSONEncoder {
    static var tokenBar: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}

extension JSONDecoder {
    static var tokenBar: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
