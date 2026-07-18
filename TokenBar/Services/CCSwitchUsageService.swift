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
            let databaseSnapshot = try database.load(since: CCSwitchUsageSnapshotMapper.rollingStartString())
            async let deepSeekBalance = providerTransport.deepSeekBalance(from: databaseSnapshot.providerRecords)
            async let quotaWindows = providerTransport.liveQuotaWindows(from: databaseSnapshot.providerRecords)
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
        let snapshotURL = fileManager.temporaryDirectory
            .appendingPathComponent("tokenbar-cc-switch-models-\(UUID().uuidString).db")
        do {
            try fileManager.copyItem(at: databaseURL, to: snapshotURL)
            defer { try? fileManager.removeItem(at: snapshotURL) }

            let database = try CCSwitchDatabaseAdapter(path: snapshotURL.path)
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
