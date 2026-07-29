import Foundation

extension ProviderUsage {
    mutating func apply(localUsage: LocalAgentUsageAppliedSnapshot) {
        let calendar = Calendar.current
        let dayKey = Self.localUsageDayKey(localUsage.occurredAt, calendar: calendar)
        let monthKey = Self.localUsageMonthKey(localUsage.occurredAt, calendar: calendar)
        var summary = localAgentUsage ?? LocalAgentUsageSummary(
            tokensToday: 0,
            requestCountToday: 0,
            requestCountMonth: 0,
            spendToday: 0,
            spendMonth: 0,
            dayKey: dayKey,
            monthKey: monthKey,
            lastUpdated: localUsage.occurredAt,
            sourceDetail: localUsage.sourceDetail
        )
        if summary.dayKey != dayKey {
            summary.tokensToday = 0
            summary.requestCountToday = 0
            summary.spendToday = 0
            summary.dayKey = dayKey
        }
        if summary.monthKey != monthKey {
            summary.requestCountMonth = 0
            summary.spendMonth = 0
            summary.monthKey = monthKey
        }
        summary.tokensToday += localUsage.tokenDelta
        summary.requestCountToday += localUsage.requestDelta
        summary.requestCountMonth += localUsage.requestDelta
        summary.spendToday += localUsage.costDelta
        summary.spendMonth += localUsage.costDelta
        summary.lastUpdated = localUsage.occurredAt
        summary.sourceDetail = localUsage.sourceDetail
        localAgentUsage = summary

        guard sourceKind != .live && sourceKind != .ccSwitch else { return }
        contextTokens = localUsage.contextTokenTotal > 0 ? localUsage.contextTokenTotal : contextTokens
        contextWindowSize = localUsage.contextWindowSize ?? contextWindowSize
        current = 0
        limit = 0
        quotaLimitKnown = false
        unit = "tokens"
        tokensToday = summary.tokensToday
        requestCountToday = summary.requestCountToday
        requestCountMonth = summary.requestCountMonth
        requestCountKnown = true
        currencyCode = "USD"
        spendTodayKnown = true
        spendMonthKnown = true
        spendToday = summary.spendToday
        spendMonth = summary.spendMonth
        resetAt = localUsage.rateLimitResetAt ?? resetAt
        lastUpdated = localUsage.occurredAt
        let historyValue = localUsage.contextTokenTotal > 0
            ? localUsage.contextTokenTotal
            : summary.tokensToday
        history.append(UsagePoint(timestamp: localUsage.occurredAt, value: historyValue))
        if history.count > 48 {
            history.removeFirst(history.count - 48)
        }
        dataSource = .localAgent
        sourceUpdatedAt = localUsage.occurredAt
        healthAlerts = nil
        sourceDetail = localUsage.sourceDetail
    }

    private static func localUsageDayKey(_ date: Date, calendar: Calendar) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(
            format: "%04d-%02d-%02d",
            components.year ?? 0,
            components.month ?? 0,
            components.day ?? 0
        )
    }

    private static func localUsageMonthKey(_ date: Date, calendar: Calendar) -> String {
        let components = calendar.dateComponents([.year, .month], from: date)
        return String(
            format: "%04d-%02d",
            components.year ?? 0,
            components.month ?? 0
        )
    }
}
