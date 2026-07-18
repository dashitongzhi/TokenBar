import Foundation

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
    var estimatedCostKnown: Bool? = nil
    var actualCostKnown: Bool? = nil
    var estimatedTokens: Int
    var actualTokens: Int
    var estimatedTokensKnown: Bool? = nil
    var actualTokensKnown: Bool? = nil
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
    var estimatedCostKnownRunCount: Int
    var actualCostKnownRunCount: Int
    var estimatedTokensTotal: Int
    var actualTokensTotal: Int
    var estimatedTokensKnownRunCount: Int
    var actualTokensKnownRunCount: Int
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
    var estimatedCostKnownRunCount: Int
    var actualCostKnownRunCount: Int
    var estimatedTokensTotal: Int
    var actualTokensTotal: Int
    var estimatedTokensKnownRunCount: Int
    var actualTokensKnownRunCount: Int
    var excludedNonProductionRuns: Int
    var routeStats: [SmartRoutingRouteStats]
    var recentRuns: [SmartRoutingRunRecord]
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
