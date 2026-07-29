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

typealias CCSwitchQuotaWindow = MiniMaxQuotaWindow

extension MiniMaxQuotaWindow {
    var hasKnownIntervalLimit: Bool {
        intervalTotalCount > 0 || intervalRemainingPercent != nil
    }

    var hasKnownWeeklyLimit: Bool {
        weeklyTotalCount > 0 || weeklyRemainingPercent != nil
    }

    var intervalWindowLabel: String {
        QuotaWindowFormatting.label(from: intervalStartAt, to: intervalResetAt)
    }

    var weeklyWindowLabel: String {
        QuotaWindowFormatting.label(from: weeklyStartAt, to: weeklyResetAt)
    }
}

struct CCSwitchUsageService {
    private let fileManager: FileManager
    private let databaseURL: URL
    private let providerTransport: CCSwitchProviderTransport

    init(
        fileManager: FileManager = .default,
        databaseURL: URL = UserHomeDirectory.url
            .appendingPathComponent(".cc-switch/cc-switch.db")
    ) {
        self.fileManager = fileManager
        self.databaseURL = databaseURL
        providerTransport = CCSwitchProviderTransport()
    }

    func refresh(includeOfficialQuotaProbes: Bool = false) async -> CCSwitchUsageRefreshResult {
        guard fileManager.fileExists(atPath: databaseURL.path) else {
            return .unavailable("CC Switch usage requires ~/.cc-switch/cc-switch.db.")
        }

        do {
            let database = try CCSwitchDatabaseAdapter(path: databaseURL.path)
            let databaseSnapshot = try database.load(since: CCSwitchUsageSnapshotMapper.rollingStartString())
            async let deepSeekBalance: DeepSeekBalance? = includeOfficialQuotaProbes
                ? providerTransport.deepSeekBalance(from: databaseSnapshot.providerRecords)
                : nil
            async let quotaWindows: [CCSwitchKnownProvider: [CCSwitchQuotaWindow]] = includeOfficialQuotaProbes
                ? providerTransport.liveQuotaWindows(from: databaseSnapshot.providerRecords)
                : [:]
            let snapshot = CCSwitchUsageSnapshotMapper.buildSnapshot(
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
        do {
            let database = try CCSwitchDatabaseAdapter(path: databaseURL.path)
            let records = try database.providerRecords()
            return records.flatMap { record -> [ModelCatalogItem] in
                let providerID = CCSwitchProviderNormalizer.normalize(record: record)?.providerID ?? record.id
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

}
