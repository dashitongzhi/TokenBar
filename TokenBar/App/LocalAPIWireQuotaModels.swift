import Foundation

@MainActor
extension LocalAPIWire {
    struct Quota: Encodable {
        var platform: String
        var displayName: String
        var status: String
        var healthAlerts: [HealthAlert]
        var dataSource: String
        var sourceDetail: String
        var metrics: [QuotaMetric]

        init(_ provider: ProviderUsage) {
            platform = provider.id
            displayName = provider.name
            status = provider.status.rawValue
            healthAlerts = provider.activeHealthAlerts.map(HealthAlert.init)
            dataSource = provider.sourceKind.rawValue
            sourceDetail = provider.sourceDescription
            metrics = [QuotaMetric(provider)]
        }
    }

    struct QuotaMetric: Encodable {
        var name: String
        var current: Double
        var limit: Nullable<Double>
        var unit: String
        var remaining: Nullable<Double>
        var usageRatio: Double
        var burnRatePerHour: Double
        var resetAt: String
        var dataSource: String
        var sourceDetail: String
        var sourceUpdatedAt: Nullable<String>
        var quotaLimitKnown: Bool
        var tokensToday: Double
        var requestsKnown: Bool
        var requestsToday: Nullable<Int>
        var requestsMonth: Nullable<Int>
        var spendTodayKnown: Bool
        var spendToday: Nullable<Double>
        var spendMonthKnown: Bool
        var spendMonth: Nullable<Double>
        var currency: String
        var localAgentUsage: Nullable<LocalAgentUsageSummaryPayload>
        var predictedExhaustion: Nullable<String>

        init(_ provider: ProviderUsage) {
            name = provider.unit
            current = provider.current
            limit = Nullable(provider.hasKnownQuotaLimit ? provider.limit : nil)
            unit = provider.unit
            remaining = Nullable(provider.knownRemaining)
            usageRatio = provider.usageRatio
            burnRatePerHour = provider.burnRatePerHour
            resetAt = LocalAPIWire.timestamp(provider.resetAt)
            dataSource = provider.sourceKind.rawValue
            sourceDetail = provider.sourceDescription
            sourceUpdatedAt = Nullable(provider.sourceUpdatedAt.map(LocalAPIWire.timestamp))
            quotaLimitKnown = provider.hasKnownQuotaLimit
            tokensToday = provider.todayTokenCount
            requestsKnown = provider.hasKnownRequestCount
            requestsToday = Nullable(provider.knownTodayRequestCount)
            requestsMonth = Nullable(provider.knownRequestCount)
            spendTodayKnown = provider.hasKnownSpendToday
            spendToday = Nullable(provider.hasKnownSpendToday ? provider.spendToday : nil)
            spendMonthKnown = provider.hasKnownSpendMonth
            spendMonth = Nullable(provider.hasKnownSpendMonth ? provider.spendMonth : nil)
            currency = provider.displayCurrency
            localAgentUsage = Nullable(provider.localAgentUsage.map(LocalAgentUsageSummaryPayload.init))
            predictedExhaustion = Nullable(provider.predictedExhaustion.map(LocalAPIWire.timestamp))
        }
    }

    struct LocalAgentUsageSummaryPayload: Encodable {
        var tokensToday: Double
        var requestCountToday: Int
        var requestCountMonth: Int
        var spendToday: Double
        var spendMonth: Double
        var lastUpdated: String
        var sourceDetail: String

        init(_ summary: LocalAgentUsageSummary) {
            tokensToday = summary.tokensToday
            requestCountToday = summary.requestCountToday
            requestCountMonth = summary.requestCountMonth
            spendToday = summary.spendToday
            spendMonth = summary.spendMonth
            lastUpdated = LocalAPIWire.timestamp(summary.lastUpdated)
            sourceDetail = summary.sourceDetail
        }
    }

    struct HealthAlert: Encodable {
        var status: String
        var title: String
        var detail: String

        init(_ alert: ProviderHealthAlert) {
            status = alert.status.rawValue
            title = alert.title
            detail = alert.detail
        }
    }

    struct Pace: Encodable {
        var platform: String
        var displayName: String
        var status: String
        var dataSource: String
        var sourceDetail: String
        var burnRatePerHour: Double
        var remaining: Nullable<Double>
        var quotaLimitKnown: Bool
        var tokensToday: Double
        var tokensMonth: Double
        var requestsKnown: Bool
        var requestsToday: Nullable<Int>
        var requestsMonth: Nullable<Int>
        var spendTodayKnown: Bool
        var spendToday: Nullable<Double>
        var spendMonthKnown: Bool
        var spendMonth: Nullable<Double>
        var currency: String
        var predictedExhaustion: Nullable<String>
        var healthAlerts: [HealthAlert]
        var recommendation: String

        init(provider: ProviderUsage, recommendation: String) {
            platform = provider.id
            displayName = provider.name
            status = provider.status.rawValue
            dataSource = provider.sourceKind.rawValue
            sourceDetail = provider.sourceDescription
            burnRatePerHour = provider.burnRatePerHour
            remaining = Nullable(provider.knownRemaining)
            quotaLimitKnown = provider.hasKnownQuotaLimit
            tokensToday = provider.todayTokenCount
            tokensMonth = provider.current
            requestsKnown = provider.hasKnownRequestCount
            requestsToday = Nullable(provider.knownTodayRequestCount)
            requestsMonth = Nullable(provider.knownRequestCount)
            spendTodayKnown = provider.hasKnownSpendToday
            spendToday = Nullable(provider.hasKnownSpendToday ? provider.spendToday : nil)
            spendMonthKnown = provider.hasKnownSpendMonth
            spendMonth = Nullable(provider.hasKnownSpendMonth ? provider.spendMonth : nil)
            currency = provider.displayCurrency
            predictedExhaustion = Nullable(provider.predictedExhaustion.map(LocalAPIWire.timestamp))
            healthAlerts = provider.activeHealthAlerts.map(HealthAlert.init)
            self.recommendation = recommendation
        }
    }
}
