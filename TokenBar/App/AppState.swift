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
        didSet { savePreferencesAndNotify() }
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

    private let preferences = UserDefaults.standard
    private let storeURL: URL

    private init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? FileManager.default.temporaryDirectory
        let directory = support.appendingPathComponent("TokenBar", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        storeURL = directory.appendingPathComponent("providers.json")

        language = AppLanguage(rawValue: preferences.string(forKey: "language") ?? "") ?? .english
        statusBarContent = StatusBarContent(rawValue: preferences.string(forKey: "statusBarContent") ?? "") ?? .guardDecision
        selectedMainSection = MainSection(rawValue: preferences.string(forKey: "selectedMainSection") ?? "") ?? .guardrail
        selectedProviderID = preferences.string(forKey: "selectedProviderID") ?? "openai"
        selectedWorkspaceID = preferences.string(forKey: "selectedWorkspaceID") ?? "client-app"
        selectedAgent = AgentProvider(rawValue: preferences.string(forKey: "selectedAgent") ?? "") ?? .claudeCode
        selectedModel = preferences.string(forKey: "selectedModel") ?? "claude-opus"
        estimatedRunCost = preferences.object(forKey: "estimatedRunCost") as? Double ?? 1.2
        estimatedTokens = preferences.object(forKey: "estimatedTokens") as? Double ?? 120_000
        customStatusText = preferences.string(forKey: "customStatusText") ?? "TokenBar"
        sessionBudget = preferences.object(forKey: "sessionBudget") as? Double ?? 5
        sessionSpend = preferences.object(forKey: "sessionSpend") as? Double ?? 1.2
        focusModeEnabled = preferences.object(forKey: "focusModeEnabled") as? Bool ?? true
        localAPIEnabled = preferences.object(forKey: "localAPIEnabled") as? Bool ?? true
        selectedAppIcon = AppIconChoice(rawValue: preferences.string(forKey: "selectedAppIcon") ?? "") ?? .classic

        providers = Self.loadProviders(from: storeURL) ?? Self.seedProviders()
        workspacePolicies = Self.seedWorkspacePolicies()
        auditEvents = Self.seedAudit()
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
        providers.reduce(0) { $0 + $1.spendMonth }
    }

    var totalSpendToday: Double {
        providers.reduce(0) { $0 + $1.spendToday }
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
            requests: providers.reduce(0) { $0 + Int($1.current / max($1.limit, 1) * 1200) },
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

    func refreshAll() {
        for index in providers.indices {
            providers[index].simulateRefresh()
        }

        if focusModeEnabled {
            sessionSpend = min(sessionSpend + Double.random(in: 0.03...0.25), max(sessionBudget * 1.3, sessionBudget + 1))
        }
        for index in workspacePolicies.indices {
            workspacePolicies[index].spendToday = min(
                workspacePolicies[index].spendToday + Double.random(in: 0.05...0.45),
                max(workspacePolicies[index].dailyBudget * 1.2, workspacePolicies[index].dailyBudget + 0.5)
            )
            workspacePolicies[index].spendMonth += Double.random(in: 0.15...1.4)
        }
        currentDecision = evaluatePolicy(input: currentPolicyInput, shouldRecord: false)

        lastRefresh = .now
        addAudit(provider: localized("allProviders"), action: "refresh", detail: "Refreshed local usage and policy metadata")
        persistProviders()
        NotificationService.shared.notifyIfNeeded(appState: self)
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
        providers.append(Self.provider(
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
        let workspace = workspacePolicies.first { $0.id == input.workspaceID } ?? selectedWorkspace ?? workspacePolicies[0]
        let provider = providers.first { $0.id == input.providerID }
        let projectedDailySpend = workspace.spendToday + input.estimatedCost
        var status: PolicyDecisionStatus = .allow
        var reasons: [String] = []

        if workspace.allowedProviderIDs.contains(input.providerID) == false {
            status = .block
            reasons.append("Provider is not allowed for this workspace.")
        }

        if workspace.blockedModels.contains(where: { input.model.localizedCaseInsensitiveContains($0) }) {
            status = .block
            reasons.append("Model is blocked by the workspace policy.")
        }

        if input.estimatedCost > workspace.maxEstimatedRunCost {
            status = .block
            reasons.append("Estimated run cost is above the per-run cap.")
        }

        if workspace.requireCompanyKey && input.providerID == "openai" {
            status = .block
            reasons.append("Workspace requires a company-managed key.")
        }

        if projectedDailySpend >= workspace.dailyBudget {
            status = .block
            reasons.append("Projected daily spend would exceed the workspace budget.")
        } else if projectedDailySpend >= workspace.dailyBudget * 0.8 && status != .block {
            status = .warn
            reasons.append("Projected daily spend is close to the workspace budget.")
        }

        if let provider, provider.status == .critical && status != .block {
            status = .warn
            reasons.append("\(provider.name) is near its quota or reset window.")
        }

        if projectedSessionSpend >= sessionBudget && status != .block {
            status = .warn
            reasons.append("Current session budget will be tight after this run.")
        }

        if reasons.isEmpty {
            reasons.append("Workspace, provider, model, and budget are inside policy.")
        }

        let fallback = workspace.allowedProviderIDs.first { $0 != input.providerID }
        let recommendation: String
        switch status {
        case .allow:
            recommendation = "Continue with \(input.model). Keep the agent on this workspace policy."
        case .warn:
            recommendation = "Continue only if this run is necessary, or switch to \(fallbackName(fallback)) first."
        case .block:
            recommendation = "Stop this run. Switch provider/model or raise the workspace budget after review."
        }

        let decision = PolicyDecision(
            timestamp: .now,
            status: status,
            agent: input.agent,
            workspaceID: workspace.id,
            workspaceName: workspace.name,
            providerID: input.providerID,
            model: input.model,
            estimatedCost: input.estimatedCost,
            projectedDailySpend: projectedDailySpend,
            reasons: reasons,
            recommendation: recommendation,
            fallbackProviderID: fallback
        )

        if shouldRecord {
            recentDecisions.insert(decision, at: 0)
            if recentDecisions.count > 20 {
                recentDecisions.removeLast(recentDecisions.count - 20)
            }
            addAudit(provider: input.agent.displayName, action: "policy.\(status.rawValue)", detail: "\(workspace.name) · \(input.model) · $\(formatMoney(input.estimatedCost))")
        }

        return decision
    }

    func policyJSON() -> Data {
        let payload: [String: Any] = [
            "version": "1.0",
            "timestamp": ISO8601DateFormatter().string(from: Date()),
            "localOnly": true,
            "decision": policyDictionary(currentDecision),
            "workspaces": workspacePolicies.map { workspace in
                [
                    "id": workspace.id,
                    "name": workspace.name,
                    "pathHint": workspace.pathHint,
                    "dailyBudget": workspace.dailyBudget,
                    "spendToday": workspace.spendToday,
                    "allowedProviders": workspace.allowedProviderIDs,
                    "blockedModels": workspace.blockedModels,
                    "requireCompanyKey": workspace.requireCompanyKey
                ] as [String: Any]
            }
        ]
        return (try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])) ?? Data("{}".utf8)
    }

    func policyDecisionJSON(input: PolicyEvaluationInput) -> Data {
        let decision = evaluatePolicy(input: input)
        let payload: [String: Any] = [
            "version": "1.0",
            "timestamp": ISO8601DateFormatter().string(from: Date()),
            "localOnly": true,
            "decision": policyDictionary(decision)
        ]
        currentDecision = decision
        return (try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])) ?? Data("{}".utf8)
    }

    func mcpSnapshotJSON(filteredProviderID: String? = nil) -> Data {
        let selected = filteredProviderID.map { id in providers.filter { $0.id == id } } ?? providers
        let quotas = selected.map { provider in
            var metric: [String: Any] = [
                "name": provider.unit,
                "current": provider.current,
                "limit": provider.limit,
                "unit": provider.unit,
                "remaining": provider.remaining,
                "usageRatio": provider.usageRatio,
                "burnRatePerHour": provider.burnRatePerHour,
                "resetAt": ISO8601DateFormatter().string(from: provider.resetAt)
            ]
            metric["predictedExhaustion"] = provider.predictedExhaustion.map { ISO8601DateFormatter().string(from: $0) } ?? NSNull()
            return [
                "platform": provider.id,
                "displayName": provider.name,
                "status": provider.status.rawValue,
                "metrics": [metric]
            ] as [String: Any]
        }
        let payload: [String: Any] = [
            "version": "1.0",
            "timestamp": ISO8601DateFormatter().string(from: Date()),
            "localOnly": true,
            "quotas": quotas
        ]
        return (try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])) ?? Data("{}".utf8)
    }

    func paceJSON(providerID: String) -> Data {
        guard let provider = providers.first(where: { $0.id == providerID }) else {
            return Data(#"{"error":"provider_not_found"}"#.utf8)
        }
        let payload: [String: Any] = [
            "platform": provider.id,
            "displayName": provider.name,
            "status": provider.status.rawValue,
            "burnRatePerHour": provider.burnRatePerHour,
            "remaining": provider.remaining,
            "predictedExhaustion": provider.predictedExhaustion.map { ISO8601DateFormatter().string(from: $0) } ?? NSNull(),
            "recommendation": insightText()
        ]
        return (try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])) ?? Data("{}".utf8)
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
        preferences.set(language.rawValue, forKey: "language")
        preferences.set(selectedMainSection.rawValue, forKey: "selectedMainSection")
        preferences.set(statusBarContent.rawValue, forKey: "statusBarContent")
        preferences.set(selectedProviderID, forKey: "selectedProviderID")
        preferences.set(selectedWorkspaceID, forKey: "selectedWorkspaceID")
        preferences.set(selectedAgent.rawValue, forKey: "selectedAgent")
        preferences.set(selectedModel, forKey: "selectedModel")
        preferences.set(estimatedRunCost, forKey: "estimatedRunCost")
        preferences.set(estimatedTokens, forKey: "estimatedTokens")
        preferences.set(customStatusText, forKey: "customStatusText")
        preferences.set(sessionBudget, forKey: "sessionBudget")
        preferences.set(sessionSpend, forKey: "sessionSpend")
        preferences.set(focusModeEnabled, forKey: "focusModeEnabled")
        preferences.set(localAPIEnabled, forKey: "localAPIEnabled")
        preferences.set(selectedAppIcon.rawValue, forKey: "selectedAppIcon")
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
        guard let data = try? JSONEncoder.tokenBar.encode(providers) else { return }
        try? data.write(to: storeURL, options: [.atomic])
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

    private func fallbackName(_ providerID: String?) -> String {
        guard let providerID, let provider = providers.first(where: { $0.id == providerID }) else {
            return "a cheaper allowed provider"
        }
        return provider.name
    }

    private func policyDictionary(_ decision: PolicyDecision) -> [String: Any] {
        [
            "status": decision.status.rawValue,
            "agent": decision.agent.displayName,
            "workspace": [
                "id": decision.workspaceID,
                "name": decision.workspaceName
            ],
            "provider": decision.providerID,
            "model": decision.model,
            "estimatedCost": decision.estimatedCost,
            "projectedDailySpend": decision.projectedDailySpend,
            "reasons": decision.reasons,
            "recommendation": decision.recommendation,
            "fallbackProvider": decision.fallbackProviderID ?? NSNull(),
            "timestamp": ISO8601DateFormatter().string(from: decision.timestamp)
        ]
    }

    private func usageSummary(id: String, title: String, multiplier: Double, requestDivisor: Double) -> UsageSummary {
        let spend = totalSpendToday * multiplier
        let tokens = providers.reduce(0) { $0 + ($1.burnRatePerHour * 24 * multiplier) }
        let requests = providers.reduce(0) { $0 + Int(($1.current / max($1.limit, 1)) * 350 * multiplier / requestDivisor) }
        return UsageSummary(id: id, title: title, spend: spend, tokens: tokens, requests: requests, projectedSpend: spend * 1.12)
    }

    private func statusRank(_ status: UsageStatus) -> Int {
        switch status {
        case .healthy: 0
        case .warning: 1
        case .critical: 2
        }
    }

    private static func loadProviders(from url: URL) -> [ProviderUsage]? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder.tokenBar.decode([ProviderUsage].self, from: data)
    }

    private static func seedProviders() -> [ProviderUsage] {
        [
            provider(id: "openai", name: "OpenAI", category: "AI & API", symbol: "brain.head.profile", current: 6_820, limit: 10_000, unit: "tokens", spendToday: 4.18, spendMonth: 72.40, resetHours: 42),
            provider(id: "anthropic", name: "Anthropic", category: "AI & API", symbol: "sparkles", current: 8_870, limit: 10_000, unit: "tokens", spendToday: 7.32, spendMonth: 116.22, resetHours: 18),
            provider(id: "cursor", name: "Cursor", category: "AI Tool", symbol: "cursorarrow.motionlines", current: 58, limit: 100, unit: "requests", spendToday: 1.80, spendMonth: 24.00, resetHours: 9),
            provider(id: "github", name: "GitHub Copilot", category: "Developer Tool", symbol: "chevron.left.forwardslash.chevron.right", current: 41, limit: 100, unit: "requests", spendToday: 0.62, spendMonth: 10.00, resetHours: 26),
            provider(id: "stripe", name: "Stripe", category: "Payments", symbol: "creditcard.fill", current: 1_250, limit: 5_000, unit: "events", spendToday: 0.40, spendMonth: 18.10, resetHours: 120)
        ]
    }

    private static func seedWorkspacePolicies() -> [WorkspacePolicy] {
        [
            WorkspacePolicy(
                id: "client-app",
                name: "Client App",
                pathHint: "~/project/client-app",
                client: "Acme",
                dailyBudget: 6,
                monthlyBudget: 180,
                spendToday: 4.7,
                spendMonth: 96.2,
                allowedProviderIDs: ["anthropic", "openrouter", "github"],
                blockedModels: ["opus"],
                maxEstimatedRunCost: 1.5,
                requireCompanyKey: true
            ),
            WorkspacePolicy(
                id: "personal-lab",
                name: "Personal Lab",
                pathHint: "~/project/lab",
                client: "Personal",
                dailyBudget: 3,
                monthlyBudget: 60,
                spendToday: 0.8,
                spendMonth: 18.4,
                allowedProviderIDs: ["openai", "openrouter", "deepseek", "cursor"],
                blockedModels: [],
                maxEstimatedRunCost: 0.75,
                requireCompanyKey: false
            ),
            WorkspacePolicy(
                id: "production-fix",
                name: "Production Fix",
                pathHint: "~/work/prod",
                client: "Ops",
                dailyBudget: 12,
                monthlyBudget: 300,
                spendToday: 2.1,
                spendMonth: 144.9,
                allowedProviderIDs: ["anthropic", "openai", "github"],
                blockedModels: [],
                maxEstimatedRunCost: 3,
                requireCompanyKey: true
            )
        ]
    }

    private static func provider(id: String, name: String, category: String, symbol: String, current: Double, limit: Double, unit: String, spendToday: Double, spendMonth: Double, resetHours: Double) -> ProviderUsage {
        let now = Date()
        let history = (0..<8).map { offset in
            UsagePoint(timestamp: now.addingTimeInterval(Double(offset - 7) * 3600), value: max(current - Double(7 - offset) * Double.random(in: 24...120), 0))
        }
        return ProviderUsage(
            id: id,
            name: name,
            category: category,
            symbolName: symbol,
            current: current,
            limit: limit,
            unit: unit,
            spendToday: spendToday,
            spendMonth: spendMonth,
            resetAt: now.addingTimeInterval(resetHours * 3600),
            lastUpdated: now,
            history: history
        )
    }

    private static func seedAudit() -> [AuditEvent] {
        [
            AuditEvent(timestamp: .now.addingTimeInterval(-420), provider: "OpenAI", action: "usage.read", detail: "Read aggregate billing metadata"),
            AuditEvent(timestamp: .now.addingTimeInterval(-900), provider: "Anthropic", action: "usage.read", detail: "Read token counts and reset windows"),
            AuditEvent(timestamp: .now.addingTimeInterval(-1400), provider: "Keychain", action: "key.lookup", detail: "Looked up provider credential handle only")
        ]
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
