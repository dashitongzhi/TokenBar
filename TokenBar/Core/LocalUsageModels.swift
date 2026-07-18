import Foundation

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
