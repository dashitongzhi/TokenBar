import Foundation

extension ProviderUsage {
    mutating func apply(snapshot: OpenAIUsageSnapshot) {
        current = snapshot.tokenTotal
        limit = 0
        unit = "tokens"
        tokensToday = snapshot.tokenToday
        requestCountToday = snapshot.requestCountToday
        requestCountMonth = snapshot.requestCountMonth
        currencyCode = snapshot.currency.uppercased()
        quotaLimitKnown = false
        requestCountKnown = true
        spendTodayKnown = true
        spendMonthKnown = true
        spendToday = snapshot.spendToday
        spendMonth = snapshot.spendMonth
        resetAt = snapshot.resetAt
        lastUpdated = snapshot.fetchedAt
        history = snapshot.history.isEmpty ? [UsagePoint(timestamp: snapshot.fetchedAt, value: snapshot.tokenTotal)] : snapshot.history
        dataSource = .live
        sourceUpdatedAt = snapshot.fetchedAt
        healthAlerts = nil
        sourceDetail = "OpenAI organization usage and cost APIs. \(snapshot.requestCountMonth) requests this month, \(snapshot.currency.uppercased()) costs. Organization quota limits stay in the OpenAI console."
    }

    mutating func apply(snapshot: AnthropicUsageSnapshot) {
        current = snapshot.tokenTotal
        limit = 0
        unit = "tokens"
        tokensToday = snapshot.tokenToday
        requestCountToday = snapshot.requestCountToday
        requestCountMonth = snapshot.requestCountMonth
        currencyCode = snapshot.currency.uppercased()
        quotaLimitKnown = false
        requestCountKnown = false
        spendTodayKnown = true
        spendMonthKnown = true
        spendToday = snapshot.spendToday
        spendMonth = snapshot.spendMonth
        resetAt = snapshot.resetAt
        lastUpdated = snapshot.fetchedAt
        history = snapshot.history.isEmpty ? [UsagePoint(timestamp: snapshot.fetchedAt, value: snapshot.tokenTotal)] : snapshot.history
        dataSource = .live
        sourceUpdatedAt = snapshot.fetchedAt
        healthAlerts = nil
        sourceDetail = "Anthropic Usage and Cost Admin API. Token and cost data are live; message request counts and console spend limits stay outside this public Admin API."
    }

    mutating func apply(snapshot: OpenRouterCreditsSnapshot) {
        current = snapshot.totalUsage
        limit = snapshot.totalCredits
        unit = "credits"
        tokensToday = 0
        requestCountToday = 0
        requestCountMonth = 0
        currencyCode = "USD"
        quotaLimitKnown = snapshot.totalCredits > 0
        requestCountKnown = false
        spendTodayKnown = false
        spendMonthKnown = false
        spendToday = 0
        spendMonth = 0
        resetAt = snapshot.fetchedAt
        lastUpdated = snapshot.fetchedAt
        history = snapshot.history.isEmpty ? [UsagePoint(timestamp: snapshot.fetchedAt, value: snapshot.totalUsage)] : snapshot.history
        dataSource = .live
        sourceUpdatedAt = snapshot.fetchedAt
        healthAlerts = nil
        sourceDetail = "OpenRouter Credits API. Total credits and total usage are live; token buckets, request counts, and period spend are not exposed by this endpoint."
    }

    mutating func apply(snapshot: CodexUsageSnapshot) {
        current = snapshot.primaryUsedPercent
        limit = 100
        unit = "percent"
        tokensToday = 0
        requestCountToday = 0
        requestCountMonth = 0
        currencyCode = "USD"
        quotaLimitKnown = true
        requestCountKnown = false
        spendTodayKnown = false
        spendMonthKnown = false
        spendToday = 0
        spendMonth = 0
        resetAt = snapshot.primaryResetAt
        lastUpdated = snapshot.fetchedAt
        history = snapshot.history
        dataSource = .live
        sourceUpdatedAt = snapshot.fetchedAt
        healthAlerts = nil

        let primaryLabel = Self.quotaWindowLabel(seconds: snapshot.primaryWindowSeconds, fallback: "5-hour window")
        var detail = "Codex login quota from local ~/.codex/auth.json and ChatGPT wham usage. \(primaryLabel) is \(Int(snapshot.primaryUsedPercent))% used."
        if let secondaryUsedPercent = snapshot.secondaryUsedPercent, let secondaryResetAt = snapshot.secondaryResetAt {
            let formatter = RelativeDateTimeFormatter()
            formatter.unitsStyle = .short
            let secondaryLabel = Self.quotaWindowLabel(seconds: snapshot.secondaryWindowSeconds, fallback: "7-day window")
            detail += " \(secondaryLabel) is \(Int(secondaryUsedPercent))% used and resets \(formatter.localizedString(for: secondaryResetAt, relativeTo: snapshot.fetchedAt))."
        }
        if let planType = snapshot.planType, planType.isEmpty == false {
            detail += " Plan: \(planType.uppercased())."
        }
        if snapshot.allowed == false || snapshot.limitReached {
            detail += " Upstream reports the Codex account is currently rate limited."
        }
        sourceDetail = detail
    }

    mutating func apply(snapshot: CCSwitchProviderUsageSnapshot) {
        if let quotaWindow = Self.primaryQuotaWindow(from: snapshot.quotaWindows),
           quotaWindow.hasKnownIntervalLimit || quotaWindow.hasKnownWeeklyLimit {
            current = quotaWindow.intervalUsedPercent
            limit = 100
            unit = "percent"
            quotaLimitKnown = true
            resetAt = quotaWindow.intervalResetAt
            history = [UsagePoint(timestamp: snapshot.fetchedAt, value: quotaWindow.intervalUsedPercent)]
        } else {
            current = snapshot.tokenTotalMonth
            limit = 0
            unit = "tokens"
            quotaLimitKnown = false
            resetAt = snapshot.monthResetAt
            history = snapshot.history.isEmpty
                ? [UsagePoint(timestamp: snapshot.fetchedAt, value: snapshot.tokenTotalMonth)]
                : snapshot.history
        }
        tokensToday = snapshot.tokenTotalToday
        requestCountToday = snapshot.requestCountToday
        requestCountMonth = snapshot.requestCountMonth
        currencyCode = "USD"
        requestCountKnown = true
        spendTodayKnown = true
        spendMonthKnown = true
        spendToday = snapshot.spendToday
        spendMonth = snapshot.spendMonth
        lastUpdated = snapshot.fetchedAt
        dataSource = .ccSwitch
        sourceUpdatedAt = snapshot.fetchedAt
        healthAlerts = snapshot.healthAlerts.isEmpty ? nil : snapshot.healthAlerts
        sourceDetail = snapshot.sourceDetail
    }

    mutating func apply(snapshot: MiniMaxUsageSnapshot) {
        current = snapshot.intervalUsedPercent
        limit = 100
        unit = "percent"
        tokensToday = tokensToday ?? 0
        requestCountToday = requestCountToday ?? 0
        requestCountMonth = requestCountMonth ?? 0
        currencyCode = "USD"
        quotaLimitKnown = true
        requestCountKnown = false
        spendTodayKnown = false
        spendMonthKnown = false
        spendToday = 0
        spendMonth = 0
        resetAt = snapshot.intervalResetAt
        lastUpdated = snapshot.fetchedAt
        history = snapshot.history
        dataSource = .live
        sourceUpdatedAt = snapshot.fetchedAt
        healthAlerts = nil
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        let intervalReset = formatter.localizedString(for: snapshot.intervalResetAt, relativeTo: snapshot.fetchedAt)
        let weeklyReset = formatter.localizedString(for: snapshot.weeklyResetAt, relativeTo: snapshot.fetchedAt)
        var detail = "MiniMax Token Plan quota from \(MiniMaxUsageSnapshot.tokenPlanURL). \(snapshot.primaryModelName) current \(snapshot.intervalWindowLabel) is \(Int(snapshot.intervalUsedPercent))% used"
        if snapshot.intervalTotalCount > 0 {
            detail += " (\(Int(snapshot.intervalUsedCount))/\(Int(snapshot.intervalTotalCount)))"
        } else if let remaining = snapshot.intervalRemainingPercent {
            detail += " (\(Int(remaining))% remaining)"
        }
        detail += " and resets \(intervalReset). Weekly \(snapshot.weeklyWindowLabel) is \(Int(snapshot.weeklyUsedPercent))% used"
        if snapshot.weeklyTotalCount > 0 {
            detail += " (\(Int(snapshot.weeklyUsedCount))/\(Int(snapshot.weeklyTotalCount)))"
        } else if let remaining = snapshot.weeklyRemainingPercent {
            detail += " (\(Int(remaining))% remaining)"
        }
        detail += " and resets \(weeklyReset)."
        if snapshot.modelWindows.count > 1 {
            let names = snapshot.modelWindows.dropFirst().prefix(3).map(\.modelName).joined(separator: ", ")
            if names.isEmpty == false {
                detail += " Additional windows: \(names)."
            }
        }
        sourceDetail = detail
    }

    private static func primaryQuotaWindow(from windows: [CCSwitchQuotaWindow]) -> CCSwitchQuotaWindow? {
        windows.first(where: { $0.modelName == "general" && ($0.hasKnownIntervalLimit || $0.hasKnownWeeklyLimit) })
            ?? windows.first(where: { $0.hasKnownIntervalLimit || $0.hasKnownWeeklyLimit })
            ?? windows.first
    }

    private static func quotaWindowLabel(seconds: TimeInterval?, fallback: String) -> String {
        guard let seconds, seconds > 0 else { return fallback }
        if seconds >= 86_400 {
            let days = max(Int(round(seconds / 86_400)), 1)
            return days == 1 ? "1-day window" : "\(days)-day window"
        }
        if seconds >= 3_600 {
            let hours = max(Int(round(seconds / 3_600)), 1)
            return hours == 1 ? "1-hour window" : "\(hours)-hour window"
        }
        let minutes = max(Int(round(seconds / 60)), 1)
        return minutes == 1 ? "1-minute window" : "\(minutes)-minute window"
    }
}
