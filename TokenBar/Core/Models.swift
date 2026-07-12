import Foundation

enum AppLanguage: String, CaseIterable, Identifiable, Codable {
    case english = "en"
    case chinese = "zh-Hans"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .english: "English"
        case .chinese: "中文"
        }
    }
}

enum StatusBarContent: String, CaseIterable, Identifiable, Codable {
    case guardDecision
    case activeWorkspace
    case sessionBudget
    case totalSpend
    case customText
    case iconOnly

    var id: String { rawValue }

    func title(language: AppLanguage) -> String {
        switch (self, language) {
        case (.guardDecision, .english): "Guard Decision"
        case (.activeWorkspace, .english): "Active Workspace"
        case (.totalSpend, .english): "Total Spend"
        case (.sessionBudget, .english): "Session Budget"
        case (.customText, .english): "Custom Text"
        case (.iconOnly, .english): "Icon Only"
        case (.guardDecision, .chinese): "守卫决策"
        case (.activeWorkspace, .chinese): "当前工作区"
        case (.totalSpend, .chinese): "总花费"
        case (.sessionBudget, .chinese): "会话预算"
        case (.customText, .chinese): "自定义文本"
        case (.iconOnly, .chinese): "仅图标"
        }
    }
}

enum AppIconChoice: String, CaseIterable, Identifiable, Codable {
    case classic
    case glass
    case frost
    case midnight

    var id: String { rawValue }

    var assetName: String {
        switch self {
        case .classic: "AppIconDefault"
        case .glass: "AppIconGlass"
        case .frost: "AppIconFrost"
        case .midnight: "AppIconMidnight"
        }
    }

    func title(language: AppLanguage) -> String {
        switch (self, language) {
        case (.classic, .english): "Classic"
        case (.glass, .english): "Glass"
        case (.frost, .english): "Frost"
        case (.midnight, .english): "Midnight"
        case (.classic, .chinese): "经典"
        case (.glass, .chinese): "玻璃"
        case (.frost, .chinese): "霜白"
        case (.midnight, .chinese): "暗夜"
        }
    }
}

enum MainSection: String, CaseIterable, Identifiable, Codable {
    case guardrail
    case workspaces
    case summary
    case integrations

    var id: String { rawValue }

    func title(language: AppLanguage) -> String {
        switch (self, language) {
        case (.guardrail, .english): "Guard"
        case (.workspaces, .english): "Workspaces"
        case (.summary, .english): "Summary"
        case (.integrations, .english): "Integrations"
        case (.guardrail, .chinese): "守卫"
        case (.workspaces, .chinese): "工作区"
        case (.summary, .chinese): "汇总"
        case (.integrations, .chinese): "集成"
        }
    }

    var symbolName: String {
        switch self {
        case .guardrail: "shield.lefthalf.filled"
        case .workspaces: "folder.badge.gearshape"
        case .summary: "chart.xyaxis.line"
        case .integrations: "network"
        }
    }
}

enum RoutingMode: String, CaseIterable, Identifiable, Codable {
    case guardOnly
    case smartRouting

    var id: String { rawValue }

    func title(language: AppLanguage) -> String {
        switch (self, language) {
        case (.guardOnly, .english): "Guard Only"
        case (.smartRouting, .english): "Smart Routing"
        case (.guardOnly, .chinese): "仅守卫"
        case (.smartRouting, .chinese): "智能路由"
        }
    }

    var symbolName: String {
        switch self {
        case .guardOnly: "shield"
        case .smartRouting: "point.3.connected.trianglepath.dotted"
        }
    }
}

enum UsageStatus: String, Codable {
    case healthy
    case warning
    case critical
}

enum LocalAPIStatus: Equatable {
    case disabled
    case starting(port: UInt16)
    case running(port: UInt16)
    case stopped
    case failed(String)
}

enum UsageDataSource: String, Codable {
    case live
    case localAgent
    case ccSwitch
    case liveUnavailable
    case unsupported
    case error
}

struct ProviderHealthAlert: Codable, Equatable, Identifiable {
    var status: UsageStatus
    var title: String
    var detail: String

    var id: String {
        [status.rawValue, title, detail].joined(separator: "|")
    }
}

enum ModelUsageSource: String, Codable {
    case localAgent
    case configured
}

enum ModelCatalogSource: String, Codable {
    case providerAPI
    case ccSwitchConfig
    case localAgentConfig
}

struct ModelCatalogItem: Identifiable, Codable, Equatable {
    var providerID: String
    var modelID: String
    var displayName: String
    var source: ModelCatalogSource
    var baseURL: String?
    var configPath: String?
    var fetchedAt: Date

    var id: String {
        [providerID, modelID.lowercased(), source.rawValue, baseURL ?? "", configPath ?? ""].joined(separator: "|")
    }
}

struct UsagePoint: Identifiable, Codable, Equatable {
    var id = UUID()
    var timestamp: Date
    var value: Double
}

struct LocalAgentUsageSummary: Codable, Equatable {
    var tokensToday: Double
    var requestCountToday: Int
    var requestCountMonth: Int
    var spendToday: Double
    var spendMonth: Double
    var lastUpdated: Date
    var sourceDetail: String
}

struct ProviderUsage: Identifiable, Codable, Equatable {
    var id: String
    var name: String
    var category: String
    var symbolName: String
    var current: Double
    var limit: Double
    var unit: String
    var spendToday: Double
    var spendMonth: Double
    var resetAt: Date
    var lastUpdated: Date
    var history: [UsagePoint]
    var dataSource: UsageDataSource?
    var sourceDetail: String?
    var sourceUpdatedAt: Date?
    var tokensToday: Double?
    var requestCountToday: Int?
    var requestCountMonth: Int?
    var currencyCode: String?
    var quotaLimitKnown: Bool?
    var requestCountKnown: Bool?
    var spendTodayKnown: Bool? = nil
    var spendMonthKnown: Bool? = nil
    var healthAlerts: [ProviderHealthAlert]? = nil
    var localAgentUsage: LocalAgentUsageSummary? = nil

    var usageRatio: Double {
        guard hasKnownQuotaLimit else { return 0 }
        return min(max(current / limit, 0), 1.5)
    }

    var remaining: Double {
        knownRemaining ?? 0
    }

    var knownRemaining: Double? {
        guard hasKnownQuotaLimit else { return nil }
        return max(limit - current, 0)
    }

    var burnRatePerHour: Double {
        let sorted = history.sorted { $0.timestamp < $1.timestamp }
        guard sorted.count >= 2, let first = sorted.first, let last = sorted.last else { return 0 }
        let deltaValue = last.value - first.value
        let hours = max(last.timestamp.timeIntervalSince(first.timestamp) / 3600, 0.01)
        return max(deltaValue / hours, 0)
    }

    var predictedExhaustion: Date? {
        let rate = burnRatePerHour
        guard let knownRemaining, rate > 0, knownRemaining > 0 else { return nil }
        return Date().addingTimeInterval((remaining / rate) * 3600)
    }

    var hasKnownQuotaLimit: Bool {
        (quotaLimitKnown ?? true) && limit > 0
    }

    var requestCount: Int {
        requestCountMonth ?? 0
    }

    var todayRequestCount: Int {
        requestCountToday ?? 0
    }

    var hasKnownRequestCount: Bool {
        requestCountKnown ?? (requestCountMonth != nil || requestCountToday != nil)
    }

    var knownRequestCount: Int? {
        hasKnownRequestCount ? requestCount : nil
    }

    var knownTodayRequestCount: Int? {
        hasKnownRequestCount ? todayRequestCount : nil
    }

    var todayTokenCount: Double {
        tokensToday ?? 0
    }

    var displayCurrency: String {
        let value = (currencyCode ?? "USD").trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? "USD" : value.uppercased()
    }

    var hasKnownSpendToday: Bool {
        spendTodayKnown ?? true
    }

    var hasKnownSpendMonth: Bool {
        spendMonthKnown ?? true
    }

    var status: UsageStatus {
        let quotaStatus: UsageStatus
        if let predictedExhaustion {
            let hours = predictedExhaustion.timeIntervalSinceNow / 3600
            if hours < 6 {
                quotaStatus = .critical
            } else if hours < 24 {
                quotaStatus = .warning
            } else {
                quotaStatus = .healthy
            }
        } else if usageRatio >= 0.9 {
            quotaStatus = .critical
        } else if usageRatio >= 0.7 {
            quotaStatus = .warning
        } else {
            quotaStatus = .healthy
        }

        return activeHealthAlerts.reduce(quotaStatus) { current, alert in
            alert.status.rank > current.rank ? alert.status : current
        }
    }

    var activeHealthAlerts: [ProviderHealthAlert] {
        healthAlerts ?? []
    }

    var primaryHealthAlert: ProviderHealthAlert? {
        activeHealthAlerts.sorted {
            if $0.status != $1.status {
                return $0.status.rank > $1.status.rank
            }
            return $0.title < $1.title
        }.first
    }

    var displayHealthAlert: ProviderHealthAlert? {
        guard let alert = primaryHealthAlert, alert.status.rank >= status.rank else {
            return nil
        }
        return alert
    }

    var sourceKind: UsageDataSource {
        dataSource ?? .unsupported
    }

    var sourceDescription: String {
        sourceDetail ?? ""
    }

    var isLive: Bool {
        sourceKind == .live
    }

    var isUsageConnected: Bool {
        sourceKind == .live || sourceKind == .localAgent
    }

    mutating func apply(snapshot: OpenAIUsageSnapshot) {
        current = snapshot.tokenTotal
        limit = 0
        unit = "tokens"
        tokensToday = snapshot.tokenToday
        requestCountToday = snapshot.requestCountToday
        requestCountMonth = snapshot.requestCountMonth
        currencyCode = snapshot.currency.uppercased()
        quotaLimitKnown = false
        requestCountKnown = true
        spendTodayKnown = true
        spendMonthKnown = true
        spendToday = snapshot.spendToday
        spendMonth = snapshot.spendMonth
        resetAt = snapshot.resetAt
        lastUpdated = snapshot.fetchedAt
        history = snapshot.history.isEmpty ? [UsagePoint(timestamp: snapshot.fetchedAt, value: snapshot.tokenTotal)] : snapshot.history
        dataSource = .live
        sourceUpdatedAt = snapshot.fetchedAt
        healthAlerts = nil
        sourceDetail = "OpenAI organization usage and cost APIs. \(snapshot.requestCountMonth) requests this month, \(snapshot.currency.uppercased()) costs. Organization quota limits stay in the OpenAI console."
    }

    mutating func apply(snapshot: AnthropicUsageSnapshot) {
        current = snapshot.tokenTotal
        limit = 0
        unit = "tokens"
        tokensToday = snapshot.tokenToday
        requestCountToday = snapshot.requestCountToday
        requestCountMonth = snapshot.requestCountMonth
        currencyCode = snapshot.currency.uppercased()
        quotaLimitKnown = false
        requestCountKnown = false
        spendTodayKnown = true
        spendMonthKnown = true
        spendToday = snapshot.spendToday
        spendMonth = snapshot.spendMonth
        resetAt = snapshot.resetAt
        lastUpdated = snapshot.fetchedAt
        history = snapshot.history.isEmpty ? [UsagePoint(timestamp: snapshot.fetchedAt, value: snapshot.tokenTotal)] : snapshot.history
        dataSource = .live
        sourceUpdatedAt = snapshot.fetchedAt
        healthAlerts = nil
        sourceDetail = "Anthropic Usage and Cost Admin API. Token and cost data are live; message request counts and console spend limits stay outside this public Admin API."
    }

    mutating func apply(snapshot: OpenRouterCreditsSnapshot) {
        current = snapshot.totalUsage
        limit = snapshot.totalCredits
        unit = "credits"
        tokensToday = 0
        requestCountToday = 0
        requestCountMonth = 0
        currencyCode = "USD"
        quotaLimitKnown = snapshot.totalCredits > 0
        requestCountKnown = false
        spendTodayKnown = false
        spendMonthKnown = false
        spendToday = 0
        spendMonth = 0
        resetAt = snapshot.fetchedAt
        lastUpdated = snapshot.fetchedAt
        history = snapshot.history.isEmpty ? [UsagePoint(timestamp: snapshot.fetchedAt, value: snapshot.totalUsage)] : snapshot.history
        dataSource = .live
        sourceUpdatedAt = snapshot.fetchedAt
        healthAlerts = nil
        sourceDetail = "OpenRouter Credits API. Total credits and total usage are live; token buckets, request counts, and period spend are not exposed by this endpoint."
    }

    mutating func apply(snapshot: CodexUsageSnapshot) {
        current = snapshot.primaryUsedPercent
        limit = 100
        unit = "percent"
        tokensToday = 0
        requestCountToday = 0
        requestCountMonth = 0
        currencyCode = "USD"
        quotaLimitKnown = true
        requestCountKnown = false
        spendTodayKnown = false
        spendMonthKnown = false
        spendToday = 0
        spendMonth = 0
        resetAt = snapshot.primaryResetAt
        lastUpdated = snapshot.fetchedAt
        history = snapshot.history
        dataSource = .live
        sourceUpdatedAt = snapshot.fetchedAt
        healthAlerts = nil

        let primaryLabel = Self.quotaWindowLabel(seconds: snapshot.primaryWindowSeconds, fallback: "5-hour window")
        var detail = "Codex login quota from local ~/.codex/auth.json and ChatGPT wham usage. \(primaryLabel) is \(Int(snapshot.primaryUsedPercent))% used."
        if let secondaryUsedPercent = snapshot.secondaryUsedPercent, let secondaryResetAt = snapshot.secondaryResetAt {
            let formatter = RelativeDateTimeFormatter()
            formatter.unitsStyle = .short
            let secondaryLabel = Self.quotaWindowLabel(seconds: snapshot.secondaryWindowSeconds, fallback: "7-day window")
            detail += " \(secondaryLabel) is \(Int(secondaryUsedPercent))% used and resets \(formatter.localizedString(for: secondaryResetAt, relativeTo: snapshot.fetchedAt))."
        }
        if let planType = snapshot.planType, planType.isEmpty == false {
            detail += " Plan: \(planType.uppercased())."
        }
        if snapshot.allowed == false || snapshot.limitReached {
            detail += " Upstream reports the Codex account is currently rate limited."
        }
        sourceDetail = detail
    }

    mutating func apply(snapshot: CCSwitchProviderUsageSnapshot) {
        if let quotaWindow = Self.primaryQuotaWindow(from: snapshot.quotaWindows),
           quotaWindow.hasKnownIntervalLimit || quotaWindow.hasKnownWeeklyLimit {
            current = quotaWindow.intervalUsedPercent
            limit = 100
            unit = "percent"
            quotaLimitKnown = true
            resetAt = quotaWindow.intervalResetAt
            history = [UsagePoint(timestamp: snapshot.fetchedAt, value: quotaWindow.intervalUsedPercent)]
        } else {
            current = snapshot.tokenTotalMonth
            limit = 0
            unit = "tokens"
            quotaLimitKnown = false
            resetAt = snapshot.monthResetAt
            history = snapshot.history.isEmpty
                ? [UsagePoint(timestamp: snapshot.fetchedAt, value: snapshot.tokenTotalMonth)]
                : snapshot.history
        }
        tokensToday = snapshot.tokenTotalToday
        requestCountToday = snapshot.requestCountToday
        requestCountMonth = snapshot.requestCountMonth
        currencyCode = "USD"
        requestCountKnown = true
        spendTodayKnown = true
        spendMonthKnown = true
        spendToday = snapshot.spendToday
        spendMonth = snapshot.spendMonth
        lastUpdated = snapshot.fetchedAt
        dataSource = .ccSwitch
        sourceUpdatedAt = snapshot.fetchedAt
        healthAlerts = snapshot.healthAlerts.isEmpty ? nil : snapshot.healthAlerts
        sourceDetail = snapshot.sourceDetail
    }

    mutating func apply(snapshot: MiniMaxUsageSnapshot) {
        current = snapshot.intervalUsedPercent
        limit = 100
        unit = "percent"
        tokensToday = tokensToday ?? 0
        requestCountToday = requestCountToday ?? 0
        requestCountMonth = requestCountMonth ?? 0
        currencyCode = "USD"
        quotaLimitKnown = true
        requestCountKnown = false
        spendTodayKnown = false
        spendMonthKnown = false
        spendToday = 0
        spendMonth = 0
        resetAt = snapshot.intervalResetAt
        lastUpdated = snapshot.fetchedAt
        history = snapshot.history
        dataSource = .live
        sourceUpdatedAt = snapshot.fetchedAt
        healthAlerts = nil
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        let intervalReset = formatter.localizedString(for: snapshot.intervalResetAt, relativeTo: snapshot.fetchedAt)
        let weeklyReset = formatter.localizedString(for: snapshot.weeklyResetAt, relativeTo: snapshot.fetchedAt)
        var detail = "MiniMax Token Plan quota from \(MiniMaxUsageSnapshot.tokenPlanURL). \(snapshot.primaryModelName) current \(snapshot.intervalWindowLabel) is \(Int(snapshot.intervalUsedPercent))% used"
        if snapshot.intervalTotalCount > 0 {
            detail += " (\(Int(snapshot.intervalUsedCount))/\(Int(snapshot.intervalTotalCount)))"
        } else if let remaining = snapshot.intervalRemainingPercent {
            detail += " (\(Int(remaining))% remaining)"
        }
        detail += " and resets \(intervalReset). Weekly \(snapshot.weeklyWindowLabel) is \(Int(snapshot.weeklyUsedPercent))% used"
        if snapshot.weeklyTotalCount > 0 {
            detail += " (\(Int(snapshot.weeklyUsedCount))/\(Int(snapshot.weeklyTotalCount)))"
        } else if let remaining = snapshot.weeklyRemainingPercent {
            detail += " (\(Int(remaining))% remaining)"
        }
        detail += " and resets \(weeklyReset)."
        if snapshot.modelWindows.count > 1 {
            let names = snapshot.modelWindows.dropFirst().prefix(3).map(\.modelName).joined(separator: ", ")
            if names.isEmpty == false {
                detail += " Additional windows: \(names)."
            }
        }
        sourceDetail = detail
    }

    mutating func apply(localUsage: LocalAgentUsageAppliedSnapshot) {
        var summary = localAgentUsage ?? LocalAgentUsageSummary(
            tokensToday: 0,
            requestCountToday: 0,
            requestCountMonth: 0,
            spendToday: 0,
            spendMonth: 0,
            lastUpdated: localUsage.occurredAt,
            sourceDetail: localUsage.sourceDetail
        )
        summary.tokensToday += localUsage.tokenDelta
        summary.requestCountToday += localUsage.requestDelta
        summary.requestCountMonth += localUsage.requestDelta
        summary.spendToday += localUsage.costDelta
        summary.spendMonth += localUsage.costDelta
        summary.lastUpdated = localUsage.occurredAt
        summary.sourceDetail = localUsage.sourceDetail
        localAgentUsage = summary

        guard sourceKind != .live && sourceKind != .ccSwitch else { return }
        if localUsage.contextTokenTotal > 0 {
            current = localUsage.contextTokenTotal
        } else if localUsage.tokenDelta > 0 {
            current += localUsage.tokenDelta
        }
        if let contextWindowSize = localUsage.contextWindowSize, contextWindowSize > 0 {
            limit = contextWindowSize
            quotaLimitKnown = true
        } else {
            limit = 0
            quotaLimitKnown = false
        }
        unit = "tokens"
        tokensToday = max((tokensToday ?? 0) + localUsage.tokenDelta, localUsage.contextTokenTotal)
        if localUsage.requestDelta > 0 {
            requestCountToday = (requestCountToday ?? 0) + localUsage.requestDelta
            requestCountMonth = (requestCountMonth ?? 0) + localUsage.requestDelta
            requestCountKnown = true
        }
        currencyCode = "USD"
        spendTodayKnown = true
        spendMonthKnown = true
        spendToday += localUsage.costDelta
        spendMonth += localUsage.costDelta
        resetAt = localUsage.rateLimitResetAt ?? resetAt
        lastUpdated = localUsage.occurredAt
        let historyValue = localUsage.contextTokenTotal > 0 ? localUsage.contextTokenTotal : current
        history.append(UsagePoint(timestamp: localUsage.occurredAt, value: historyValue))
        if history.count > 48 {
            history.removeFirst(history.count - 48)
        }
        dataSource = .localAgent
        sourceUpdatedAt = localUsage.occurredAt
        healthAlerts = nil
        sourceDetail = localUsage.sourceDetail
    }

    mutating func markSource(_ source: UsageDataSource, detail: String, now: Date = .now, clearUsage: Bool = false) {
        if clearUsage {
            current = 0
            limit = 0
            spendToday = 0
            spendMonth = 0
            history = [UsagePoint(timestamp: now, value: 0)]
            tokensToday = 0
            requestCountToday = 0
            requestCountMonth = 0
            currencyCode = "USD"
            quotaLimitKnown = false
            requestCountKnown = false
            spendTodayKnown = false
            spendMonthKnown = false
        }
        dataSource = source
        sourceDetail = detail
        sourceUpdatedAt = now
        lastUpdated = now
        healthAlerts = source == .error ? [
            ProviderHealthAlert(status: .critical, title: "Provider refresh failed", detail: detail)
        ] : nil
    }

    private static func primaryQuotaWindow(from windows: [CCSwitchQuotaWindow]) -> CCSwitchQuotaWindow? {
        windows.first(where: { $0.modelName == "general" && ($0.hasKnownIntervalLimit || $0.hasKnownWeeklyLimit) })
            ?? windows.first(where: { $0.hasKnownIntervalLimit || $0.hasKnownWeeklyLimit })
            ?? windows.first
    }

    private static func quotaWindowLabel(seconds: TimeInterval?, fallback: String) -> String {
        guard let seconds, seconds > 0 else { return fallback }
        if seconds >= 86_400 {
            let days = max(Int(round(seconds / 86_400)), 1)
            return days == 1 ? "1-day window" : "\(days)-day window"
        }
        if seconds >= 3_600 {
            let hours = max(Int(round(seconds / 3_600)), 1)
            return hours == 1 ? "1-hour window" : "\(hours)-hour window"
        }
        let minutes = max(Int(round(seconds / 60)), 1)
        return minutes == 1 ? "1-minute window" : "\(minutes)-minute window"
    }
}

struct LocalAgentUsageIngest: Codable, Equatable {
    var agent: AgentProvider?
    var providerID: String?
    var model: String?
    var workspaceID: String?
    var workspaceName: String?
    var workspacePath: String?
    var workspaceClient: String?
    var dailyBudget: Double?
    var monthlyBudget: Double?
    var maxEstimatedRunCost: Double?
    var maxEstimatedTokens: Int?
    var allowedProviderIDs: [String]?
    var blockedModels: [String]?
    var requireCompanyKey: Bool?
    var sessionID: String?
    var source: String?
    var currentDirectory: String?
    var transcriptPath: String?
    var costUSD: Double?
    var inputTokens: Int?
    var outputTokens: Int?
    var totalTokens: Int?
    var contextWindowSize: Int?
    var requestCount: Int?
    var occurredAt: Date?
    var rateLimitUsedPercentage: Double?
    var rateLimitResetAt: Date?
    var cumulative: Bool?
}

struct LocalAgentUsageAppliedSnapshot: Equatable {
    var agent: AgentProvider
    var providerID: String
    var model: String
    var workspaceID: String?
    var sessionKey: String
    var sourceName: String
    var costDelta: Double
    var tokenDelta: Double
    var requestDelta: Int
    var contextTokenTotal: Double
    var contextWindowSize: Double?
    var rateLimitUsedPercentage: Double?
    var rateLimitResetAt: Date?
    var occurredAt: Date
    var sourceDetail: String
}

enum SmartRoutingRunSignal: String, Codable {
    case success
    case followUp
    case failed
    case unknown
}

struct SmartRoutingRunInput: Codable, Equatable {
    var agent: AgentProvider?
    var taskIntent: String?
    var providerID: String?
    var model: String?
    var workspaceID: String?
    var workspaceName: String?
    var workspacePath: String?
    var sessionID: String?
    var taskID: String?
    var estimatedCost: Double?
    var actualCost: Double?
    var estimatedTokens: Int?
    var actualTokens: Int?
    var inputTokens: Int?
    var outputTokens: Int?
    var requestCount: Int?
    var signal: SmartRoutingRunSignal?
    var followUpRequired: Bool?
    var selectedBy: String?
    var alternatives: [String]?
    var routingReason: String?
    var metadata: [String: String]?
    var occurredAt: Date?
}

struct SmartRoutingRunRecord: Identifiable, Codable, Equatable {
    var id: UUID
    var recordedAt: Date
    var occurredAt: Date
    var agent: AgentProvider
    var taskIntent: String
    var providerID: String
    var model: String
    var workspaceID: String?
    var workspaceName: String?
    var workspacePath: String?
    var sessionID: String?
    var taskID: String?
    var estimatedCost: Double
    var actualCost: Double
    var estimatedTokens: Int
    var actualTokens: Int
    var inputTokens: Int?
    var outputTokens: Int?
    var requestCount: Int?
    var signal: SmartRoutingRunSignal
    var followUpRequired: Bool
    var selectedBy: String?
    var alternatives: [String]
    var routingReason: String?
    var metadata: [String: String]

    var isWin: Bool {
        signal == .success && followUpRequired == false
    }
}

struct SmartRoutingRouteStats: Identifiable, Codable, Equatable {
    var id: String { routeKey }
    var routeKey: String
    var providerID: String
    var model: String
    var taskIntent: String
    var runCount: Int
    var winCount: Int
    var followUpCount: Int
    var failedCount: Int
    var unknownCount: Int
    var winRate: Double
    var followUpRate: Double
    var estimatedCostTotal: Double
    var actualCostTotal: Double
    var estimatedTokensTotal: Int
    var actualTokensTotal: Int
    var averageCostDelta: Double
    var averageTokenDelta: Double
    var lastRunAt: Date
}

struct SmartRoutingStatsSnapshot: Codable, Equatable {
    var generatedAt: Date
    var totalRuns: Int
    var winCount: Int
    var followUpCount: Int
    var failedCount: Int
    var unknownCount: Int
    var winRate: Double
    var followUpRate: Double
    var estimatedCostTotal: Double
    var actualCostTotal: Double
    var estimatedTokensTotal: Int
    var actualTokensTotal: Int
    var excludedNonProductionRuns: Int
    var routeStats: [SmartRoutingRouteStats]
    var recentRuns: [SmartRoutingRunRecord]
}

struct ModelUsageRollup: Identifiable, Codable, Equatable {
    var agent: AgentProvider
    var providerID: String
    var model: String
    var source: ModelUsageSource
    var configPath: String?
    var spendToday: Double
    var spendMonth: Double
    var tokensToday: Double
    var tokensMonth: Double
    var requestCountToday: Int
    var requestCountMonth: Int
    var dayKey: String
    var monthKey: String
    var lastUpdated: Date

    var id: String {
        [agent.rawValue, providerID, model.lowercased(), source.rawValue, configPath ?? ""].joined(separator: "|")
    }

    var hasUsage: Bool {
        spendMonth > 0 || tokensMonth > 0 || requestCountMonth > 0
    }
}

enum APIMonitorCapability: String, Codable {
    case automatic
    case console
    case responseHeaders
    case manualSubscription

    func title(language: AppLanguage) -> String {
        switch (self, language) {
        case (.automatic, .english): "Automatic"
        case (.console, .english): "Console / Cloud metrics"
        case (.responseHeaders, .english): "Response headers"
        case (.manualSubscription, .english): "Manual subscription"
        case (.automatic, .chinese): "自动读取"
        case (.console, .chinese): "控制台 / 云监控"
        case (.responseHeaders, .chinese): "响应头"
        case (.manualSubscription, .chinese): "手动订阅"
        }
    }

    var status: UsageStatus {
        switch self {
        case .automatic: .healthy
        case .responseHeaders: .warning
        case .console, .manualSubscription: .warning
        }
    }
}

struct APIRequestTemplate: Codable, Equatable {
    var method: String
    var url: String
    var headers: [String]
    var body: String?
}

struct APIMonitorSpec: Identifiable, Codable, Equatable {
    var id: String
    var name: String
    var family: String
    var symbolName: String
    var models: [String]
    var capability: APIMonitorCapability
    var usageRequest: APIRequestTemplate?
    var costRequest: APIRequestTemplate?
    var subscriptionURL: String
    var docsURL: String
    var alertMetric: String
    var note: String
}

enum AgentProvider: String, CaseIterable, Identifiable, Codable {
    case claudeCode
    case codex
    case cursor
    case continueDev
    case custom

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .claudeCode: "Claude Code"
        case .codex: "Codex"
        case .cursor: "Cursor"
        case .continueDev: "Continue"
        case .custom: "Custom Agent"
        }
    }

    var symbolName: String {
        switch self {
        case .claudeCode: "terminal.fill"
        case .codex: "curlybraces"
        case .cursor: "cursorarrow.motionlines"
        case .continueDev: "play.rectangle.fill"
        case .custom: "cpu"
        }
    }
}

enum PolicyDecisionStatus: String, Codable {
    case allow
    case warn
    case block

    var usageStatus: UsageStatus {
        switch self {
        case .allow: .healthy
        case .warn: .warning
        case .block: .critical
        }
    }

    var symbolName: String {
        switch self {
        case .allow: "checkmark.shield.fill"
        case .warn: "exclamationmark.shield.fill"
        case .block: "xmark.shield.fill"
        }
    }
}

struct WorkspacePolicy: Identifiable, Codable, Equatable {
    var id: String
    var name: String
    var pathHint: String
    var client: String
    var dailyBudget: Double
    var monthlyBudget: Double
    var spendToday: Double
    var spendMonth: Double
    /// Calendar buckets for the mutable spend totals. Missing keys are treated as
    /// unverified legacy data and reset rather than carrying a stale total forward.
    var spendDayKey: String? = nil
    var spendMonthKey: String? = nil
    var allowedProviderIDs: [String]
    var blockedModels: [String]
    var maxEstimatedRunCost: Double
    var maxEstimatedTokens: Int = 0
    var requireCompanyKey: Bool
    var preferredProviderID: String? = nil
    var preferredModel: String? = nil
    var setupSourceDetail: String? = nil
    var configuredModelCount: Int? = nil
    var inferredFromPaths: [String]? = nil

    var dailyRatio: Double {
        guard dailyBudget > 0 else { return 0 }
        return min(spendToday / dailyBudget, 1.5)
    }

    var status: UsageStatus {
        if dailyRatio >= 1 { return .critical }
        if dailyRatio >= 0.8 { return .warning }
        return .healthy
    }

    @discardableResult
    mutating func resetExpiredSpendBuckets(now: Date = .now, calendar: Calendar = .current) -> Bool {
        let components = calendar.dateComponents([.year, .month, .day], from: now)
        guard let year = components.year, let month = components.month, let day = components.day else {
            return false
        }

        let currentDayKey = String(format: "%04d-%02d-%02d", year, month, day)
        let currentMonthKey = String(format: "%04d-%02d", year, month)
        var changed = false
        if spendDayKey != currentDayKey {
            spendToday = 0
            spendDayKey = currentDayKey
            changed = true
        }
        if spendMonthKey != currentMonthKey {
            spendMonth = 0
            spendMonthKey = currentMonthKey
            changed = true
        }
        return changed
    }
}

struct WorkspacePolicyInference: Equatable {
    var allowedProviderIDs: [String]
    var preferredProviderID: String
    var preferredModel: String
    var maxEstimatedRunCost: Double
    var setupSourceDetail: String
    var configuredModelCount: Int
    var inferredFromPaths: [String]

    var hasSignals: Bool {
        configuredModelCount > 0 || inferredFromPaths.isEmpty == false
    }
}

struct PolicyEvaluationInput: Codable, Equatable {
    var agent: AgentProvider
    var workspaceID: String
    var providerID: String
    var model: String
    var estimatedCost: Double
    var estimatedTokens: Int
    var keySource: String? = nil
    var intent: String
    var workspaceName: String? = nil
    var workspacePath: String? = nil
    var workspaceClient: String? = nil
    var dailyBudget: Double? = nil
    var monthlyBudget: Double? = nil
    var maxEstimatedRunCost: Double? = nil
    var maxEstimatedTokens: Int? = nil
    var allowedProviderIDs: [String]? = nil
    var blockedModels: [String]? = nil
    var requireCompanyKey: Bool? = nil
    var preferredProviderID: String? = nil
    var preferredModel: String? = nil
}

struct SmartRoutingRecommendation: Codable, Equatable {
    var providerID: String
    var model: String
    var taskIntent: String
    var confidence: Double
    var evidenceRunCount: Int
    var winRate: Double
    var estimatedCost: Double
    var reason: String
    var alternatives: [String]
}

struct PolicyDecision: Identifiable, Codable, Equatable {
    var id = UUID()
    var timestamp: Date
    var status: PolicyDecisionStatus
    var agent: AgentProvider
    var workspaceID: String
    var workspaceName: String
    var providerID: String
    var model: String
    var estimatedCost: Double
    var projectedDailySpend: Double
    var projectedMonthlySpend: Double
    var reasons: [String]
    var recommendation: String
    var fallbackProviderID: String?
    var routingMode: RoutingMode = .guardOnly
    var smartRoutingRecommendation: SmartRoutingRecommendation? = nil
}

struct UsageSummary: Identifiable, Equatable {
    var id: String
    var title: String
    var spend: Double
    var tokens: Double
    var requests: Int
    var projectedSpend: Double
}

struct AuditEvent: Identifiable, Codable, Equatable {
    var id = UUID()
    var timestamp: Date
    var provider: String
    var action: String
    var detail: String
}

struct ProbeTemplate: Identifiable, Codable, Equatable {
    var id: String { platform }
    var platform: String
    var displayName: String
    var category: String
    var symbolName: String
    var unit: String
}
