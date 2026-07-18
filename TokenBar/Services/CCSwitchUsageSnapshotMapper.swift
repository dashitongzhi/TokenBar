import Foundation

enum CCSwitchUsageSnapshotMapper {
    static func buildSnapshot(
        providerRecords: [CCSwitchProviderRecord],
        rollups: [CCSwitchDailyRollup],
        health: [String: CCSwitchProviderHealth],
        deepSeekBalance: DeepSeekBalance?,
        quotaWindows: [CCSwitchKnownProvider: [CCSwitchQuotaWindow]] = [:],
        now: Date = .now
    ) -> CCSwitchUsageSnapshot {
        let recordsByCompositeID = Dictionary(uniqueKeysWithValues: providerRecords.map { ("\($0.appType):\($0.id)", $0) })
        let recordsByID = Dictionary(grouping: providerRecords, by: \.id)
        let today = dayString(now)
        var aggregates: [CCSwitchKnownProvider: CCSwitchAggregate] = [:]

        for rollup in rollups {
            guard let provider = CCSwitchProviderNormalizer.normalize(
                rollup: rollup,
                recordsByCompositeID: recordsByCompositeID,
                recordsByID: recordsByID
            ) else {
                continue
            }
            aggregates[provider, default: CCSwitchAggregate(provider: provider)].add(rollup: rollup, isToday: rollup.date == today)
        }

        for record in providerRecords {
            guard let provider = CCSwitchProviderNormalizer.normalize(record: record) else { continue }
            if aggregates[provider] == nil {
                aggregates[provider] = CCSwitchAggregate(provider: provider)
            }
        }

        let monthResetAt = Calendar.current.date(
            byAdding: DateComponents(month: 1),
            to: Calendar.current.date(from: Calendar.current.dateComponents([.year, .month], from: now)) ?? now
        ) ?? now.addingTimeInterval(30 * 24 * 3600)

        let snapshots = aggregates.values
            .sorted { $0.provider.sortOrder < $1.provider.sortOrder }
            .map { aggregate in
                snapshot(
                    aggregate: aggregate,
                    providerRecords: providerRecords,
                    health: health,
                    deepSeekBalance: deepSeekBalance,
                    quotaWindows: quotaWindows,
                    monthResetAt: monthResetAt,
                    now: now
                )
            }

        return CCSwitchUsageSnapshot(providers: snapshots, fetchedAt: now)
    }

    static func rollingStartString(now: Date = .now) -> String {
        let start = Calendar.current.date(byAdding: .day, value: -30, to: now) ?? now.addingTimeInterval(-30 * 24 * 3600)
        return dayString(start)
    }

    private static func snapshot(
        aggregate: CCSwitchAggregate,
        providerRecords: [CCSwitchProviderRecord],
        health: [String: CCSwitchProviderHealth],
        deepSeekBalance: DeepSeekBalance?,
        quotaWindows: [CCSwitchKnownProvider: [CCSwitchQuotaWindow]],
        monthResetAt: Date,
        now: Date
    ) -> CCSwitchProviderUsageSnapshot {
        var detail: String
        if aggregate.requestCountMonth > 0 {
            let models = aggregate.models.isEmpty ? "unknown models" : aggregate.models.prefix(3).joined(separator: ", ")
            detail = "CC Switch local proxy rollups. \(aggregate.requestCountMonth) requests in the rolling 30-day window across \(models)."
        } else {
            detail = "CC Switch provider config detected; no rolling 30-day proxy usage was found."
        }
        let healthyRecords = providerRecords.filter { CCSwitchProviderNormalizer.normalize(record: $0) == aggregate.provider }
        let healthItems = healthyRecords.compactMap { health["\($0.appType):\($0.id)"] }
        if let failures = maxConsecutiveFailures(from: healthItems) {
            detail += " CC Switch health reports \(failures) consecutive failures."
        } else if healthItems.contains(where: { $0.isHealthy }) {
            detail += " CC Switch health has a recent successful route."
        }
        let healthAlerts = healthAlerts(
            provider: aggregate.provider,
            healthItems: healthItems,
            deepSeekBalance: aggregate.provider == .deepSeek ? deepSeekBalance : nil
        )
        if aggregate.provider == .deepSeek, let deepSeekBalance {
            detail += " DeepSeek live balance: \(deepSeekBalance.currency) \(String(format: "%.2f", deepSeekBalance.totalBalance)); API available: \(deepSeekBalance.isAvailable ? "yes" : "no")."
        }
        let providerQuotaWindows = quotaWindows[aggregate.provider] ?? []
        if let primaryWindow = primaryQuotaWindow(from: providerQuotaWindows) {
            detail += quotaDetail(primaryWindow: primaryWindow, windows: providerQuotaWindows)
        }
        if healthyRecords.contains(where: { $0.hasAPIKey }) {
            detail += " API key was detected in CC Switch config and used only in memory."
        }
        let dailyLimit = healthyRecords.compactMap(\.dailySpendLimit).max()
        let monthlyLimit = healthyRecords.compactMap(\.monthlySpendLimit).max()
        if dailyLimit != nil || monthlyLimit != nil {
            let daily = dailyLimit.map { String(format: "daily $%.2f", $0) }
            let monthly = monthlyLimit.map { String(format: "monthly $%.2f", $0) }
            detail += " Configured spend limits: \([daily, monthly].compactMap { $0 }.joined(separator: ", "))."
        }

        return CCSwitchProviderUsageSnapshot(
            providerID: aggregate.provider.providerID,
            displayName: aggregate.provider.displayName,
            category: "CC Switch",
            symbolName: aggregate.provider.symbolName,
            tokenTotalToday: aggregate.tokenTotalToday,
            tokenTotalMonth: aggregate.tokenTotalMonth,
            requestCountToday: aggregate.requestCountToday,
            requestCountMonth: aggregate.requestCountMonth,
            spendToday: aggregate.spendToday,
            spendMonth: aggregate.spendMonth,
            dailySpendLimit: dailyLimit,
            monthlySpendLimit: monthlyLimit,
            monthResetAt: monthResetAt,
            quotaWindows: providerQuotaWindows,
            history: aggregate.history(),
            healthAlerts: healthAlerts,
            sourceDetail: detail,
            fetchedAt: now
        )
    }

    private static func quotaDetail(primaryWindow: CCSwitchQuotaWindow, windows: [CCSwitchQuotaWindow]) -> String {
        var detail = " Live quota from CC Switch provider key: \(primaryWindow.modelName) \(primaryWindow.intervalWindowLabel) is \(Int(primaryWindow.intervalUsedPercent))% used"
        if primaryWindow.intervalTotalCount > 0 {
            detail += " (\(Int(primaryWindow.intervalUsedCount))/\(Int(primaryWindow.intervalTotalCount)))"
        } else if let remaining = primaryWindow.intervalRemainingPercent {
            detail += " (\(Int(remaining))% remaining)"
        }
        detail += "; weekly \(primaryWindow.weeklyWindowLabel) is \(Int(primaryWindow.weeklyUsedPercent))% used"
        if primaryWindow.weeklyTotalCount > 0 {
            detail += " (\(Int(primaryWindow.weeklyUsedCount))/\(Int(primaryWindow.weeklyTotalCount)))"
        } else if let remaining = primaryWindow.weeklyRemainingPercent {
            detail += " (\(Int(remaining))% remaining)"
        }
        detail += "."
        let additionalNames = windows
            .filter { $0.modelName != primaryWindow.modelName }
            .prefix(3)
            .map(\.modelName)
            .joined(separator: ", ")
        if additionalNames.isEmpty == false {
            detail += " Additional quota windows: \(additionalNames)."
        }
        return detail
    }

    private static func dayString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private static func primaryQuotaWindow(from windows: [CCSwitchQuotaWindow]) -> CCSwitchQuotaWindow? {
        windows.first(where: { $0.modelName == "general" && ($0.hasKnownIntervalLimit || $0.hasKnownWeeklyLimit) })
            ?? windows.first(where: { $0.hasKnownIntervalLimit || $0.hasKnownWeeklyLimit })
            ?? windows.first
    }

    private static func healthAlerts(
        provider: CCSwitchKnownProvider,
        healthItems: [CCSwitchProviderHealth],
        deepSeekBalance: DeepSeekBalance?
    ) -> [ProviderHealthAlert] {
        var alerts: [ProviderHealthAlert] = []
        if let failures = maxConsecutiveFailures(from: healthItems) {
            let status: UsageStatus = failures >= 10 ? .critical : .warning
            alerts.append(ProviderHealthAlert(
                status: status,
                title: "\(failures) consecutive CC Switch failures",
                detail: "\(provider.displayName) has \(failures) consecutive failed CC Switch route checks."
            ))
        }

        if provider == .deepSeek, let deepSeekBalance {
            let amount = "\(deepSeekBalance.currency.uppercased()) \(String(format: "%.2f", deepSeekBalance.totalBalance))"
            if deepSeekBalance.totalBalance < 0, deepSeekBalance.isAvailable == false {
                alerts.append(ProviderHealthAlert(
                    status: .critical,
                    title: "Negative balance and API unavailable",
                    detail: "DeepSeek balance is \(amount), and the balance API reports unavailable."
                ))
            } else if deepSeekBalance.totalBalance < 0 {
                alerts.append(ProviderHealthAlert(
                    status: .critical,
                    title: "Negative provider balance",
                    detail: "DeepSeek balance is \(amount)."
                ))
            } else if deepSeekBalance.isAvailable == false {
                alerts.append(ProviderHealthAlert(
                    status: .critical,
                    title: "Provider API unavailable",
                    detail: "DeepSeek balance API reports unavailable."
                ))
            }
        }
        return alerts
    }

    private static func maxConsecutiveFailures(from healthItems: [CCSwitchProviderHealth]) -> Int? {
        healthItems
            .filter { $0.isHealthy == false && $0.consecutiveFailures > 0 }
            .map(\.consecutiveFailures)
            .max()
    }
}
