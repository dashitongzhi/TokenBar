import Foundation

extension ProviderUsage {
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
}
