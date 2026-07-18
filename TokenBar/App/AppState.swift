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
        projectedMonthlySpend: 0,
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
    private let localUsageIngestionModule = LocalUsageIngestionModule()
    private let smartRoutingLedgerStore = SmartRoutingLedgerStore()
    private let agentModelConfigurationService = AgentModelConfigurationService()
    private let providerModelCatalogService = ProviderModelCatalogService()
    private let providerRefreshModule = ProviderRefreshModule()
    private let smartRoutingRecommender = SmartRoutingRecommender()
    private let ccSwitchUsageService = CCSwitchUsageService()
    private var hasExplicitSelectedProviderPreference = false
    private var hasExplicitSelectedWorkspacePreference = false
    private var hasExplicitSelectedAgentPreference = false
    private var hasExplicitSelectedModelPreference = false
    private var isApplyingInferredSelections = false
    #if DEBUG
    private var isPersistenceSuppressedForVerification = false
    #endif

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
        mergeModelUsageRollups(localUsageIngestionModule.loadModelUsageRollups())
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
            let outcome = await providerRefreshModule.refresh(providers: providers)
            applyProviderRefreshOutcome(outcome)
        }
    }

    private func applyProviderRefreshOutcome(_ outcome: ProviderRefreshOutcome) {
        providers = outcome.providers
        for audit in outcome.audits {
            addAudit(provider: audit.provider, action: audit.action, detail: audit.detail)
        }
        lastRefresh = .now
        isRefreshingUsage = false
        currentDecision = evaluatePolicy(input: currentPolicyInput, shouldRecord: false)
        persistProviders()
        if CommandLine.arguments.contains("--tokenbar-verify-local-api") == false,
           CommandLine.arguments.contains("--tokenbar-verify-minimax-ccswitch-fallback-audit") == false {
            NotificationService.shared.notifyIfNeeded(appState: self)
        }
        notifyStatusBarUpdate()
    }

    #if DEBUG
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
    #endif

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
        normalizeWorkspaceSpendBuckets()
        let activeWorkspacePolicies = evaluationWorkspacePolicies ?? workspacePolicies
        var decision = PolicyEngine.evaluate(
            input: input,
            workspaces: activeWorkspacePolicies,
            selectedWorkspace: selectedWorkspace,
            providers: providers,
            projectedSessionSpend: sessionSpend + input.estimatedCost,
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
        guard let recommendation = smartRoutingRecommender.recommendation(for: SmartRoutingContext(
            input: input,
            workspacePolicies: evaluationWorkspacePolicies,
            selectedWorkspace: selectedWorkspace,
            providers: providers,
            modelUsageRollups: modelUsageRollups,
            modelCatalogItems: modelCatalogItems,
            stats: smartRoutingLedgerStore.stats(),
            projectedSessionSpend: sessionSpend + input.estimatedCost,
            sessionBudget: sessionBudget,
            fallbackProviderID: selectedProviderID
        )) else {
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

    func policyJSON() throws -> Data {
        normalizeWorkspaceSpendBuckets()
        currentDecision = evaluatePolicy(input: currentPolicyInput, shouldRecord: false)
        return try LocalAPIPayloadBuilder.policyJSON(currentDecision: currentDecision, workspacePolicies: workspacePolicies)
    }

    func policyDecisionJSON(input: PolicyEvaluationInput) throws -> Data {
        var verifiedInput = input
        // The local API cannot prove which credential an external agent will
        // use. Do not promote a Keychain credential into request provenance.
        verifiedInput.keySource = nil
        normalizeWorkspaceSpendBuckets()
        let transientWorkspacePolicies = workspacePoliciesForPolicyEvaluation(verifiedInput)
        let decision = evaluatePolicy(input: verifiedInput, shouldRecord: false, workspacePolicies: transientWorkspacePolicies)
        currentDecision = decision
        return try LocalAPIPayloadBuilder.policyDecisionJSON(decision)
    }

    func ingestLocalAgentUsageJSON(input: LocalAgentUsageIngest) throws -> Data {
        let snapshot = applyLocalAgentUsage(input)
        let policyInput = PolicyEvaluationInput(
            agent: snapshot.agent,
            workspaceID: snapshot.workspaceID ?? selectedWorkspaceID,
            providerID: snapshot.providerID,
            model: snapshot.model,
            // The delta has already been applied to the workspace total. Passing it
            // again here would make the returned policy decision count it twice.
            estimatedCost: 0,
            estimatedTokens: Int(snapshot.tokenDelta),
            intent: "local_usage_ingest"
        )
        currentDecision = evaluatePolicy(input: policyInput, shouldRecord: false)
        return try LocalAPIPayloadBuilder.localAgentUsageJSON(snapshot: snapshot, decision: currentDecision)
    }

    func ingestClaudeStatuslineJSON(data: Data) throws -> Data {
        guard let input = ClaudeStatuslineParser.parse(data) else {
            return Data(#"{"error":"invalid_claude_statusline_input"}"#.utf8)
        }
        return try ingestLocalAgentUsageJSON(input: input)
    }

    func recordSmartRoutingRunJSON(input: SmartRoutingRunInput) throws -> Data {
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
        return try LocalAPIPayloadBuilder.smartRoutingRunJSON(record: record)
    }

    func smartRoutingStatsJSON() throws -> Data {
        try LocalAPIPayloadBuilder.smartRoutingStatsJSON(snapshot: smartRoutingLedgerStore.stats())
    }

    func mcpSnapshotJSON(filteredProviderID: String? = nil) throws -> Data {
        try LocalAPIPayloadBuilder.mcpSnapshotJSON(providers: providers, filteredProviderID: filteredProviderID)
    }

    func paceJSON(providerID: String) throws -> Data {
        guard let provider = providers.first(where: { $0.id == providerID }) else {
            return Data(#"{"error":"provider_not_found"}"#.utf8)
        }
        return try LocalAPIPayloadBuilder.paceJSON(provider: provider, recommendation: insightText())
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
            selectedAgent = AgentProvider.defaultAgent(forProviderID: selectedProviderID)
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
        #if DEBUG
        guard isPersistenceSuppressedForVerification == false else { return }
        #endif
        auditEventStore.save(auditEvents)
    }

    private func persistProviders() {
        #if DEBUG
        guard isPersistenceSuppressedForVerification == false else { return }
        #endif
        providerStore.save(providers)
    }

    private func persistWorkspacePolicies() {
        #if DEBUG
        guard isPersistenceSuppressedForVerification == false else { return }
        #endif
        workspacePolicyStore.save(workspacePolicies)
    }

    @discardableResult
    private func normalizeWorkspaceSpendBuckets(now: Date = .now) -> Bool {
        var normalized = workspacePolicies
        var changed = false
        for index in normalized.indices {
            let didReset = normalized[index].resetExpiredSpendBuckets(now: now)
            changed = didReset || changed
        }
        guard changed else { return false }
        workspacePolicies = normalized
        persistWorkspacePolicies()
        return true
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

    private func applyLocalAgentUsage(_ input: LocalAgentUsageIngest) -> LocalAgentUsageAppliedSnapshot {
        let outcome = localUsageIngestionModule.ingest(
            input,
            providers: providers,
            workspacePolicies: workspacePolicies,
            selectedWorkspaceID: selectedWorkspaceID,
            selectedProviderID: selectedProviderID,
            sessionBudget: sessionBudget,
            sessionSpend: sessionSpend
        )
        providers = outcome.providers
        workspacePolicies = outcome.workspacePolicies
        sessionSpend = outcome.sessionSpend
        addAudit(provider: outcome.audit.provider, action: outcome.audit.action, detail: outcome.audit.detail)
        mergeModelUsageRollups(outcome.modelUsageRollups)
        persistProviders()
        persistWorkspacePolicies()
        notifyStatusBarUpdate()
        return outcome.snapshot
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
            evaluationWorkspacePolicies[index].maxEstimatedTokens = input.maxEstimatedTokens ?? evaluationWorkspacePolicies[index].maxEstimatedTokens
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
                maxEstimatedTokens: input.maxEstimatedTokens ?? 0,
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
        if let seed = AppSeedData.providers().first(where: { $0.id == providerID }) {
            let seedOrder = AppSeedData.providers().firstIndex(where: { $0.id == providerID }) ?? providers.count
            providers.insert(seed, at: min(seedOrder, providers.count))
            return
        }
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

    private func titleFromWorkspaceID(_ value: String) -> String {
        let words = value.replacingOccurrences(of: "_", with: "-").split(separator: "-")
        guard words.isEmpty == false else { return "Workspace" }
        return words.map { word in
            word.prefix(1).uppercased() + word.dropFirst()
        }.joined(separator: " ")
    }

    private func reloadModelUsageRollups() {
        mergeModelUsageRollups(localUsageIngestionModule.loadModelUsageRollups())
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

    #if DEBUG
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
                providers: [
                    CCSwitchProviderUsageSnapshot(
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
                        quotaWindows: [
                            CCSwitchQuotaWindow(
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
                            )
                        ],
                        history: [],
                        healthAlerts: [],
                        sourceDetail: "smoke: MiniMax quota from CC Switch provider key",
                        fetchedAt: now
                    )
                ],
                fetchedAt: now
            ))
        )

        guard let miniMaxProvider = providers.first(where: { $0.id == "minimax" }) else {
            throw MiniMaxCCSwitchFallbackAuditSmokeFailure("MiniMax provider was not present after app refresh apply.")
        }
        guard miniMaxProvider.sourceKind == .ccSwitch,
              miniMaxProvider.unit == "percent",
              miniMaxProvider.hasKnownQuotaLimit else {
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
    #endif

}
#if DEBUG
private struct MiniMaxCCSwitchFallbackAuditSmokeFailure: Error, CustomStringConvertible {
    var description: String

    init(_ description: String) {
        self.description = description
    }
}

#endif

private extension PolicyEvaluationInput {
    var hasTransientWorkspacePolicyFields: Bool {
        allowedProviderIDs != nil ||
            blockedModels != nil ||
            dailyBudget != nil ||
            monthlyBudget != nil ||
            maxEstimatedRunCost != nil ||
            maxEstimatedTokens != nil ||
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
