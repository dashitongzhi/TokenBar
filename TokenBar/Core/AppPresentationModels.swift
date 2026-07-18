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
