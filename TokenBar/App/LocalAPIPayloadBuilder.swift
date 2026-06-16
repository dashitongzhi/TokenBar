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
                    "spendToday": workspace.spendToday,
                    "allowedProviders": workspace.allowedProviderIDs,
                    "blockedModels": workspace.blockedModels,
                    "requireCompanyKey": workspace.requireCompanyKey
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

    private static func jsonData(_ payload: [String: Any]) -> Data {
        (try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])) ?? Data("{}".utf8)
    }
}
