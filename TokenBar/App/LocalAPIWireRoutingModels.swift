import Foundation

@MainActor
extension LocalAPIWire {
    struct SmartRoutingRun: Encodable {
        var id: String
        var recordedAt: String
        var occurredAt: String
        var agent: String
        var agentID: String
        var taskIntent: String
        var provider: String
        var model: String
        var workspaceID: Nullable<String>
        var workspaceName: Nullable<String>
        var workspacePath: Nullable<String>
        var sessionID: Nullable<String>
        var taskID: Nullable<String>
        var estimatedCost: Nullable<Double>
        var actualCost: Nullable<Double>
        var costDelta: Nullable<Double>
        var estimatedTokens: Nullable<Int>
        var actualTokens: Nullable<Int>
        var tokenDelta: Nullable<Int>
        var inputTokens: Nullable<Int>
        var outputTokens: Nullable<Int>
        var requestCount: Nullable<Int>
        var signal: String
        var followUpRequired: Bool
        var win: Bool
        var selectedBy: Nullable<String>
        var alternatives: [String]
        var routingReason: Nullable<String>
        var metadata: [String: String]

        init(_ record: SmartRoutingRunRecord) {
            let hasEstimatedCost = record.estimatedCostKnown != false
            let hasActualCost = record.actualCostKnown != false
            let hasEstimatedTokens = record.estimatedTokensKnown != false
            let hasActualTokens = record.actualTokensKnown != false
            id = record.id.uuidString
            recordedAt = LocalAPIWire.timestamp(record.recordedAt)
            occurredAt = LocalAPIWire.timestamp(record.occurredAt)
            agent = record.agent.displayName
            agentID = record.agent.rawValue
            taskIntent = record.taskIntent
            provider = record.providerID
            model = record.model
            workspaceID = Nullable(record.workspaceID)
            workspaceName = Nullable(record.workspaceName)
            workspacePath = Nullable(record.workspacePath)
            sessionID = Nullable(record.sessionID)
            taskID = Nullable(record.taskID)
            estimatedCost = Nullable(hasEstimatedCost ? record.estimatedCost : nil)
            actualCost = Nullable(hasActualCost ? record.actualCost : nil)
            costDelta = Nullable(hasEstimatedCost && hasActualCost ? record.actualCost - record.estimatedCost : nil)
            estimatedTokens = Nullable(hasEstimatedTokens ? record.estimatedTokens : nil)
            actualTokens = Nullable(hasActualTokens ? record.actualTokens : nil)
            tokenDelta = Nullable(hasEstimatedTokens && hasActualTokens ? record.actualTokens - record.estimatedTokens : nil)
            inputTokens = Nullable(record.inputTokens)
            outputTokens = Nullable(record.outputTokens)
            requestCount = Nullable(record.requestCount)
            signal = record.signal.rawValue
            followUpRequired = record.followUpRequired
            win = record.signal == .success && record.followUpRequired == false
            selectedBy = Nullable(record.selectedBy)
            alternatives = record.alternatives
            routingReason = Nullable(record.routingReason)
            metadata = record.metadata
        }
    }

    struct SmartRoutingStats: Encodable {
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

        init(_ snapshot: SmartRoutingStatsSnapshot) {
            totalRuns = snapshot.totalRuns
            winCount = snapshot.winCount
            followUpCount = snapshot.followUpCount
            failedCount = snapshot.failedCount
            unknownCount = snapshot.unknownCount
            winRate = snapshot.winRate
            followUpRate = snapshot.followUpRate
            estimatedCostTotal = snapshot.estimatedCostTotal
            actualCostTotal = snapshot.actualCostTotal
            estimatedCostKnownRunCount = snapshot.estimatedCostKnownRunCount
            actualCostKnownRunCount = snapshot.actualCostKnownRunCount
            estimatedTokensTotal = snapshot.estimatedTokensTotal
            actualTokensTotal = snapshot.actualTokensTotal
            estimatedTokensKnownRunCount = snapshot.estimatedTokensKnownRunCount
            actualTokensKnownRunCount = snapshot.actualTokensKnownRunCount
            excludedNonProductionRuns = snapshot.excludedNonProductionRuns
        }
    }

    struct SmartRoutingRoute: Encodable {
        var routeKey: String
        var provider: String
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
        var lastRunAt: String

        init(_ route: SmartRoutingRouteStats) {
            routeKey = route.routeKey
            provider = route.providerID
            model = route.model
            taskIntent = route.taskIntent
            runCount = route.runCount
            winCount = route.winCount
            followUpCount = route.followUpCount
            failedCount = route.failedCount
            unknownCount = route.unknownCount
            winRate = route.winRate
            followUpRate = route.followUpRate
            estimatedCostTotal = route.estimatedCostTotal
            actualCostTotal = route.actualCostTotal
            estimatedCostKnownRunCount = route.estimatedCostKnownRunCount
            actualCostKnownRunCount = route.actualCostKnownRunCount
            estimatedTokensTotal = route.estimatedTokensTotal
            actualTokensTotal = route.actualTokensTotal
            estimatedTokensKnownRunCount = route.estimatedTokensKnownRunCount
            actualTokensKnownRunCount = route.actualTokensKnownRunCount
            averageCostDelta = route.averageCostDelta
            averageTokenDelta = route.averageTokenDelta
            lastRunAt = LocalAPIWire.timestamp(route.lastRunAt)
        }
    }
}
