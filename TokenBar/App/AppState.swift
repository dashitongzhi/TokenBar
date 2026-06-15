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
    private let openAIUsageService = OpenAIUsageService()
    private let anthropicUsageService = AnthropicUsageService()
    private let openRouterCreditsService = OpenRouterCreditsService()

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
        providers.filter(\.isLive).count
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
            apply(
                openAIResult: await openAIResult,
                anthropicResult: await anthropicResult,
                openRouterResult: await openRouterResult
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
        NSApp.applicationIconImage = image
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
        openRouterResult: OpenRouterCreditsRefreshResult
    ) {
        defer {
            lastRefresh = .now
            isRefreshingUsage = false
            currentDecision = evaluatePolicy(input: currentPolicyInput, shouldRecord: false)
            persistProviders()
            NotificationService.shared.notifyIfNeeded(appState: self)
            notifyStatusBarUpdate()
        }

        applyOpenAIResult(openAIResult)
        applyAnthropicResult(anthropicResult)
        applyOpenRouterResult(openRouterResult)
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
