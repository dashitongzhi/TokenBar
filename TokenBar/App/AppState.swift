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

    @Published var selectedProviderID: String {
        didSet { savePreferencesAndNotify() }
    }

    @Published var selectedMainSection: MainSection {
        didSet { savePreferencesAndNotify() }
    }

    @Published var selectedWorkspaceID: String {
        didSet {
            rebuildPolicyInput()
            savePreferencesAndNotify()
        }
    }

    @Published var selectedAgent: AgentProvider {
        didSet {
            rebuildPolicyInput()
            savePreferencesAndNotify()
        }
    }

    @Published var selectedModel: String {
        didSet {
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
        agent: .claudeCode,
        workspaceID: "ship",
        providerID: "anthropic",
        model: "claude-opus",
        estimatedCost: 1.2,
        estimatedTokens: 120_000,
        intent: "code"
    )
    @Published private(set) var currentDecision = PolicyDecision(
        timestamp: .now,
        status: .warn,
        agent: .claudeCode,
        workspaceID: "ship",
        workspaceName: "Ship Client",
        providerID: "anthropic",
        model: "claude-opus",
        estimatedCost: 1.2,
        projectedDailySpend: 5.9,
        reasons: ["Workspace budget is close to the daily limit."],
        recommendation: "Use Sonnet or split the run before continuing.",
        fallbackProviderID: "openrouter"
    )
    @Published private(set) var recentDecisions: [PolicyDecision] = []
    @Published private(set) var auditEvents: [AuditEvent] = []
    @Published private(set) var lastRefresh: Date = .now
    @Published private(set) var isRefreshingUsage = false
    @Published private(set) var localAPIStatus: LocalAPIStatus = .stopped

    private let preferencesStore = AppPreferencesStore()
    private let providerStore = ProviderUsageStore()
    private let localAgentUsageLedgerStore = LocalAgentUsageLedgerStore()
    private let openAIUsageService = OpenAIUsageService()
    private let anthropicUsageService = AnthropicUsageService()
    private let openRouterCreditsService = OpenRouterCreditsService()
    private let codexUsageService = CodexUsageService()
    private let miniMaxUsageService = MiniMaxUsageService()
    private let ccSwitchUsageService = CCSwitchUsageService()

    private init() {
        let savedPreferences = preferencesStore.load()
        language = savedPreferences.language
        statusBarContent = savedPreferences.statusBarContent
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

        providers = providerStore.load(defaults: AppSeedData.providers())
        workspacePolicies = AppSeedData.workspacePolicies()
        auditEvents = AppSeedData.auditEvents()
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
        sessionSpend + estimatedRunCost
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
                detail: "MiniMax access verification uses the built-in Anthropic-compatible base URL https://api.minimaxi.com/anthropic and requires MINIMAX_API_KEY in Keychain or the app environment.",
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

    func evaluatePolicy(input: PolicyEvaluationInput, shouldRecord: Bool = true) -> PolicyDecision {
        let decision = PolicyEngine.evaluate(
            input: input,
            workspaces: workspacePolicies,
            selectedWorkspace: selectedWorkspace,
            providers: providers,
            projectedSessionSpend: projectedSessionSpend,
            sessionBudget: sessionBudget
        )

        if shouldRecord {
            recentDecisions.insert(decision, at: 0)
            if recentDecisions.count > 20 {
                recentDecisions.removeLast(recentDecisions.count - 20)
            }
            addAudit(provider: input.agent.displayName, action: "policy.\(decision.status.rawValue)", detail: "\(decision.workspaceName) · \(input.model) · $\(formatMoney(input.estimatedCost))")
        }

        return decision
    }

    func policyJSON() -> Data {
        LocalAPIPayloadBuilder.policyJSON(currentDecision: currentDecision, workspacePolicies: workspacePolicies)
    }

    func policyDecisionJSON(input: PolicyEvaluationInput) -> Data {
        let decision = evaluatePolicy(input: input)
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
            return "\(selectedWorkspace?.name ?? "Workspace") $\(formatMoney(selectedWorkspace?.spendToday ?? 0))"
        case .totalSpend:
            return "$\(formatMoney(totalSpendMonth))"
        case .sessionBudget:
            return "$\(formatMoney(sessionSpend)) / $\(formatMoney(sessionBudget))"
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
            selectedAppIcon: selectedAppIcon
        ))
        notifyStatusBarUpdate()
    }

    private func notifyStatusBarUpdate() {
        NotificationCenter.default.post(name: .tokenBarStateDidChange, object: self)
    }

    private func addAudit(provider: String, action: String, detail: String) {
        auditEvents.insert(AuditEvent(timestamp: .now, provider: provider, action: action, detail: detail), at: 0)
        if auditEvents.count > 30 {
            auditEvents.removeLast(auditEvents.count - 30)
        }
    }

    private func persistProviders() {
        providerStore.save(providers)
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
            let secondary = snapshot.secondaryUsedPercent.map { ", 7-day \(Int($0))%" } ?? ""
            addAudit(provider: "Codex", action: "quota.live", detail: "Fetched Codex quota: 5-hour \(Int(snapshot.primaryUsedPercent))%\(secondary)")
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
                providers[index].sourceDetail = "\(providers[index].sourceDescription) MiniMax API verification also succeeded with \(snapshot.modelCount) visible models at \(MiniMaxUsageSnapshot.anthropicBaseURL)."
                providers[index].sourceUpdatedAt = snapshot.fetchedAt
            }
            addAudit(provider: "MiniMax", action: "access.live", detail: "Verified MiniMax access with \(snapshot.modelCount) visible models")
        case .unavailable(let detail):
            if providers[index].sourceKind != .ccSwitch {
                providers[index].markSource(.liveUnavailable, detail: detail, clearUsage: true)
            }
            addAudit(provider: "MiniMax", action: "access.needs_key", detail: "MiniMax access refresh skipped because no API key is available")
        case .failure(let detail):
            if providers[index].sourceKind != .ccSwitch {
                providers[index].markSource(.error, detail: detail)
            }
            addAudit(provider: "MiniMax", action: "access.error", detail: detail)
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
            unit: "models",
            spendToday: 0,
            spendMonth: 0,
            resetHours: 24 * 30,
            dataSource: .liveUnavailable,
            sourceDetail: "MiniMax access verification uses the built-in Anthropic-compatible base URL https://api.minimaxi.com/anthropic and requires MINIMAX_API_KEY in Keychain or the app environment."
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
        persistProviders()
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
                dailyBudget: input.dailyBudget ?? 8,
                monthlyBudget: input.monthlyBudget ?? 160,
                spendToday: 0,
                spendMonth: 0,
                allowedProviderIDs: input.allowedProviderIDs ?? allowedProviderIDs,
                blockedModels: input.blockedModels ?? [],
                maxEstimatedRunCost: input.maxEstimatedRunCost ?? 1.5,
                requireCompanyKey: input.requireCompanyKey ?? false
            ))
        }

        return workspaceID
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
        if model.contains("gpt") || model.contains("o3") || model.contains("o4") { return "openai" }
        switch agent {
        case .claudeCode:
            return "anthropic"
        case .codex:
            return "codex"
        default:
            return selectedProviderID
        }
    }

    private func defaultAgent(providerID: String) -> AgentProvider {
        providerID == "anthropic" ? .claudeCode : .custom
    }

    private func normalizedModel(_ model: String?, providerID: String) -> String {
        let value = model?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if value.isEmpty == false { return value }
        return providerID == "anthropic" ? "claude-sonnet" : "unspecified"
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
            providerID: "anthropic",
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
