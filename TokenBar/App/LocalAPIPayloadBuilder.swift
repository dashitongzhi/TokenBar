import Foundation

enum LocalAPIPayloadBuilder {
    static func policyJSON(currentDecision: PolicyDecision, workspacePolicies: [WorkspacePolicy]) -> Data {
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
                    "monthlyBudget": workspace.monthlyBudget,
                    "spendToday": workspace.spendToday,
                    "spendMonth": workspace.spendMonth,
                    "maxEstimatedRunCost": workspace.maxEstimatedRunCost,
                    "allowedProviders": workspace.allowedProviderIDs,
                    "preferredProvider": workspace.preferredProviderID ?? NSNull(),
                    "preferredModel": workspace.preferredModel ?? NSNull(),
                    "blockedModels": workspace.blockedModels,
                    "requireCompanyKey": workspace.requireCompanyKey,
                    "setupSourceDetail": workspace.setupSourceDetail ?? NSNull(),
                    "configuredModelCount": workspace.configuredModelCount ?? NSNull()
                ] as [String: Any]
            }
        ]
        return jsonData(payload)
    }

    static func policyDecisionJSON(_ decision: PolicyDecision) -> Data {
        let payload: [String: Any] = [
            "version": "1.0",
            "timestamp": ISO8601DateFormatter().string(from: Date()),
            "localOnly": true,
            "decision": policyDictionary(decision)
        ]
        return jsonData(payload)
    }

    static func localAgentUsageJSON(snapshot: LocalAgentUsageAppliedSnapshot, decision: PolicyDecision) -> Data {
        let payload: [String: Any] = [
            "version": "1.0",
            "timestamp": ISO8601DateFormatter().string(from: Date()),
            "localOnly": true,
            "source": snapshot.sourceName,
            "usage": [
                "agent": snapshot.agent.displayName,
                "provider": snapshot.providerID,
                "model": snapshot.model,
                "workspaceID": snapshot.workspaceID ?? NSNull(),
                "sessionKey": snapshot.sessionKey,
                "dataSource": UsageDataSource.localAgent.rawValue,
                "costDelta": snapshot.costDelta,
                "tokenDelta": snapshot.tokenDelta,
                "requestDelta": snapshot.requestDelta,
                "contextTokenTotal": snapshot.contextTokenTotal,
                "contextWindowSize": snapshot.contextWindowSize ?? NSNull(),
                "rateLimitUsedPercentage": snapshot.rateLimitUsedPercentage ?? NSNull(),
                "rateLimitResetAt": snapshot.rateLimitResetAt.map { ISO8601DateFormatter().string(from: $0) } ?? NSNull(),
                "occurredAt": ISO8601DateFormatter().string(from: snapshot.occurredAt),
                "sourceDetail": snapshot.sourceDetail
            ] as [String: Any],
            "decision": policyDictionary(decision)
        ]
        return jsonData(payload)
    }

    static func smartRoutingRunJSON(record: SmartRoutingRunRecord) -> Data {
        let payload: [String: Any] = [
            "version": "1.0",
            "timestamp": ISO8601DateFormatter().string(from: Date()),
            "localOnly": true,
            "routingRun": smartRoutingRunDictionary(record)
        ]
        return jsonData(payload)
    }

    static func smartRoutingStatsJSON(snapshot: SmartRoutingStatsSnapshot) -> Data {
        let payload: [String: Any] = [
            "version": "1.0",
            "timestamp": ISO8601DateFormatter().string(from: snapshot.generatedAt),
            "localOnly": true,
            "stats": [
                "totalRuns": snapshot.totalRuns,
                "winCount": snapshot.winCount,
                "followUpCount": snapshot.followUpCount,
                "failedCount": snapshot.failedCount,
                "unknownCount": snapshot.unknownCount,
                "winRate": snapshot.winRate,
                "followUpRate": snapshot.followUpRate,
                "estimatedCostTotal": snapshot.estimatedCostTotal,
                "actualCostTotal": snapshot.actualCostTotal,
                "estimatedTokensTotal": snapshot.estimatedTokensTotal,
                "actualTokensTotal": snapshot.actualTokensTotal
            ],
            "routes": snapshot.routeStats.map(smartRoutingRouteDictionary),
            "recentRuns": snapshot.recentRuns.map(smartRoutingRunDictionary)
        ]
        return jsonData(payload)
    }

    static func mcpSnapshotJSON(providers: [ProviderUsage], filteredProviderID: String? = nil) -> Data {
        let selected = filteredProviderID.map { id in providers.filter { $0.id == id } } ?? providers
        let quotas = selected.map { provider in
            var metric: [String: Any] = [
                "name": provider.unit,
                "current": provider.current,
                "limit": provider.hasKnownQuotaLimit ? provider.limit : NSNull(),
                "unit": provider.unit,
                "remaining": provider.knownRemaining ?? NSNull(),
                "usageRatio": provider.usageRatio,
                "burnRatePerHour": provider.burnRatePerHour,
                "resetAt": ISO8601DateFormatter().string(from: provider.resetAt),
                "dataSource": provider.sourceKind.rawValue,
                "sourceDetail": provider.sourceDescription,
                "sourceUpdatedAt": provider.sourceUpdatedAt.map { ISO8601DateFormatter().string(from: $0) } ?? NSNull(),
                "quotaLimitKnown": provider.hasKnownQuotaLimit,
                "tokensToday": provider.todayTokenCount,
                "requestsKnown": provider.hasKnownRequestCount,
                "requestsToday": provider.knownTodayRequestCount ?? NSNull(),
                "requestsMonth": provider.knownRequestCount ?? NSNull(),
                "spendTodayKnown": provider.hasKnownSpendToday,
                "spendToday": provider.hasKnownSpendToday ? provider.spendToday as Any : NSNull() as Any,
                "spendMonthKnown": provider.hasKnownSpendMonth,
                "spendMonth": provider.hasKnownSpendMonth ? provider.spendMonth as Any : NSNull() as Any,
                "currency": provider.displayCurrency
            ]
            metric["predictedExhaustion"] = provider.predictedExhaustion.map { ISO8601DateFormatter().string(from: $0) } ?? NSNull()
            return [
                "platform": provider.id,
                "displayName": provider.name,
                "status": provider.status.rawValue,
                "dataSource": provider.sourceKind.rawValue,
                "sourceDetail": provider.sourceDescription,
                "metrics": [metric]
            ] as [String: Any]
        }
        let payload: [String: Any] = [
            "version": "1.0",
            "timestamp": ISO8601DateFormatter().string(from: Date()),
            "localOnly": true,
            "quotas": quotas
        ]
        return jsonData(payload)
    }

    static func paceJSON(provider: ProviderUsage, recommendation: String) -> Data {
        let payload: [String: Any] = [
            "platform": provider.id,
            "displayName": provider.name,
            "status": provider.status.rawValue,
            "dataSource": provider.sourceKind.rawValue,
            "sourceDetail": provider.sourceDescription,
            "burnRatePerHour": provider.burnRatePerHour,
            "remaining": provider.knownRemaining ?? NSNull(),
            "quotaLimitKnown": provider.hasKnownQuotaLimit,
            "tokensToday": provider.todayTokenCount,
            "tokensMonth": provider.current,
            "requestsKnown": provider.hasKnownRequestCount,
            "requestsToday": provider.knownTodayRequestCount ?? NSNull(),
            "requestsMonth": provider.knownRequestCount ?? NSNull(),
            "spendTodayKnown": provider.hasKnownSpendToday,
            "spendToday": provider.hasKnownSpendToday ? provider.spendToday as Any : NSNull() as Any,
            "spendMonthKnown": provider.hasKnownSpendMonth,
            "spendMonth": provider.hasKnownSpendMonth ? provider.spendMonth as Any : NSNull() as Any,
            "currency": provider.displayCurrency,
            "predictedExhaustion": provider.predictedExhaustion.map { ISO8601DateFormatter().string(from: $0) } ?? NSNull(),
            "recommendation": recommendation
        ]
        return jsonData(payload)
    }

    private static func policyDictionary(_ decision: PolicyDecision) -> [String: Any] {
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

    private static func smartRoutingRunDictionary(_ record: SmartRoutingRunRecord) -> [String: Any] {
        [
            "id": record.id.uuidString,
            "recordedAt": ISO8601DateFormatter().string(from: record.recordedAt),
            "occurredAt": ISO8601DateFormatter().string(from: record.occurredAt),
            "agent": record.agent.displayName,
            "agentID": record.agent.rawValue,
            "taskIntent": record.taskIntent,
            "provider": record.providerID,
            "model": record.model,
            "workspaceID": record.workspaceID ?? NSNull(),
            "workspaceName": record.workspaceName ?? NSNull(),
            "workspacePath": record.workspacePath ?? NSNull(),
            "sessionID": record.sessionID ?? NSNull(),
            "taskID": record.taskID ?? NSNull(),
            "estimatedCost": record.estimatedCost,
            "actualCost": record.actualCost,
            "costDelta": record.actualCost - record.estimatedCost,
            "estimatedTokens": record.estimatedTokens,
            "actualTokens": record.actualTokens,
            "tokenDelta": record.actualTokens - record.estimatedTokens,
            "inputTokens": record.inputTokens ?? NSNull(),
            "outputTokens": record.outputTokens ?? NSNull(),
            "requestCount": record.requestCount ?? NSNull(),
            "signal": record.signal.rawValue,
            "followUpRequired": record.followUpRequired,
            "win": record.isWin,
            "selectedBy": record.selectedBy ?? NSNull(),
            "alternatives": record.alternatives,
            "routingReason": record.routingReason ?? NSNull(),
            "metadata": record.metadata
        ]
    }

    private static func smartRoutingRouteDictionary(_ route: SmartRoutingRouteStats) -> [String: Any] {
        [
            "routeKey": route.routeKey,
            "provider": route.providerID,
            "model": route.model,
            "taskIntent": route.taskIntent,
            "runCount": route.runCount,
            "winCount": route.winCount,
            "followUpCount": route.followUpCount,
            "failedCount": route.failedCount,
            "unknownCount": route.unknownCount,
            "winRate": route.winRate,
            "followUpRate": route.followUpRate,
            "estimatedCostTotal": route.estimatedCostTotal,
            "actualCostTotal": route.actualCostTotal,
            "estimatedTokensTotal": route.estimatedTokensTotal,
            "actualTokensTotal": route.actualTokensTotal,
            "averageCostDelta": route.averageCostDelta,
            "averageTokenDelta": route.averageTokenDelta,
            "lastRunAt": ISO8601DateFormatter().string(from: route.lastRunAt)
        ]
    }

    private static func jsonData(_ payload: [String: Any]) -> Data {
        (try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])) ?? Data("{}".utf8)
    }
}
