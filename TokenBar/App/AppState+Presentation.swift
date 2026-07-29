import AppKit
import Foundation

@MainActor
extension AppState {
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
                return $0.status.rank > $1.status.rank
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
        UsageSummary(
            id: "daily",
            title: localized("daily"),
            spend: totalSpendToday,
            tokens: providers.reduce(0) { $0 + $1.todayTokenCount },
            requests: providers.reduce(0) { $0 + ($1.knownTodayRequestCount ?? 0) },
            projectedSpend: 0
        )
    }

    var weeklySummary: UsageSummary {
        // TokenBar does not persist a seven-day ledger yet. Keep unavailable
        // values empty instead of presenting extrapolated daily figures as facts.
        UsageSummary(id: "weekly", title: localized("weekly"), spend: 0, tokens: 0, requests: 0, projectedSpend: 0)
    }

    var monthlySummary: UsageSummary {
        UsageSummary(
            id: "monthly",
            title: localized("monthly"),
            spend: totalSpendMonth,
            tokens: modelUsageRollups.reduce(0) { $0 + $1.tokensMonth },
            requests: providers.reduce(0) { $0 + ($1.knownRequestCount ?? 0) },
            projectedSpend: 0
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
        case .disabled: localized("localAPIDisabled")
        case .starting: localized("localAPIStarting")
        case .running: localized("localAPIRunning")
        case .stopped: localized("localAPIStopped")
        case .failed: localized("localAPIFailed")
        }
    }

    var localAPIStatusDetail: String {
        switch localAPIStatus {
        case .disabled: localized("localAPIDisabledDetail")
        case .starting(let port): String(format: localized("localAPIStartingDetail"), port)
        case .running(let port): String(format: localized("localAPIRunningDetail"), port)
        case .stopped: localized("localAPIStoppedDetail")
        case .failed(let message): message.isEmpty ? localized("localAPIFailedDetail") : message
        }
    }

    var localAPISummaryValue: String {
        switch localAPIStatus {
        case .running(let port), .starting(let port): "\(port)"
        case .disabled: localized("off")
        case .stopped: localized("stopped")
        case .failed: localized("failed")
        }
    }

    func setLocalAPIStatus(_ status: LocalAPIStatus) {
        guard localAPIStatus != status else { return }
        localAPIStatus = status
        notifyStatusBarUpdate()
    }

    func statusBarText() -> String {
        switch statusBarContent {
        case .iconOnly: return ""
        case .customText: return customStatusText.isEmpty ? "TokenBar" : customStatusText
        case .guardDecision: return "\(currentDecision.status.rawValue.uppercased()) \(currentDecision.workspaceName)"
        case .activeWorkspace:
            guard let selectedWorkspace else { return "Workspace" }
            return selectedWorkspace.dailyBudget > 0
                ? "\(selectedWorkspace.name) $\(formatMoney(selectedWorkspace.spendToday))"
                : selectedWorkspace.name
        case .totalSpend: return totalSpendMonth > 0 ? "$\(formatMoney(totalSpendMonth))" : "TokenBar"
        case .sessionBudget: return sessionBudget > 0 ? "$\(formatMoney(sessionSpend)) / $\(formatMoney(sessionBudget))" : "TokenBar"
        }
    }

    func statusBarSymbolName() -> String {
        switch statusBarContent {
        case .guardDecision: return currentDecision.status.symbolName
        case .activeWorkspace: return "folder.badge.gearshape"
        case .sessionBudget: return budgetStatus.symbolName
        case .totalSpend: return mostUrgentProvider?.status.symbolName ?? "chart.line.uptrend.xyaxis"
        case .customText: return "sparkles"
        case .iconOnly: return selectedProvider?.status.symbolName ?? "chart.bar.fill"
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
            if let alert = urgent.displayHealthAlert {
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
        if seconds < 3600 { return "\(Int(seconds / 60))m" }
        if seconds < 86_400 { return "\(Int(seconds / 3600))h" }
        return "\(Int(seconds / 86_400))d"
    }

}
