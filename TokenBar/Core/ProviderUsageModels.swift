import Foundation

enum UsageStatus: String, Codable {
    case healthy
    case warning
    case critical

    var rank: Int {
        switch self {
        case .healthy: 0
        case .warning: 1
        case .critical: 2
        }
    }
}

enum LocalAPIStatus: Equatable {
    case disabled
    case starting(port: UInt16)
    case running(port: UInt16)
    case stopped
    case failed(String)
}

enum UsageDataSource: String, Codable {
    case live
    case localAgent
    case ccSwitch
    case liveUnavailable
    case unsupported
    case error
}

struct ProviderHealthAlert: Codable, Equatable, Identifiable {
    var status: UsageStatus
    var title: String
    var detail: String

    var id: String {
        [status.rawValue, title, detail].joined(separator: "|")
    }
}

enum ModelUsageSource: String, Codable {
    case localAgent
    case configured
}

enum ModelCatalogSource: String, Codable {
    case providerAPI
    case ccSwitchConfig
    case localAgentConfig
}

struct ModelCatalogItem: Identifiable, Codable, Equatable {
    var providerID: String
    var modelID: String
    var displayName: String
    var source: ModelCatalogSource
    var baseURL: String?
    var configPath: String?
    var fetchedAt: Date

    var id: String {
        [providerID, modelID.lowercased(), source.rawValue, baseURL ?? "", configPath ?? ""].joined(separator: "|")
    }
}

struct UsagePoint: Identifiable, Codable, Equatable {
    var id = UUID()
    var timestamp: Date
    var value: Double
}

struct LocalAgentUsageSummary: Codable, Equatable {
    var tokensToday: Double
    var requestCountToday: Int
    var requestCountMonth: Int
    var spendToday: Double
    var spendMonth: Double
    var lastUpdated: Date
    var sourceDetail: String
}

struct ProviderUsage: Identifiable, Codable, Equatable {
    var id: String
    var name: String
    var category: String
    var symbolName: String
    var current: Double
    var limit: Double
    var unit: String
    var spendToday: Double
    var spendMonth: Double
    var resetAt: Date
    var lastUpdated: Date
    var history: [UsagePoint]
    var dataSource: UsageDataSource?
    var sourceDetail: String?
    var sourceUpdatedAt: Date?
    var tokensToday: Double?
    var requestCountToday: Int?
    var requestCountMonth: Int?
    var currencyCode: String?
    var quotaLimitKnown: Bool?
    var requestCountKnown: Bool?
    var spendTodayKnown: Bool? = nil
    var spendMonthKnown: Bool? = nil
    var healthAlerts: [ProviderHealthAlert]? = nil
    var localAgentUsage: LocalAgentUsageSummary? = nil

    var usageRatio: Double {
        guard hasKnownQuotaLimit else { return 0 }
        return min(max(current / limit, 0), 1.5)
    }

    var remaining: Double {
        knownRemaining ?? 0
    }

    var knownRemaining: Double? {
        guard hasKnownQuotaLimit else { return nil }
        return max(limit - current, 0)
    }

    var burnRatePerHour: Double {
        let sorted = history.sorted { $0.timestamp < $1.timestamp }
        guard sorted.count >= 2, let first = sorted.first, let last = sorted.last else { return 0 }
        let deltaValue = last.value - first.value
        let hours = max(last.timestamp.timeIntervalSince(first.timestamp) / 3600, 0.01)
        return max(deltaValue / hours, 0)
    }

    var predictedExhaustion: Date? {
        let rate = burnRatePerHour
        guard let knownRemaining, rate > 0, knownRemaining > 0 else { return nil }
        return Date().addingTimeInterval((remaining / rate) * 3600)
    }

    var hasKnownQuotaLimit: Bool {
        (quotaLimitKnown ?? true) && limit > 0
    }

    var requestCount: Int {
        requestCountMonth ?? 0
    }

    var todayRequestCount: Int {
        requestCountToday ?? 0
    }

    var hasKnownRequestCount: Bool {
        requestCountKnown ?? (requestCountMonth != nil || requestCountToday != nil)
    }

    var knownRequestCount: Int? {
        hasKnownRequestCount ? requestCount : nil
    }

    var knownTodayRequestCount: Int? {
        hasKnownRequestCount ? todayRequestCount : nil
    }

    var todayTokenCount: Double {
        tokensToday ?? 0
    }

    var displayCurrency: String {
        let value = (currencyCode ?? "USD").trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? "USD" : value.uppercased()
    }

    var hasKnownSpendToday: Bool {
        spendTodayKnown ?? true
    }

    var hasKnownSpendMonth: Bool {
        spendMonthKnown ?? true
    }

    var status: UsageStatus {
        let quotaStatus: UsageStatus
        if let predictedExhaustion {
            let hours = predictedExhaustion.timeIntervalSinceNow / 3600
            if hours < 6 {
                quotaStatus = .critical
            } else if hours < 24 {
                quotaStatus = .warning
            } else {
                quotaStatus = .healthy
            }
        } else if usageRatio >= 0.9 {
            quotaStatus = .critical
        } else if usageRatio >= 0.7 {
            quotaStatus = .warning
        } else {
            quotaStatus = .healthy
        }

        return activeHealthAlerts.reduce(quotaStatus) { current, alert in
            alert.status.rank > current.rank ? alert.status : current
        }
    }

    var activeHealthAlerts: [ProviderHealthAlert] {
        healthAlerts ?? []
    }

    var primaryHealthAlert: ProviderHealthAlert? {
        activeHealthAlerts.sorted {
            if $0.status != $1.status {
                return $0.status.rank > $1.status.rank
            }
            return $0.title < $1.title
        }.first
    }

    var displayHealthAlert: ProviderHealthAlert? {
        guard let alert = primaryHealthAlert, alert.status.rank >= status.rank else {
            return nil
        }
        return alert
    }

    var sourceKind: UsageDataSource {
        dataSource ?? .unsupported
    }

    var sourceDescription: String {
        sourceDetail ?? ""
    }

    var isLive: Bool {
        sourceKind == .live
    }

    var isUsageConnected: Bool {
        sourceKind == .live || sourceKind == .localAgent
    }

    mutating func markSource(_ source: UsageDataSource, detail: String, now: Date = .now, clearUsage: Bool = false) {
        if clearUsage {
            current = 0
            limit = 0
            spendToday = 0
            spendMonth = 0
            history = [UsagePoint(timestamp: now, value: 0)]
            tokensToday = 0
            requestCountToday = 0
            requestCountMonth = 0
            currencyCode = "USD"
            quotaLimitKnown = false
            requestCountKnown = false
            spendTodayKnown = false
            spendMonthKnown = false
        }
        dataSource = source
        sourceDetail = detail
        sourceUpdatedAt = now
        lastUpdated = now
        healthAlerts = source == .error ? [
            ProviderHealthAlert(status: .critical, title: "Provider refresh failed", detail: detail)
        ] : nil
    }
}
