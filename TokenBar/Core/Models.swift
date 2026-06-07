import Foundation
import AppKit
import SwiftUI

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

enum UsageStatus: String, Codable {
    case healthy
    case warning
    case critical

    var color: Color {
        switch self {
        case .healthy: .green
        case .warning: .orange
        case .critical: .red
        }
    }

    var nsColor: NSColor {
        switch self {
        case .healthy: .systemGreen
        case .warning: .systemOrange
        case .critical: .systemRed
        }
    }

    var symbolName: String {
        switch self {
        case .healthy: "chart.bar.fill"
        case .warning: "exclamationmark.circle.fill"
        case .critical: "exclamationmark.triangle.fill"
        }
    }
}

struct UsagePoint: Identifiable, Codable, Equatable {
    var id = UUID()
    var timestamp: Date
    var value: Double
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

    var usageRatio: Double {
        guard limit > 0 else { return 0 }
        return min(max(current / limit, 0), 1.5)
    }

    var remaining: Double {
        max(limit - current, 0)
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
        guard rate > 0, remaining > 0 else { return nil }
        return Date().addingTimeInterval((remaining / rate) * 3600)
    }

    var status: UsageStatus {
        if let predictedExhaustion {
            let hours = predictedExhaustion.timeIntervalSinceNow / 3600
            if hours < 6 { return .critical }
            if hours < 24 { return .warning }
        }

        if usageRatio >= 0.9 { return .critical }
        if usageRatio >= 0.7 { return .warning }
        return .healthy
    }

    mutating func simulateRefresh() {
        let increment = Double.random(in: 8...90)
        current = min(current + increment, limit * 1.05)
        spendToday += increment * 0.0008
        spendMonth += increment * 0.0008
        lastUpdated = Date()
        history.append(UsagePoint(timestamp: lastUpdated, value: current))
        if history.count > 100 {
            history.removeFirst(history.count - 100)
        }
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
    var allowedProviderIDs: [String]
    var blockedModels: [String]
    var maxEstimatedRunCost: Double
    var requireCompanyKey: Bool

    var dailyRatio: Double {
        guard dailyBudget > 0 else { return 0 }
        return min(spendToday / dailyBudget, 1.5)
    }

    var status: UsageStatus {
        if dailyRatio >= 1 { return .critical }
        if dailyRatio >= 0.8 { return .warning }
        return .healthy
    }
}

struct PolicyEvaluationInput: Codable, Equatable {
    var agent: AgentProvider
    var workspaceID: String
    var providerID: String
    var model: String
    var estimatedCost: Double
    var estimatedTokens: Int
    var intent: String
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
    var reasons: [String]
    var recommendation: String
    var fallbackProviderID: String?
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
