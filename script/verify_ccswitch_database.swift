import Foundation
import SQLite3

enum CCSwitchKnownProvider: Hashable {
    case miniMax
    case deepSeek
    case xiaomiMiMo
    case ccSwitchCodex
    case glm
    case openAI
    case anthropic
}

private struct VerificationFailure: Error, CustomStringConvertible {
    let description: String
}

@main
struct VerifyCCSwitchDatabase {
    static func main() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("tokenbar-ccswitch-verification-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }

        let databaseURL = directory.appendingPathComponent("cc-switch.db")
        try createFixture(at: databaseURL.path)

        let database = try CCSwitchDatabaseAdapter(path: databaseURL.path)
        let snapshot = try database.load(since: "2026-07-01")

        try expect(snapshot.providerRecords.count == 1, "provider record must load")
        guard let provider = snapshot.providerRecords.first else {
            throw VerificationFailure(description: "provider fixture missing")
        }
        try expect(provider.id == "openai-fixture", "provider id must be preserved")
        try expect(
            provider.apiKey(forProviderID: "openai") == "fixture-secret",
            "provider-specific OpenAI key must decode from env"
        )
        try expect(
            provider.apiKey(forProviderID: "deepseek") == nil,
            "an OpenAI key must never be reused as a DeepSeek credential"
        )
        try expect(
            provider.apiKey(forProviderID: "minimax") == nil,
            "an OpenAI key must never be reused as a MiniMax credential"
        )
        try expect(provider.baseURL == "https://api.openai.com/v1", "base URL must decode")
        try expect(provider.modelNames == ["gpt-5"], "configured models must decode")
        try expect(provider.dailySpendLimit == 12.5, "daily spend limit must load")
        try expect(provider.monthlySpendLimit == 250, "monthly spend limit must load")

        try expect(snapshot.dailyRollups.count == 1, "rollup must load")
        guard let rollup = snapshot.dailyRollups.first else {
            throw VerificationFailure(description: "rollup fixture missing")
        }
        try expect(rollup.requestCount == 3, "request count must load")
        try expect(rollup.tokenTotal == 1_150, "all token categories must aggregate")
        try expect(rollup.totalCostUSD == 1.75, "cost must load")

        let health = snapshot.providerHealth["codex:openai-fixture"]
        try expect(health?.isHealthy == false, "health state must load")
        try expect(health?.consecutiveFailures == 4, "failure count must load")

        let filtered = try database.load(since: "2026-08-01")
        try expect(filtered.dailyRollups.isEmpty, "start date must filter old rollups")
        try verifyProviderNormalization()

        print("Verified CC Switch database provider, limits, rollup, and health adapter.")
    }

    private static func verifyProviderNormalization() throws {
        let aggregator = CCSwitchProviderRecord(
            id: "router-fixture",
            appType: "claude",
            name: "Multi-vendor Router",
            config: [
                "baseUrl": "https://router.example.test/v1",
                "models": [
                    ["id": "deepseek-chat"],
                    ["id": "gpt-5"]
                ]
            ],
            meta: [:],
            dailySpendLimit: nil,
            monthlySpendLimit: nil
        )
        try expect(
            CCSwitchProviderNormalizer.normalize(record: aggregator) == nil,
            "a heterogeneous aggregator record must not collapse to one provider"
        )
        var ambiguousIdentity = aggregator
        ambiguousIdentity.id = "deepseek-openai-router"
        try expect(
            CCSwitchProviderNormalizer.normalize(record: ambiguousIdentity) == nil,
            "an identity naming multiple providers must remain an aggregator"
        )

        let rollup = CCSwitchDailyRollup(
            date: "2026-07-28",
            appType: aggregator.appType,
            providerID: aggregator.id,
            model: "deepseek-chat",
            requestCount: 1,
            inputTokens: 1,
            outputTokens: 1,
            cacheReadTokens: 0,
            cacheCreationTokens: 0,
            totalCostUSD: 0
        )
        try expect(
            CCSwitchProviderNormalizer.normalize(
                rollup: rollup,
                recordsByCompositeID: ["\(aggregator.appType):\(aggregator.id)": aggregator],
                recordsByID: [aggregator.id: [aggregator]]
            ) == .deepSeek,
            "heterogeneous aggregator rollups must normalize from each rollup model"
        )

        let misleadingIdentity = CCSwitchProviderRecord(
            id: "demo1",
            appType: "proxy",
            name: "Provider No1",
            config: ["baseUrl": "https://router.example.test/v1"],
            meta: [:],
            dailySpendLimit: nil,
            monthlySpendLimit: nil
        )
        try expect(
            CCSwitchProviderNormalizer.normalize(record: misleadingIdentity) == nil,
            "ordinary tokens containing o1 characters must not be classified as OpenAI"
        )

        for (model, expected) in [
            ("gpt-5", CCSwitchKnownProvider.openAI),
            ("glm-4.5", .glm),
            ("claude-sonnet-4", .anthropic)
        ] {
            let record = CCSwitchProviderRecord(
                id: "model-fixture",
                appType: "proxy",
                name: "Model Fixture",
                config: [
                    "baseUrl": "https://router.example.test/v1",
                    "models": [["id": model]]
                ],
                meta: [:],
                dailySpendLimit: nil,
                monthlySpendLimit: nil
            )
            try expect(
                CCSwitchProviderNormalizer.normalize(record: record) == expected,
                "\(model) must normalize using token boundaries"
            )
        }
    }

    private static func createFixture(at path: String) throws {
        var database: OpaquePointer?
        guard sqlite3_open(path, &database) == SQLITE_OK else {
            throw VerificationFailure(description: "could not create SQLite fixture")
        }
        defer { sqlite3_close(database) }

        try execute(
            """
            create table providers (
                id text,
                app_type text,
                name text,
                settings_config text,
                meta text,
                limit_daily_usd real,
                limit_monthly_usd real
            );
            create table usage_daily_rollups (
                date text,
                app_type text,
                provider_id text,
                model text,
                request_count integer,
                input_tokens real,
                output_tokens real,
                cache_read_tokens real,
                cache_creation_tokens real,
                total_cost_usd real
            );
            create table provider_health (
                provider_id text,
                app_type text,
                is_healthy integer,
                consecutive_failures integer
            );
            """,
            database: database
        )

        let settings = #"{"env":{"OPENAI_API_KEY":"fixture-secret"},"models":[{"id":"gpt-5"}],"baseUrl":"https://api.openai.com/v1"}"#
        try execute(
            """
            insert into providers values (
                'openai-fixture',
                'codex',
                'OpenAI Fixture',
                '\(settings)',
                '{}',
                12.5,
                250
            );
            insert into usage_daily_rollups values (
                '2026-07-17',
                'codex',
                'openai-fixture',
                'gpt-5',
                3,
                800,
                200,
                100,
                50,
                1.75
            );
            insert into provider_health values (
                'openai-fixture',
                'codex',
                0,
                4
            );
            """,
            database: database
        )
    }

    private static func execute(_ sql: String, database: OpaquePointer?) throws {
        var errorMessage: UnsafeMutablePointer<CChar>?
        guard sqlite3_exec(database, sql, nil, nil, &errorMessage) == SQLITE_OK else {
            let message = errorMessage.map { String(cString: $0) } ?? "unknown SQLite error"
            sqlite3_free(errorMessage)
            throw VerificationFailure(description: message)
        }
    }

    private static func expect(
        _ condition: @autoclosure () -> Bool,
        _ message: String
    ) throws {
        guard condition() else {
            throw VerificationFailure(description: message)
        }
    }
}
