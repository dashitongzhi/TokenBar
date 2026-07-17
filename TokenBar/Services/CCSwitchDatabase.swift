import Foundation
import SQLite3

struct CCSwitchDatabaseSnapshot {
    var providerRecords: [CCSwitchProviderRecord]
    var dailyRollups: [CCSwitchDailyRollup]
    var providerHealth: [String: CCSwitchProviderHealth]
}

struct CCSwitchDatabaseAdapter {
    private let reader: SQLiteReader

    init(path: String) throws {
        reader = try SQLiteReader(path: path)
    }

    func load(since startDate: String) throws -> CCSwitchDatabaseSnapshot {
        CCSwitchDatabaseSnapshot(
            providerRecords: try reader.providerRecords(),
            dailyRollups: try reader.dailyRollups(since: startDate),
            providerHealth: try reader.providerHealth()
        )
    }

    func providerRecords() throws -> [CCSwitchProviderRecord] {
        try reader.providerRecords()
    }
}

struct CCSwitchProviderRecord {
    var id: String
    var appType: String
    var name: String
    var config: [String: Any]
    var meta: [String: Any]
    var dailySpendLimit: Double?
    var monthlySpendLimit: Double?

    var env: [String: Any] {
        config["env"] as? [String: Any] ?? [:]
    }

    var apiKey: String? {
        stringValue(config["apiKey"])
            ?? stringValue(config["api_key"])
            ?? stringValue(env["DEEPSEEK_API_KEY"])
            ?? stringValue(env["ANTHROPIC_AUTH_TOKEN"])
            ?? stringValue(env["ANTHROPIC_API_KEY"])
            ?? stringValue(env["OPENAI_API_KEY"])
            ?? stringValue(config["auth"].flatMap { ($0 as? [String: Any])?["OPENAI_API_KEY"] })
    }

    var hasAPIKey: Bool {
        apiKey?.isEmpty == false
    }

    var baseURL: String? {
        stringValue(config["baseUrl"])
            ?? stringValue(config["base_url"])
            ?? stringValue(env["ANTHROPIC_BASE_URL"])
            ?? embeddedCodexProviderValue("base_url")
    }

    var modelNames: [String] {
        var names: [String] = []
        for key in [
            "model",
            "modelName",
            "ANTHROPIC_MODEL",
            "ANTHROPIC_DEFAULT_SONNET_MODEL",
            "ANTHROPIC_DEFAULT_SONNET_MODEL_NAME",
            "ANTHROPIC_DEFAULT_OPUS_MODEL",
            "ANTHROPIC_DEFAULT_OPUS_MODEL_NAME",
            "ANTHROPIC_DEFAULT_HAIKU_MODEL",
            "ANTHROPIC_DEFAULT_HAIKU_MODEL_NAME",
            "OPENAI_MODEL",
            "CODEX_MODEL"
        ] {
            if let value = stringValue(config[key]) ?? stringValue(env[key]) {
                names.append(value)
            }
        }
        if let models = config["models"] as? [[String: Any]] {
            names.append(contentsOf: models.compactMap {
                stringValue($0["id"]) ?? stringValue($0["name"])
            })
        }
        if let routes = meta["claudeDesktopModelRoutes"] as? [String: Any] {
            for (_, rawRoute) in routes {
                guard let route = rawRoute as? [String: Any] else { continue }
                if let model = stringValue(route["model"]) {
                    names.append(model)
                }
                if let label = stringValue(route["labelOverride"]) {
                    names.append(label)
                }
            }
        }
        if let embeddedModel = embeddedCodexTopLevelValue("model") {
            names.append(embeddedModel)
        }
        return Array(Set(
            names
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { $0.isEmpty == false }
        )).sorted()
    }

    private func stringValue(_ value: Any?) -> String? {
        guard let value else { return nil }
        if let string = value as? String { return string.isEmpty ? nil : string }
        return "\(value)"
    }

    private func embeddedCodexTopLevelValue(_ key: String) -> String? {
        guard let content = stringValue(config["config"]) else { return nil }
        var isTopLevel = true
        for rawLine in content.components(separatedBy: .newlines) {
            let line = rawLine.split(separator: "#", maxSplits: 1).first.map(String.init) ?? ""
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { continue }
            if trimmed.hasPrefix("[") {
                isTopLevel = false
                continue
            }
            guard isTopLevel, let separator = trimmed.firstIndex(of: "=") else { continue }
            let candidate = trimmed[..<separator].trimmingCharacters(in: .whitespacesAndNewlines)
            guard candidate == key else { continue }
            return trimmed[trimmed.index(after: separator)...]
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
        }
        return nil
    }

    private func embeddedCodexProviderValue(_ key: String) -> String? {
        guard let content = stringValue(config["config"]),
              let provider = embeddedCodexTopLevelValue("model_provider") else {
            return nil
        }
        let sectionName = "model_providers.\(provider)"
        var inProvider = false
        for rawLine in content.components(separatedBy: .newlines) {
            let line = rawLine.split(separator: "#", maxSplits: 1).first.map(String.init) ?? ""
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { continue }
            if trimmed.hasPrefix("[") && trimmed.hasSuffix("]") {
                inProvider = trimmed
                    .trimmingCharacters(in: CharacterSet(charactersIn: "[]")) == sectionName
                continue
            }
            guard inProvider, let separator = trimmed.firstIndex(of: "=") else { continue }
            let candidate = trimmed[..<separator].trimmingCharacters(in: .whitespacesAndNewlines)
            guard candidate == key else { continue }
            return trimmed[trimmed.index(after: separator)...]
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
        }
        return nil
    }
}

struct CCSwitchDailyRollup {
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

struct CCSwitchProviderHealth {
    var isHealthy: Bool
    var consecutiveFailures: Int
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
        try rows(
            sql: """
            select id, app_type, name, settings_config, meta,
                   limit_daily_usd, limit_monthly_usd
              from providers
            """
        )
            .compactMap { row in
                guard let config = parseJSONObject(row["settings_config"]) else {
                    return nil
                }
                let meta = parseJSONObject(row["meta"]) ?? [:]
                return CCSwitchProviderRecord(
                    id: row["id"] ?? "",
                    appType: row["app_type"] ?? "",
                    name: row["name"] ?? "",
                    config: config,
                    meta: meta,
                    dailySpendLimit: Double(row["limit_daily_usd"] ?? ""),
                    monthlySpendLimit: Double(row["limit_monthly_usd"] ?? "")
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
        let items = try rows(
            sql: "select provider_id, app_type, is_healthy, consecutive_failures from provider_health"
        )
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
            sqlite3_bind_text(
                statement,
                Int32(index + 1),
                parameter,
                -1,
                Self.transientDestructor
            )
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

    private static let transientDestructor = unsafeBitCast(
        -1,
        to: sqlite3_destructor_type.self
    )
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
