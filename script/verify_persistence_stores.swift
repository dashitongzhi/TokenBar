import Foundation

private struct VerificationFailure: Error, CustomStringConvertible {
    let description: String
}

enum AgentProvider: String, Codable {
    case claudeCode
    case codex
}

enum ModelUsageSource: String, Codable {
    case localAgent
    case configured
}

struct WorkspacePolicy: Identifiable, Codable, Equatable {
    var id: String
    var name: String
    var pathHint: String
    var client: String
    var dailyBudget: Double
    var monthlyBudget: Double
    var spendToday: Double
    var spendMonth: Double
    var spendDayKey: String?
    var spendMonthKey: String?
    var allowedProviderIDs: [String]
    var blockedModels: [String]
    var maxEstimatedRunCost: Double
    var maxEstimatedTokens: Int
    var requireCompanyKey: Bool
    var preferredProviderID: String?
    var preferredModel: String?
    var setupSourceDetail: String?
    var configuredModelCount: Int?
    var inferredFromPaths: [String]?

    @discardableResult
    mutating func resetExpiredSpendBuckets(
        now: Date = .now,
        calendar: Calendar = .current
    ) -> Bool {
        let components = calendar.dateComponents([.year, .month, .day], from: now)
        guard let year = components.year,
              let month = components.month,
              let day = components.day else {
            return false
        }
        let currentDayKey = String(format: "%04d-%02d-%02d", year, month, day)
        let currentMonthKey = String(format: "%04d-%02d", year, month)
        var changed = false
        if spendDayKey == nil {
            spendDayKey = currentDayKey
            changed = true
        } else if spendDayKey != currentDayKey {
            spendToday = 0
            spendDayKey = currentDayKey
            changed = true
        }
        if spendMonthKey == nil {
            spendMonthKey = currentMonthKey
            changed = true
        } else if spendMonthKey != currentMonthKey {
            spendMonth = 0
            spendMonthKey = currentMonthKey
            changed = true
        }
        return changed
    }
}

struct LocalAgentUsageAppliedSnapshot: Equatable {
    var agent: AgentProvider
    var providerID: String
    var model: String
    var costDelta: Double
    var tokenDelta: Double
    var requestDelta: Int
    var occurredAt: Date
}

struct ModelUsageRollup: Identifiable, Codable, Equatable {
    var agent: AgentProvider
    var providerID: String
    var model: String
    var source: ModelUsageSource
    var configPath: String?
    var spendToday: Double
    var spendMonth: Double
    var tokensToday: Double
    var tokensMonth: Double
    var requestCountToday: Int
    var requestCountMonth: Int
    var dayKey: String
    var monthKey: String
    var lastUpdated: Date

    var id: String {
        [agent.rawValue, providerID, model.lowercased(), source.rawValue, configPath ?? ""]
            .joined(separator: "|")
    }
}

enum SmartRoutingRunSignal: String, Codable {
    case success
    case followUp
    case failed
    case unknown
}

struct SmartRoutingRunInput: Codable, Equatable {
    var agent: AgentProvider?
    var taskIntent: String?
    var providerID: String?
    var model: String?
    var workspaceID: String?
    var workspaceName: String?
    var workspacePath: String?
    var sessionID: String?
    var taskID: String?
    var estimatedCost: Double?
    var actualCost: Double?
    var estimatedTokens: Int?
    var actualTokens: Int?
    var inputTokens: Int?
    var outputTokens: Int?
    var requestCount: Int?
    var signal: SmartRoutingRunSignal?
    var followUpRequired: Bool?
    var selectedBy: String?
    var alternatives: [String]?
    var routingReason: String?
    var metadata: [String: String]?
    var occurredAt: Date?
}

struct SmartRoutingRunRecord: Identifiable, Codable, Equatable {
    var id: UUID
    var recordedAt: Date
    var occurredAt: Date
    var agent: AgentProvider
    var taskIntent: String
    var providerID: String
    var model: String
    var workspaceID: String?
    var workspaceName: String?
    var workspacePath: String?
    var sessionID: String?
    var taskID: String?
    var estimatedCost: Double
    var actualCost: Double
    var estimatedCostKnown: Bool?
    var actualCostKnown: Bool?
    var estimatedTokens: Int
    var actualTokens: Int
    var estimatedTokensKnown: Bool?
    var actualTokensKnown: Bool?
    var inputTokens: Int?
    var outputTokens: Int?
    var requestCount: Int?
    var signal: SmartRoutingRunSignal
    var followUpRequired: Bool
    var selectedBy: String?
    var alternatives: [String]
    var routingReason: String?
    var metadata: [String: String]

    var isWin: Bool {
        signal == .success && followUpRequired == false
    }
}

struct SmartRoutingRouteStats: Identifiable, Codable, Equatable {
    var id: String { routeKey }
    var routeKey: String
    var providerID: String
    var model: String
    var taskIntent: String
    var runCount: Int
    var winCount: Int
    var followUpCount: Int
    var failedCount: Int
    var unknownCount: Int
    var winRate: Double
    var followUpRate: Double
    var estimatedCostTotal: Double
    var actualCostTotal: Double
    var estimatedCostKnownRunCount: Int
    var actualCostKnownRunCount: Int
    var estimatedTokensTotal: Int
    var actualTokensTotal: Int
    var estimatedTokensKnownRunCount: Int
    var actualTokensKnownRunCount: Int
    var averageCostDelta: Double
    var averageTokenDelta: Double
    var lastRunAt: Date
}

struct SmartRoutingStatsSnapshot: Codable, Equatable {
    var generatedAt: Date
    var totalRuns: Int
    var winCount: Int
    var followUpCount: Int
    var failedCount: Int
    var unknownCount: Int
    var winRate: Double
    var followUpRate: Double
    var estimatedCostTotal: Double
    var actualCostTotal: Double
    var estimatedCostKnownRunCount: Int
    var actualCostKnownRunCount: Int
    var estimatedTokensTotal: Int
    var actualTokensTotal: Int
    var estimatedTokensKnownRunCount: Int
    var actualTokensKnownRunCount: Int
    var excludedNonProductionRuns: Int
    var routeStats: [SmartRoutingRouteStats]
    var recentRuns: [SmartRoutingRunRecord]
}

@main
struct VerifyPersistenceStores {
    @MainActor
    static func main() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("tokenbar-persistence-stores-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }

        try verifyWorkspaceMergeAndCorruption(in: root.appendingPathComponent("workspace"))
        try verifyLocalAgentDeltaAndPruning(in: root.appendingPathComponent("local-agent"))
        try verifyLocalModelBuckets(in: root.appendingPathComponent("local-model"))
        try verifySmartRoutingDeduplicationAndPruning(in: root.appendingPathComponent("routing"))

        print("Verified persistence store merge, delta, bucket reset, deduplication, and pruning behavior.")
    }

    private static func verifyWorkspaceMergeAndCorruption(in directory: URL) throws {
        let store = WorkspacePolicyStore(directoryURL: directory)
        let saved = workspace(
            id: "workspace",
            preferredProviderID: nil,
            allowedProviderIDs: []
        )
        let legacyDocument = JSONDocumentStore<[WorkspacePolicy]>(
            fileName: "workspace-policies.json",
            directoryURL: directory
        )
        try rawEncoder().encode([
            workspace(id: "client-app"),
            saved
        ]).write(to: legacyDocument.url, options: [.atomic])

        let defaults = [
            workspace(
                id: "workspace",
                preferredProviderID: "openai",
                allowedProviderIDs: ["openai"]
            ),
            workspace(id: "new-workspace")
        ]
        let loaded = store.load(defaults: defaults)

        try expect(loaded.map(\.id) == ["workspace", "new-workspace"], "workspace merge must remove demo seeds and add defaults")
        try expect(loaded[0].preferredProviderID == "openai", "workspace merge must infer preferred provider")
        try expect(loaded[0].allowedProviderIDs == ["openai"], "workspace merge must infer allowed providers")
        try expect(backupURLs(in: directory, fileName: "workspace-policies.json").count == 1, "legacy workspace data must be backed up")

        let corruptDirectory = directory.appendingPathComponent("corrupt")
        let corruptStore = WorkspacePolicyStore(directoryURL: corruptDirectory)
        let corruptURL = corruptDirectory.appendingPathComponent("workspace-policies.json")
        let corruptData = Data("{broken".utf8)
        try FileManager.default.createDirectory(at: corruptDirectory, withIntermediateDirectories: true)
        try corruptData.write(to: corruptURL, options: [.atomic])

        let fallback = corruptStore.load(defaults: defaults)
        try expect(fallback.map(\.id) == defaults.map(\.id), "corrupt workspace data must return defaults")
        try expect(try Data(contentsOf: corruptURL) == corruptData, "loading corrupt workspace data must not overwrite it")
        try expect(backupURLs(in: corruptDirectory, fileName: "workspace-policies.json").isEmpty, "read-only corrupt load must not create a backup")
    }

    private static func verifyLocalAgentDeltaAndPruning(in directory: URL) throws {
        let store = LocalAgentUsageLedgerStore(directoryURL: directory)
        let now = Date(timeIntervalSince1970: 1_735_689_600)
        let old = now.addingTimeInterval(-15 * 24 * 3600)

        let initial = store.apply(
            sessionKey: "old",
            cumulativeCost: 4,
            cumulativeTokens: 40,
            cumulativeRequestCount: 2,
            now: old
        )
        try expect(initial == LocalAgentUsageDelta(costUSD: 4, tokens: 40, requestCount: 2), "first local-agent sample must use cumulative totals")

        _ = store.apply(
            sessionKey: "current",
            cumulativeCost: 10,
            cumulativeTokens: 100,
            cumulativeRequestCount: 5,
            now: now
        )
        let delta = store.apply(
            sessionKey: "current",
            cumulativeCost: 13,
            cumulativeTokens: 130,
            cumulativeRequestCount: 7,
            now: now.addingTimeInterval(60)
        )
        try expect(delta == LocalAgentUsageDelta(costUSD: 3, tokens: 30, requestCount: 2), "local-agent samples must compute monotonic deltas")

        let document = JSONDocumentStore<[String: LocalAgentUsageCursor]>(
            fileName: "local-agent-usage-ledger.json",
            directoryURL: directory
        )
        switch document.load() {
        case .loaded(let ledger):
            try expect(Set(ledger.keys) == ["current"], "local-agent ledger must prune entries older than 14 days")
        default:
            throw VerificationFailure(description: "local-agent ledger did not load")
        }
    }

    private static func verifyLocalModelBuckets(in directory: URL) throws {
        let store = LocalModelUsageStore(directoryURL: directory)
        let firstDay = utcDate("2026-01-30T10:00:00Z")
        let nextDay = utcDate("2026-01-31T10:00:00Z")
        let nextMonth = utcDate("2026-02-01T10:00:00Z")

        _ = store.apply(snapshot: localSnapshot(model: "Model-A", cost: 2, tokens: 20, requests: 1, at: firstDay))
        let sameModel = store.apply(snapshot: localSnapshot(model: " model-a ", cost: 3, tokens: 30, requests: 2, at: firstDay))
        try expect(sameModel.count == 1, "model matching must ignore case and surrounding whitespace")
        try expect(sameModel[0].spendToday == 5 && sameModel[0].spendMonth == 5, "same-day model usage must accumulate")

        let dayReset = store.apply(snapshot: localSnapshot(model: "MODEL-A", cost: 4, tokens: 40, requests: 1, at: nextDay))
        try expect(dayReset[0].spendToday == 4, "new day must reset daily spend")
        try expect(dayReset[0].spendMonth == 9, "new day in same month must retain monthly spend")

        let monthReset = store.apply(snapshot: localSnapshot(model: "model-a", cost: 5, tokens: 50, requests: 1, at: nextMonth))
        try expect(monthReset[0].spendToday == 5, "new month must reset daily spend")
        try expect(monthReset[0].spendMonth == 5, "new month must reset monthly spend")
    }

    @MainActor
    private static func verifySmartRoutingDeduplicationAndPruning(in directory: URL) throws {
        let store = SmartRoutingLedgerStore(directoryURL: directory)
        let now = Date(timeIntervalSince1970: 1_735_689_600)
        let old = now.addingTimeInterval(-91 * 24 * 3600)

        _ = store.record(
            routingInput(taskID: "old", actualCost: 7, occurredAt: old),
            fallbackWorkspaceID: "workspace",
            fallbackAgent: .codex,
            now: old
        )
        let first = store.record(
            routingInput(taskID: "current", actualCost: 2, occurredAt: now),
            fallbackWorkspaceID: "workspace",
            fallbackAgent: .codex,
            now: now
        )
        let replacement = store.record(
            routingInput(taskID: "current", actualCost: 3, occurredAt: now.addingTimeInterval(60)),
            fallbackWorkspaceID: "workspace",
            fallbackAgent: .codex,
            now: now.addingTimeInterval(60)
        )

        try expect(first.id == replacement.id, "same task run must retain its record identity")
        let stats = store.stats(now: now.addingTimeInterval(60))
        try expect(stats.totalRuns == 1, "routing ledger must deduplicate current task and prune records older than 90 days")
        try expect(stats.actualCostTotal == 3, "routing ledger replacement must use latest actual cost")
    }

    private static func workspace(
        id: String,
        preferredProviderID: String? = "openai",
        allowedProviderIDs: [String] = ["openai"]
    ) -> WorkspacePolicy {
        WorkspacePolicy(
            id: id,
            name: id,
            pathHint: "/tmp/\(id)",
            client: "Codex",
            dailyBudget: 10,
            monthlyBudget: 100,
            spendToday: 1,
            spendMonth: 2,
            spendDayKey: nil,
            spendMonthKey: nil,
            allowedProviderIDs: allowedProviderIDs,
            blockedModels: [],
            maxEstimatedRunCost: 1,
            maxEstimatedTokens: 1_000,
            requireCompanyKey: false,
            preferredProviderID: preferredProviderID,
            preferredModel: "model-a",
            setupSourceDetail: "fixture",
            configuredModelCount: 1,
            inferredFromPaths: ["/tmp/\(id)"]
        )
    }

    private static func localSnapshot(
        model: String,
        cost: Double,
        tokens: Double,
        requests: Int,
        at date: Date
    ) -> LocalAgentUsageAppliedSnapshot {
        LocalAgentUsageAppliedSnapshot(
            agent: .codex,
            providerID: "openai",
            model: model,
            costDelta: cost,
            tokenDelta: tokens,
            requestDelta: requests,
            occurredAt: date
        )
    }

    private static func routingInput(
        taskID: String,
        actualCost: Double,
        occurredAt: Date
    ) -> SmartRoutingRunInput {
        SmartRoutingRunInput(
            agent: .codex,
            taskIntent: "implementation",
            providerID: "openai",
            model: "gpt",
            workspaceID: "workspace",
            workspaceName: "Workspace",
            workspacePath: "/tmp/workspace",
            sessionID: "session",
            taskID: taskID,
            estimatedCost: 2,
            actualCost: actualCost,
            estimatedTokens: 100,
            actualTokens: 120,
            inputTokens: 80,
            outputTokens: 40,
            requestCount: 1,
            signal: .success,
            followUpRequired: false,
            selectedBy: "router",
            alternatives: [],
            routingReason: "fixture",
            metadata: [:],
            occurredAt: occurredAt
        )
    }

    private static func rawEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }

    private static func utcDate(_ value: String) -> Date {
        ISO8601DateFormatter().date(from: value)!
    }

    private static func backupURLs(in directory: URL, fileName: String) -> [URL] {
        let prefix = fileName + ".backup-"
        return ((try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        )) ?? []).filter { $0.lastPathComponent.hasPrefix(prefix) }
    }

    private static func expect(
        _ condition: @autoclosure () throws -> Bool,
        _ message: String
    ) throws {
        guard try condition() else {
            throw VerificationFailure(description: message)
        }
    }
}
