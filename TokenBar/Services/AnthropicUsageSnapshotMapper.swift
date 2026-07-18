import Foundation

struct AnthropicUsageSnapshotMapper {
    private let calendar: Calendar

    init(calendar: Calendar) {
        self.calendar = calendar
    }

    func snapshot(
        from usage: AnthropicUsageResponse,
        costs: AnthropicCostResponse,
        now: Date,
        resetAt: Date
    ) -> AnthropicUsageSnapshot {
        let sortedUsageBuckets = usage.data.sorted { $0.startingAt < $1.startingAt }
        var cumulativeTokens = 0.0
        var tokensToday = 0.0
        var requestsMonth = 0
        var requestsToday = 0
        let todayStart = calendar.startOfDay(for: now)

        let history = sortedUsageBuckets.map { bucket in
            let bucketTokens = bucket.results.reduce(0.0) { $0 + $1.tokenTotal }
            let bucketRequests = bucket.results.reduce(0) { $0 + ($1.requestCount ?? 0) }
            cumulativeTokens += bucketTokens
            requestsMonth += bucketRequests
            if bucket.startingAt >= todayStart {
                tokensToday += bucketTokens
                requestsToday += bucketRequests
            }
            return UsagePoint(timestamp: bucket.startingAt, value: cumulativeTokens)
        }

        var currency = "usd"
        var spendToday = 0.0
        let spendMonth = costs.data.reduce(0.0) { total, bucket in
            let bucketSpend = bucket.results.reduce(0.0) { subtotal, result in
                if let resultCurrency = result.currency?.trimmingCharacters(in: .whitespacesAndNewlines), resultCurrency.isEmpty == false {
                    currency = resultCurrency
                }
                return subtotal + result.amountMajorUnits
            }
            if bucket.startingAt >= todayStart {
                spendToday += bucketSpend
            }
            return total + bucketSpend
        }

        return AnthropicUsageSnapshot(
            tokenTotal: cumulativeTokens,
            tokenToday: tokensToday,
            requestCountMonth: requestsMonth,
            requestCountToday: requestsToday,
            spendToday: spendToday,
            spendMonth: spendMonth,
            currency: currency,
            resetAt: resetAt,
            fetchedAt: now,
            history: history
        )
    }
}
