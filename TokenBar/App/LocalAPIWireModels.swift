import Foundation

@MainActor
enum LocalAPIWire {
    struct Nullable<Value: Encodable>: Encodable {
        var value: Value?

        init(_ value: Value?) {
            self.value = value
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            if let value {
                try container.encode(value)
            } else {
                try container.encodeNil()
            }
        }
    }

    struct PolicyDocument: Encodable {
        let version = "1.0"
        var timestamp: String
        let localOnly = true
        var decision: Decision
        var workspaces: [Workspace]
    }

    struct PolicyDecisionDocument: Encodable {
        let version = "1.0"
        var timestamp: String
        let localOnly = true
        var decision: Decision
    }

    struct LocalAgentUsageDocument: Encodable {
        let version = "1.0"
        var timestamp: String
        let localOnly = true
        var source: String
        var usage: LocalAgentUsage
        var decision: Decision
    }

    struct SmartRoutingRunDocument: Encodable {
        let version = "1.0"
        var timestamp: String
        let localOnly = true
        var routingRun: SmartRoutingRun
    }

    struct SmartRoutingStatsDocument: Encodable {
        let version = "1.0"
        var timestamp: String
        let localOnly = true
        var stats: SmartRoutingStats
        var routes: [SmartRoutingRoute]
        var recentRuns: [SmartRoutingRun]
    }

    struct QuotaDocument: Encodable {
        let version = "1.0"
        var timestamp: String
        let localOnly = true
        var quotas: [Quota]
    }

    struct Workspace: Encodable {
        var id: String
        var name: String
        var pathHint: String
        var dailyBudget: Double
        var monthlyBudget: Double
        var spendToday: Double
        var spendMonth: Double
        var spendDayKey: Nullable<String>
        var spendMonthKey: Nullable<String>
        var maxEstimatedRunCost: Double
        var maxEstimatedTokens: Int
        var allowedProviders: [String]
        var preferredProvider: Nullable<String>
        var preferredModel: Nullable<String>
        var blockedModels: [String]
        var requireCompanyKey: Bool
        var setupSourceDetail: Nullable<String>
        var configuredModelCount: Nullable<Int>

        init(_ workspace: WorkspacePolicy) {
            id = workspace.id
            name = workspace.name
            pathHint = workspace.pathHint
            dailyBudget = workspace.dailyBudget
            monthlyBudget = workspace.monthlyBudget
            spendToday = workspace.spendToday
            spendMonth = workspace.spendMonth
            spendDayKey = Nullable(workspace.spendDayKey)
            spendMonthKey = Nullable(workspace.spendMonthKey)
            maxEstimatedRunCost = workspace.maxEstimatedRunCost
            maxEstimatedTokens = workspace.maxEstimatedTokens
            allowedProviders = workspace.allowedProviderIDs
            preferredProvider = Nullable(workspace.preferredProviderID)
            preferredModel = Nullable(workspace.preferredModel)
            blockedModels = workspace.blockedModels
            requireCompanyKey = workspace.requireCompanyKey
            setupSourceDetail = Nullable(workspace.setupSourceDetail)
            configuredModelCount = Nullable(workspace.configuredModelCount)
        }
    }

    struct Decision: Encodable {
        struct WorkspaceReference: Encodable {
            var id: String
            var name: String
        }

        var status: String
        var agent: String
        var workspace: WorkspaceReference
        var provider: String
        var model: String
        var estimatedCost: Double
        var projectedDailySpend: Double
        var projectedMonthlySpend: Double
        var reasons: [String]
        var recommendation: String
        var fallbackProvider: Nullable<String>
        var routingMode: String
        var smartRouting: Nullable<SmartRoutingRecommendationPayload>
        var timestamp: String

        init(_ decision: PolicyDecision) {
            status = decision.status.rawValue
            agent = decision.agent.displayName
            workspace = WorkspaceReference(id: decision.workspaceID, name: decision.workspaceName)
            provider = decision.providerID
            model = decision.model
            estimatedCost = decision.estimatedCost
            projectedDailySpend = decision.projectedDailySpend
            projectedMonthlySpend = decision.projectedMonthlySpend
            reasons = decision.reasons
            recommendation = decision.recommendation
            fallbackProvider = Nullable(decision.fallbackProviderID)
            routingMode = decision.routingMode.rawValue
            smartRouting = Nullable(decision.smartRoutingRecommendation.map(SmartRoutingRecommendationPayload.init))
            timestamp = LocalAPIWire.timestamp(decision.timestamp)
        }
    }

    struct SmartRoutingRecommendationPayload: Encodable {
        var provider: String
        var model: String
        var taskIntent: String
        var confidence: Double
        var evidenceRunCount: Int
        var winRate: Double
        var estimatedCost: Double
        var reason: String
        var alternatives: [String]

        init(_ recommendation: SmartRoutingRecommendation) {
            provider = recommendation.providerID
            model = recommendation.model
            taskIntent = recommendation.taskIntent
            confidence = recommendation.confidence
            evidenceRunCount = recommendation.evidenceRunCount
            winRate = recommendation.winRate
            estimatedCost = recommendation.estimatedCost
            reason = recommendation.reason
            alternatives = recommendation.alternatives
        }
    }

    struct LocalAgentUsage: Encodable {
        var agent: String
        var provider: String
        var model: String
        var workspaceID: Nullable<String>
        var sessionKey: String
        var dataSource: String
        var costDelta: Double
        var tokenDelta: Double
        var requestDelta: Int
        var contextTokenTotal: Double
        var contextWindowSize: Nullable<Double>
        var rateLimitUsedPercentage: Nullable<Double>
        var rateLimitResetAt: Nullable<String>
        var occurredAt: String
        var sourceDetail: String

        init(_ snapshot: LocalAgentUsageAppliedSnapshot) {
            agent = snapshot.agent.displayName
            provider = snapshot.providerID
            model = snapshot.model
            workspaceID = Nullable(snapshot.workspaceID)
            sessionKey = snapshot.sessionKey
            dataSource = UsageDataSource.localAgent.rawValue
            costDelta = snapshot.costDelta
            tokenDelta = snapshot.tokenDelta
            requestDelta = snapshot.requestDelta
            contextTokenTotal = snapshot.contextTokenTotal
            contextWindowSize = Nullable(snapshot.contextWindowSize)
            rateLimitUsedPercentage = Nullable(snapshot.rateLimitUsedPercentage)
            rateLimitResetAt = Nullable(snapshot.rateLimitResetAt.map(LocalAPIWire.timestamp))
            occurredAt = LocalAPIWire.timestamp(snapshot.occurredAt)
            sourceDetail = snapshot.sourceDetail
        }
    }

    nonisolated static func timestamp(_ date: Date) -> String {
        ISO8601DateFormatter().string(from: date)
    }
}
