import Foundation

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

    static func defaultAgent(forProviderID providerID: String) -> AgentProvider {
        switch providerID {
        case "anthropic": .claudeCode
        case "openai": .codex
        default: .custom
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
    /// Calendar buckets for the mutable spend totals. Missing keys identify legacy
    /// data whose existing totals are preserved while the current buckets are assigned.
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

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case pathHint
        case client
        case dailyBudget
        case monthlyBudget
        case spendToday
        case spendMonth
        case spendDayKey
        case spendMonthKey
        case allowedProviderIDs
        case blockedModels
        case maxEstimatedRunCost
        case maxEstimatedTokens
        case requireCompanyKey
        case preferredProviderID
        case preferredModel
        case setupSourceDetail
        case configuredModelCount
        case inferredFromPaths
    }

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
        if spendDayKey == nil {
            spendDayKey = currentDayKey
            changed = true
        } else if spendDayKey != currentDayKey {
            spendToday = 0
            spendDayKey = currentDayKey
            changed = true
        }
        if spendMonthKey == nil {
            spendMonthKey = currentMonthKey
            changed = true
        } else if spendMonthKey != currentMonthKey {
            spendMonth = 0
            spendMonthKey = currentMonthKey
            changed = true
        }
        return changed
    }
}

extension WorkspacePolicy {
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        pathHint = try container.decode(String.self, forKey: .pathHint)
        client = try container.decode(String.self, forKey: .client)
        dailyBudget = try container.decode(Double.self, forKey: .dailyBudget)
        monthlyBudget = try container.decode(Double.self, forKey: .monthlyBudget)
        spendToday = try container.decode(Double.self, forKey: .spendToday)
        spendMonth = try container.decode(Double.self, forKey: .spendMonth)
        spendDayKey = try container.decodeIfPresent(String.self, forKey: .spendDayKey)
        spendMonthKey = try container.decodeIfPresent(String.self, forKey: .spendMonthKey)
        allowedProviderIDs = try container.decode([String].self, forKey: .allowedProviderIDs)
        blockedModels = try container.decode([String].self, forKey: .blockedModels)
        maxEstimatedRunCost = try container.decode(Double.self, forKey: .maxEstimatedRunCost)
        maxEstimatedTokens = try container.decodeIfPresent(Int.self, forKey: .maxEstimatedTokens) ?? 0
        requireCompanyKey = try container.decode(Bool.self, forKey: .requireCompanyKey)
        preferredProviderID = try container.decodeIfPresent(String.self, forKey: .preferredProviderID)
        preferredModel = try container.decodeIfPresent(String.self, forKey: .preferredModel)
        setupSourceDetail = try container.decodeIfPresent(String.self, forKey: .setupSourceDetail)
        configuredModelCount = try container.decodeIfPresent(Int.self, forKey: .configuredModelCount)
        inferredFromPaths = try container.decodeIfPresent([String].self, forKey: .inferredFromPaths)
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
