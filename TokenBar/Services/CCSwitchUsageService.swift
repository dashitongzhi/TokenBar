import Foundation
import SQLite3

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
    var monthResetAt: Date
    var history: [UsagePoint]
    var sourceDetail: String
    var fetchedAt: Date
}

struct CCSwitchUsageService {
    private let fileManager: FileManager
    private let databaseURL: URL

    init(
        fileManager: FileManager = .default,
        databaseURL: URL = FileManager.default.homeDirectoryForCurrentUser
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

            let reader = try SQLiteReader(path: snapshotURL.path)
            let providerRecords = try reader.providerRecords()
            let rollups = try reader.dailyRollups(since: Self.rollingStartString())
            let health = try reader.providerHealth()
            let deepSeekBalance = await deepSeekBalance(from: providerRecords)
            let snapshot = Self.buildSnapshot(
                providerRecords: providerRecords,
                rollups: rollups,
                health: health,
                deepSeekBalance: deepSeekBalance
            )
            return snapshot.providers.isEmpty
                ? .unavailable("CC Switch database was found, but no supported provider usage rollups were present.")
                : .success(snapshot)
        } catch {
            return .failure("CC Switch usage refresh failed: \(error.localizedDescription)")
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
                if healthItems.contains(where: { $0.isHealthy }) {
                    detail += " CC Switch health has a recent successful route."
                } else if let unhealthy = healthItems.first(where: { $0.isHealthy == false }) {
                    detail += " CC Switch health reports \(unhealthy.consecutiveFailures) consecutive failures."
                }
                if aggregate.provider == .deepSeek, let deepSeekBalance {
                    detail += " DeepSeek live balance: \(deepSeekBalance.currency) \(String(format: "%.2f", deepSeekBalance.totalBalance)); API available: \(deepSeekBalance.isAvailable ? "yes" : "no")."
                }
                if healthyRecords.contains(where: { $0.hasAPIKey }) {
                    detail += " API key was detected in CC Switch config and used only in memory."
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
                    monthResetAt: monthResetAt,
                    history: aggregate.history(),
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
        if rollup.appType == "codex" { return .ccSwitchCodex }
        if haystack.contains("glm") { return .glm }
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
        if record.appType == "codex" { return .ccSwitchCodex }
        if haystack.contains("glm") { return .glm }
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
}

private enum CCSwitchKnownProvider: Hashable {
    case miniMax
    case deepSeek
    case xiaomiMiMo
    case ccSwitchCodex
    case glm

    var providerID: String {
        switch self {
        case .miniMax: "minimax"
        case .deepSeek: "deepseek"
        case .xiaomiMiMo: "xiaomi-mimo"
        case .ccSwitchCodex: "ccswitch-codex"
        case .glm: "glm"
        }
    }

    var displayName: String {
        switch self {
        case .miniMax: "MiniMax"
        case .deepSeek: "DeepSeek"
        case .xiaomiMiMo: "Xiaomi MiMo"
        case .ccSwitchCodex: "CC Switch Codex"
        case .glm: "GLM"
        }
    }

    var symbolName: String {
        switch self {
        case .miniMax: "bolt.horizontal.circle.fill"
        case .deepSeek: "scope"
        case .xiaomiMiMo: "waveform.path.ecg"
        case .ccSwitchCodex: "terminal.fill"
        case .glm: "sparkle.magnifyingglass"
        }
    }

    var sortOrder: Int {
        switch self {
        case .miniMax: 0
        case .deepSeek: 1
        case .xiaomiMiMo: 2
        case .ccSwitchCodex: 3
        case .glm: 4
        }
    }
}

private struct CCSwitchProviderRecord {
    var id: String
    var appType: String
    var name: String
    var config: [String: Any]
    var meta: [String: Any]

    var env: [String: Any] {
        config["env"] as? [String: Any] ?? [:]
    }

    var apiKey: String? {
        stringValue(config["apiKey"])
            ?? stringValue(config["api_key"])
            ?? stringValue(env["DEEPSEEK_API_KEY"])
            ?? stringValue(env["ANTHROPIC_AUTH_TOKEN"])
            ?? stringValue(env["OPENAI_API_KEY"])
    }

    var hasAPIKey: Bool {
        apiKey?.isEmpty == false
    }

    var baseURL: String? {
        stringValue(config["baseUrl"])
            ?? stringValue(config["base_url"])
            ?? stringValue(env["ANTHROPIC_BASE_URL"])
    }

    var modelNames: [String] {
        var names: [String] = []
        for key in ["model", "ANTHROPIC_MODEL", "ANTHROPIC_DEFAULT_SONNET_MODEL", "ANTHROPIC_DEFAULT_OPUS_MODEL", "ANTHROPIC_DEFAULT_HAIKU_MODEL"] {
            if let value = stringValue(config[key]) ?? stringValue(env[key]) {
                names.append(value)
            }
        }
        if let models = config["models"] as? [[String: Any]] {
            names.append(contentsOf: models.compactMap { stringValue($0["id"]) ?? stringValue($0["name"]) })
        }
        return names
    }

    private func stringValue(_ value: Any?) -> String? {
        guard let value else { return nil }
        if let string = value as? String { return string.isEmpty ? nil : string }
        return "\(value)"
    }
}

private struct CCSwitchDailyRollup {
    var date: String
    var appType: String
    var providerID: String
    var model: String
    var requestCount: Int
    var inputTokens: Double
    var outputTokens: Double
    var cacheReadTokens: Double
    var cacheCreationTokens: Double
    var totalCostUSD: Double

    var tokenTotal: Double {
        inputTokens + outputTokens + cacheReadTokens + cacheCreationTokens
    }
}

private struct CCSwitchProviderHealth {
    var isHealthy: Bool
    var consecutiveFailures: Int
}

private struct CCSwitchAggregate {
    var provider: CCSwitchKnownProvider
    var tokenTotalToday = 0.0
    var tokenTotalMonth = 0.0
    var requestCountToday = 0
    var requestCountMonth = 0
    var spendToday = 0.0
    var spendMonth = 0.0
    var models: [String] = []
    private var dailyTokens: [String: Double] = [:]

    init(provider: CCSwitchKnownProvider) {
        self.provider = provider
    }

    mutating func add(rollup: CCSwitchDailyRollup, isToday: Bool) {
        tokenTotalMonth += rollup.tokenTotal
        requestCountMonth += rollup.requestCount
        spendMonth += rollup.totalCostUSD
        dailyTokens[rollup.date, default: 0] += rollup.tokenTotal
        if models.contains(rollup.model) == false, rollup.model.isEmpty == false {
            models.append(rollup.model)
        }
        if isToday {
            tokenTotalToday += rollup.tokenTotal
            requestCountToday += rollup.requestCount
            spendToday += rollup.totalCostUSD
        }
    }

    func history() -> [UsagePoint] {
        dailyTokens.keys.sorted().compactMap { day in
            guard let date = Self.dateFormatter.date(from: day), let value = dailyTokens[day] else { return nil }
            return UsagePoint(timestamp: date, value: value)
        }
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}

private struct DeepSeekBalance {
    var isAvailable: Bool
    var currency: String
    var totalBalance: Double
    var toppedUpBalance: Double
    var grantedBalance: Double
}

private struct DeepSeekBalanceResponse: Decodable {
    var isAvailable: Bool
    var balanceInfos: [BalanceInfo]

    enum CodingKeys: String, CodingKey {
        case isAvailable = "is_available"
        case balanceInfos = "balance_infos"
    }

    struct BalanceInfo: Decodable {
        var currency: String
        var totalBalance: String
        var toppedUpBalance: String
        var grantedBalance: String

        enum CodingKeys: String, CodingKey {
            case currency
            case totalBalance = "total_balance"
            case toppedUpBalance = "topped_up_balance"
            case grantedBalance = "granted_balance"
        }
    }
}

private final class SQLiteReader {
    private var db: OpaquePointer?

    init(path: String) throws {
        guard sqlite3_open_v2(path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            throw SQLiteReaderError.open(message: String(cString: sqlite3_errmsg(db)))
        }
    }

    deinit {
        sqlite3_close(db)
    }

    func providerRecords() throws -> [CCSwitchProviderRecord] {
        try rows(sql: "select id, app_type, name, settings_config, meta from providers").compactMap { row in
            guard let config = parseJSONObject(row["settings_config"]) else {
                return nil
            }
            let meta = parseJSONObject(row["meta"]) ?? [:]
            return CCSwitchProviderRecord(
                id: row["id"] ?? "",
                appType: row["app_type"] ?? "",
                name: row["name"] ?? "",
                config: config,
                meta: meta
            )
        }
    }

    func dailyRollups(since monthStart: String) throws -> [CCSwitchDailyRollup] {
        try rows(
            sql: """
            select date, app_type, provider_id, model, request_count,
                   input_tokens, output_tokens, cache_read_tokens, cache_creation_tokens, total_cost_usd
              from usage_daily_rollups
             where date >= ?
            """,
            parameters: [monthStart]
        ).map { row in
            CCSwitchDailyRollup(
                date: row["date"] ?? "",
                appType: row["app_type"] ?? "",
                providerID: row["provider_id"] ?? "",
                model: row["model"] ?? "",
                requestCount: Int(row["request_count"] ?? "0") ?? 0,
                inputTokens: Double(row["input_tokens"] ?? "0") ?? 0,
                outputTokens: Double(row["output_tokens"] ?? "0") ?? 0,
                cacheReadTokens: Double(row["cache_read_tokens"] ?? "0") ?? 0,
                cacheCreationTokens: Double(row["cache_creation_tokens"] ?? "0") ?? 0,
                totalCostUSD: Double(row["total_cost_usd"] ?? "0") ?? 0
            )
        }
    }

    func providerHealth() throws -> [String: CCSwitchProviderHealth] {
        let items = try rows(sql: "select provider_id, app_type, is_healthy, consecutive_failures from provider_health")
        return Dictionary(uniqueKeysWithValues: items.map { row in
            (
                "\(row["app_type"] ?? ""):\(row["provider_id"] ?? "")",
                CCSwitchProviderHealth(
                    isHealthy: (Int(row["is_healthy"] ?? "0") ?? 0) == 1,
                    consecutiveFailures: Int(row["consecutive_failures"] ?? "0") ?? 0
                )
            )
        })
    }

    private func rows(sql: String, parameters: [String] = []) throws -> [[String: String]] {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw SQLiteReaderError.prepare(message: String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(statement) }

        for (index, parameter) in parameters.enumerated() {
            sqlite3_bind_text(statement, Int32(index + 1), parameter, -1, Self.transientDestructor)
        }

        var results: [[String: String]] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            var row: [String: String] = [:]
            for index in 0..<sqlite3_column_count(statement) {
                let name = String(cString: sqlite3_column_name(statement, index))
                if let text = sqlite3_column_text(statement, index) {
                    row[name] = String(cString: text)
                }
            }
            results.append(row)
        }
        return results
    }

    private func parseJSONObject(_ value: String?) -> [String: Any]? {
        guard let value, let data = value.data(using: .utf8) else { return [:] }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }

    private static let transientDestructor = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
}

private enum SQLiteReaderError: LocalizedError {
    case open(message: String)
    case prepare(message: String)

    var errorDescription: String? {
        switch self {
        case .open(let message): "Could not open CC Switch database: \(message)"
        case .prepare(let message): "Could not read CC Switch database: \(message)"
        }
    }
}
