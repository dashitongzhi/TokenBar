import Foundation

enum CCSwitchUsageRefreshResult {
    case success(CCSwitchUsageSnapshot)
    case unavailable(String)
    case failure(String)
}

struct CCSwitchUsageSnapshot {
    var providers: [CCSwitchProviderUsageSnapshot]
    var fetchedAt: Date
}

struct CCSwitchProviderUsageSnapshot: Equatable {
    var providerID: String
    var displayName: String
    var category: String
    var symbolName: String
    var tokenTotalToday: Double
    var tokenTotalMonth: Double
    var requestCountToday: Int
    var requestCountMonth: Int
    var spendToday: Double
    var spendMonth: Double
    var dailySpendLimit: Double?
    var monthlySpendLimit: Double?
    var monthResetAt: Date
    var quotaWindows: [CCSwitchQuotaWindow]
    var history: [UsagePoint]
    var healthAlerts: [ProviderHealthAlert]
    var sourceDetail: String
    var fetchedAt: Date
}

struct CCSwitchQuotaWindow: Equatable {
    var providerID: String
    var providerDisplayName: String
    var modelName: String
    var intervalUsedCount: Double
    var intervalTotalCount: Double
    var intervalUsedPercent: Double
    var intervalRemainingPercent: Double?
    var intervalStartAt: Date
    var intervalResetAt: Date
    var weeklyUsedCount: Double
    var weeklyTotalCount: Double
    var weeklyUsedPercent: Double
    var weeklyRemainingPercent: Double?
    var weeklyStartAt: Date
    var weeklyResetAt: Date

    var hasKnownIntervalLimit: Bool {
        intervalTotalCount > 0 || intervalRemainingPercent != nil
    }

    var hasKnownWeeklyLimit: Bool {
        weeklyTotalCount > 0 || weeklyRemainingPercent != nil
    }

    var intervalWindowLabel: String {
        Self.windowLabel(from: intervalStartAt, to: intervalResetAt)
    }

    var weeklyWindowLabel: String {
        Self.windowLabel(from: weeklyStartAt, to: weeklyResetAt)
    }

    private static func windowLabel(from start: Date, to end: Date) -> String {
        let seconds = max(end.timeIntervalSince(start), 0)
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

struct CCSwitchUsageService {
    private let fileManager: FileManager
    private let databaseURL: URL

    init(
        fileManager: FileManager = .default,
        databaseURL: URL = UserHomeDirectory.url
            .appendingPathComponent(".cc-switch/cc-switch.db")
    ) {
        self.fileManager = fileManager
        self.databaseURL = databaseURL
    }

    func refresh() async -> CCSwitchUsageRefreshResult {
        guard fileManager.fileExists(atPath: databaseURL.path) else {
            return .unavailable("CC Switch usage requires ~/.cc-switch/cc-switch.db.")
        }

        let snapshotURL = fileManager.temporaryDirectory
            .appendingPathComponent("tokenbar-cc-switch-\(UUID().uuidString).db")
        do {
            try fileManager.copyItem(at: databaseURL, to: snapshotURL)
            defer { try? fileManager.removeItem(at: snapshotURL) }

            let database = try CCSwitchDatabaseAdapter(path: snapshotURL.path)
            let databaseSnapshot = try database.load(since: Self.rollingStartString())
            async let deepSeekBalance = deepSeekBalance(from: databaseSnapshot.providerRecords)
            async let quotaWindows = liveQuotaWindows(from: databaseSnapshot.providerRecords)
            let snapshot = Self.buildSnapshot(
                providerRecords: databaseSnapshot.providerRecords,
                rollups: databaseSnapshot.dailyRollups,
                health: databaseSnapshot.providerHealth,
                deepSeekBalance: await deepSeekBalance,
                quotaWindows: await quotaWindows
            )
            return snapshot.providers.isEmpty
                ? .unavailable("CC Switch database was found, but no supported provider usage rollups were present.")
                : .success(snapshot)
        } catch {
            return .failure("CC Switch usage refresh failed: \(error.localizedDescription)")
        }
    }

    func configuredModelCatalogItems(now: Date = .now) -> [ModelCatalogItem] {
        guard fileManager.fileExists(atPath: databaseURL.path) else { return [] }
        let snapshotURL = fileManager.temporaryDirectory
            .appendingPathComponent("tokenbar-cc-switch-models-\(UUID().uuidString).db")
        do {
            try fileManager.copyItem(at: databaseURL, to: snapshotURL)
            defer { try? fileManager.removeItem(at: snapshotURL) }

            let database = try CCSwitchDatabaseAdapter(path: snapshotURL.path)
            let records = try database.providerRecords()
            return records.flatMap { record -> [ModelCatalogItem] in
                let providerID = Self.normalizedProvider(record: record)?.providerID ?? record.id
                let names = Array(Set(record.modelNames.filter { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false }))
                return names.sorted().map { model in
                    ModelCatalogItem(
                        providerID: providerID,
                        modelID: model,
                        displayName: model,
                        source: .ccSwitchConfig,
                        baseURL: record.baseURL,
                        configPath: databaseURL.path,
                        fetchedAt: now
                    )
                }
            }
        } catch {
            return []
        }
    }

    private func deepSeekBalance(from providers: [CCSwitchProviderRecord]) async -> DeepSeekBalance? {
        guard let apiKey = providers
            .compactMap({ record -> String? in
                guard Self.normalizedProvider(record: record) == .deepSeek else { return nil }
                return record.apiKey
            })
            .first(where: { $0.isEmpty == false }),
            let url = URL(string: "https://api.deepseek.com/user/balance")
        else {
            return nil
        }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                return nil
            }
            let decoded = try JSONDecoder().decode(DeepSeekBalanceResponse.self, from: data)
            guard let primary = decoded.balanceInfos.first else { return nil }
            return DeepSeekBalance(
                isAvailable: decoded.isAvailable,
                currency: primary.currency,
                totalBalance: Double(primary.totalBalance) ?? 0,
                toppedUpBalance: Double(primary.toppedUpBalance) ?? 0,
                grantedBalance: Double(primary.grantedBalance) ?? 0
            )
        } catch {
            return nil
        }
    }

    private func liveQuotaWindows(from providers: [CCSwitchProviderRecord]) async -> [CCSwitchKnownProvider: [CCSwitchQuotaWindow]] {
        var windowsByProvider: [CCSwitchKnownProvider: [CCSwitchQuotaWindow]] = [:]
        var seenKeys = Set<String>()

        for record in providers {
            guard Self.normalizedProvider(record: record) == .miniMax,
                  let apiKey = record.apiKey?.trimmingCharacters(in: .whitespacesAndNewlines),
                  apiKey.isEmpty == false,
                  seenKeys.insert(apiKey).inserted
            else {
                continue
            }

            guard let windows = await miniMaxQuotaWindows(apiKey: apiKey, record: record), windows.isEmpty == false else {
                continue
            }
            windowsByProvider[.miniMax, default: []].append(contentsOf: windows)
        }

        return windowsByProvider
    }

    private func miniMaxQuotaWindows(apiKey: String, record: CCSwitchProviderRecord) async -> [CCSwitchQuotaWindow]? {
        guard let url = URL(string: "https://api.minimaxi.com/v1/token_plan/remains") else { return nil }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue(apiKey, forHTTPHeaderField: "X-Api-Key")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("TokenBar", forHTTPHeaderField: "User-Agent")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                return nil
            }
            let decoded = try JSONDecoder().decode(CCSwitchMiniMaxQuotaResponse.self, from: data)
            guard decoded.baseResp?.statusCode ?? 0 == 0 else { return nil }
            return decoded.modelRemains.map { item in
                CCSwitchQuotaWindow(
                    providerID: CCSwitchKnownProvider.miniMax.providerID,
                    providerDisplayName: record.name.isEmpty ? CCSwitchKnownProvider.miniMax.displayName : record.name,
                    modelName: item.modelName,
                    intervalUsedCount: item.currentIntervalUsageCount,
                    intervalTotalCount: item.currentIntervalTotalCount,
                    intervalUsedPercent: Self.usedPercent(
                        used: item.currentIntervalUsageCount,
                        total: item.currentIntervalTotalCount,
                        remainingPercent: item.currentIntervalRemainingPercent
                    ),
                    intervalRemainingPercent: item.currentIntervalRemainingPercent,
                    intervalStartAt: Self.date(milliseconds: item.startTime),
                    intervalResetAt: Self.date(milliseconds: item.endTime),
                    weeklyUsedCount: item.currentWeeklyUsageCount,
                    weeklyTotalCount: item.currentWeeklyTotalCount,
                    weeklyUsedPercent: Self.usedPercent(
                        used: item.currentWeeklyUsageCount,
                        total: item.currentWeeklyTotalCount,
                        remainingPercent: item.currentWeeklyRemainingPercent
                    ),
                    weeklyRemainingPercent: item.currentWeeklyRemainingPercent,
                    weeklyStartAt: Self.date(milliseconds: item.weeklyStartTime),
                    weeklyResetAt: Self.date(milliseconds: item.weeklyEndTime)
                )
            }
        } catch {
            return nil
        }
    }

    private static func buildSnapshot(
        providerRecords: [CCSwitchProviderRecord],
        rollups: [CCSwitchDailyRollup],
        health: [String: CCSwitchProviderHealth],
        now: Date = .now
    ) -> CCSwitchUsageSnapshot {
        buildSnapshot(providerRecords: providerRecords, rollups: rollups, health: health, deepSeekBalance: nil, now: now)
    }

    private static func buildSnapshot(
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
            guard let provider = normalizedProvider(
                rollup: rollup,
                recordsByCompositeID: recordsByCompositeID,
                recordsByID: recordsByID
            ) else {
                continue
            }
            aggregates[provider, default: CCSwitchAggregate(provider: provider)].add(rollup: rollup, isToday: rollup.date == today)
        }

        for record in providerRecords {
            guard let provider = normalizedProvider(record: record) else { continue }
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
                var detail: String
                if aggregate.requestCountMonth > 0 {
                    let models = aggregate.models.isEmpty ? "unknown models" : aggregate.models.prefix(3).joined(separator: ", ")
                    detail = "CC Switch local proxy rollups. \(aggregate.requestCountMonth) requests in the rolling 30-day window across \(models)."
                } else {
                    detail = "CC Switch provider config detected; no rolling 30-day proxy usage was found."
                }
                let healthyRecords = providerRecords.filter { normalizedProvider(record: $0) == aggregate.provider }
                let healthItems = healthyRecords.compactMap { health["\($0.appType):\($0.id)"] }
                if let failures = Self.maxConsecutiveFailures(from: healthItems) {
                    detail += " CC Switch health reports \(failures) consecutive failures."
                } else if healthItems.contains(where: { $0.isHealthy }) {
                    detail += " CC Switch health has a recent successful route."
                }
                let healthAlerts = Self.healthAlerts(
                    provider: aggregate.provider,
                    healthItems: healthItems,
                    deepSeekBalance: aggregate.provider == .deepSeek ? deepSeekBalance : nil
                )
                if aggregate.provider == .deepSeek, let deepSeekBalance {
                    detail += " DeepSeek live balance: \(deepSeekBalance.currency) \(String(format: "%.2f", deepSeekBalance.totalBalance)); API available: \(deepSeekBalance.isAvailable ? "yes" : "no")."
                }
                let providerQuotaWindows = quotaWindows[aggregate.provider] ?? []
                if let primaryWindow = Self.primaryQuotaWindow(from: providerQuotaWindows) {
                    detail += " Live quota from CC Switch provider key: \(primaryWindow.modelName) \(primaryWindow.intervalWindowLabel) is \(Int(primaryWindow.intervalUsedPercent))% used"
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
                    let additionalNames = providerQuotaWindows
                        .filter { $0.modelName != primaryWindow.modelName }
                        .prefix(3)
                        .map(\.modelName)
                        .joined(separator: ", ")
                    if additionalNames.isEmpty == false {
                        detail += " Additional quota windows: \(additionalNames)."
                    }
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

        return CCSwitchUsageSnapshot(providers: snapshots, fetchedAt: now)
    }

    private static func normalizedProvider(
        rollup: CCSwitchDailyRollup,
        recordsByCompositeID: [String: CCSwitchProviderRecord],
        recordsByID: [String: [CCSwitchProviderRecord]]
    ) -> CCSwitchKnownProvider? {
        if let record = recordsByCompositeID["\(rollup.appType):\(rollup.providerID)"],
           let provider = normalizedProvider(record: record) {
            return provider
        }
        if let record = recordsByID[rollup.providerID]?.first,
           let provider = normalizedProvider(record: record) {
            return provider
        }

        let haystack = "\(rollup.providerID) \(rollup.appType) \(rollup.model)".lowercased()
        if haystack.contains("deepseek") { return .deepSeek }
        if haystack.contains("minimax") || haystack.contains("mini-max") { return .miniMax }
        if haystack.contains("mimo") || haystack.contains("xiaomi") { return .xiaomiMiMo }
        if haystack.contains("glm") { return .glm }
        if haystack.contains("openai") || haystack.contains("gpt") || haystack.contains("o1") || haystack.contains("o3") || haystack.contains("o4") { return .openAI }
        if haystack.contains("anthropic") || haystack.contains("claude") { return .anthropic }
        return nil
    }

    private static func normalizedProvider(record: CCSwitchProviderRecord) -> CCSwitchKnownProvider? {
        let haystack = [
            record.id,
            record.name,
            record.appType,
            record.baseURL ?? "",
            record.modelNames.joined(separator: " ")
        ].joined(separator: " ").lowercased()

        if haystack.contains("deepseek") { return .deepSeek }
        if haystack.contains("minimax") || haystack.contains("mini-max") || haystack.contains("minimaxi") { return .miniMax }
        if haystack.contains("mimo") || haystack.contains("xiaomi") { return .xiaomiMiMo }
        if haystack.contains("glm") { return .glm }
        if haystack.contains("openai") || haystack.contains("gpt") || haystack.contains("o1") || haystack.contains("o3") || haystack.contains("o4") { return .openAI }
        if haystack.contains("anthropic") || haystack.contains("claude") { return .anthropic }
        return nil
    }

    private static func rollingStartString(now: Date = .now) -> String {
        let start = Calendar.current.date(byAdding: .day, value: -30, to: now) ?? now.addingTimeInterval(-30 * 24 * 3600)
        return dayString(start)
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

    private static func usedPercent(used: Double, total: Double, remainingPercent: Double?) -> Double {
        if total > 0 {
            return min(max((used / total) * 100, 0), 100)
        }
        if let remainingPercent {
            return min(max(100 - remainingPercent, 0), 100)
        }
        return 0
    }

    private static func date(milliseconds: Double) -> Date {
        Date(timeIntervalSince1970: milliseconds / 1000)
    }
}
