import Foundation

struct SmartRoutingLedgerStore {
    private let storeURL: URL
    private let maxRecords = 2_000
    private let retentionSeconds: TimeInterval = 90 * 24 * 3600

    init(fileManager: FileManager = .default) {
        let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? fileManager.temporaryDirectory
        let directory = support.appendingPathComponent("TokenBar", isDirectory: true)
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        storeURL = directory.appendingPathComponent("smart-routing-runs.json")
    }

    func record(_ input: SmartRoutingRunInput, fallbackWorkspaceID: String?, fallbackAgent: AgentProvider, now: Date = .now) -> SmartRoutingRunRecord {
        let record = SmartRoutingRunRecord(
            id: UUID(),
            recordedAt: now,
            occurredAt: input.occurredAt ?? now,
            agent: input.agent ?? fallbackAgent,
            taskIntent: Self.normalized(input.taskIntent, fallback: "unspecified"),
            providerID: Self.normalized(input.providerID, fallback: "unknown"),
            model: Self.normalized(input.model, fallback: "unspecified"),
            workspaceID: Self.blankToNil(input.workspaceID) ?? fallbackWorkspaceID,
            workspaceName: Self.blankToNil(input.workspaceName),
            workspacePath: Self.blankToNil(input.workspacePath),
            sessionID: Self.blankToNil(input.sessionID),
            taskID: Self.blankToNil(input.taskID),
            estimatedCost: max(input.estimatedCost ?? 0, 0),
            actualCost: max(input.actualCost ?? 0, 0),
            estimatedTokens: max(input.estimatedTokens ?? 0, 0),
            actualTokens: max(input.actualTokens ?? ((input.inputTokens ?? 0) + (input.outputTokens ?? 0)), 0),
            inputTokens: input.inputTokens.map { max($0, 0) },
            outputTokens: input.outputTokens.map { max($0, 0) },
            requestCount: input.requestCount.map { max($0, 0) },
            signal: input.signal ?? .unknown,
            followUpRequired: input.followUpRequired ?? (input.signal == .followUp),
            selectedBy: Self.blankToNil(input.selectedBy),
            alternatives: (input.alternatives ?? []).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { $0.isEmpty == false },
            routingReason: Self.blankToNil(input.routingReason),
            metadata: (input.metadata ?? [:]).filter { $0.key.isEmpty == false && $0.value.isEmpty == false }
        )
        var records = load()
        records.append(record)
        save(pruned(records, now: now))
        return record
    }

    func stats(now: Date = .now) -> SmartRoutingStatsSnapshot {
        let records = pruned(load(), now: now).sorted { $0.occurredAt > $1.occurredAt }
        let routes = Dictionary(grouping: records, by: Self.routeKey)
            .map { key, values in
                routeStats(routeKey: key, records: values)
            }
            .sorted {
                if $0.runCount != $1.runCount { return $0.runCount > $1.runCount }
                return $0.lastRunAt > $1.lastRunAt
            }

        let runCount = records.count
        let winCount = records.filter(\.isWin).count
        let followUpCount = records.filter { $0.followUpRequired || $0.signal == .followUp }.count
        let failedCount = records.filter { $0.signal == .failed }.count
        let unknownCount = records.filter { $0.signal == .unknown }.count

        return SmartRoutingStatsSnapshot(
            generatedAt: now,
            totalRuns: runCount,
            winCount: winCount,
            followUpCount: followUpCount,
            failedCount: failedCount,
            unknownCount: unknownCount,
            winRate: ratio(winCount, runCount),
            followUpRate: ratio(followUpCount, runCount),
            estimatedCostTotal: records.reduce(0) { $0 + $1.estimatedCost },
            actualCostTotal: records.reduce(0) { $0 + $1.actualCost },
            estimatedTokensTotal: records.reduce(0) { $0 + $1.estimatedTokens },
            actualTokensTotal: records.reduce(0) { $0 + $1.actualTokens },
            routeStats: routes,
            recentRuns: Array(records.prefix(20))
        )
    }

    private func load() -> [SmartRoutingRunRecord] {
        guard let data = try? Data(contentsOf: storeURL),
              let records = try? JSONDecoder.tokenBar.decode([SmartRoutingRunRecord].self, from: data) else {
            return []
        }
        return records
    }

    private func save(_ records: [SmartRoutingRunRecord]) {
        guard let data = try? JSONEncoder.tokenBar.encode(records) else { return }
        try? data.write(to: storeURL, options: [.atomic])
    }

    private func pruned(_ records: [SmartRoutingRunRecord], now: Date) -> [SmartRoutingRunRecord] {
        let cutoff = now.addingTimeInterval(-retentionSeconds)
        return Array(records.filter { $0.occurredAt >= cutoff }.suffix(maxRecords))
    }

    private static func routeKey(_ record: SmartRoutingRunRecord) -> String {
        [record.providerID, record.model.lowercased(), record.taskIntent.lowercased()].joined(separator: "|")
    }

    private func routeStats(routeKey: String, records: [SmartRoutingRunRecord]) -> SmartRoutingRouteStats {
        let runCount = records.count
        let winCount = records.filter(\.isWin).count
        let followUpCount = records.filter { $0.followUpRequired || $0.signal == .followUp }.count
        let failedCount = records.filter { $0.signal == .failed }.count
        let unknownCount = records.filter { $0.signal == .unknown }.count
        let estimatedCost = records.reduce(0) { $0 + $1.estimatedCost }
        let actualCost = records.reduce(0) { $0 + $1.actualCost }
        let estimatedTokens = records.reduce(0) { $0 + $1.estimatedTokens }
        let actualTokens = records.reduce(0) { $0 + $1.actualTokens }
        let exemplar = records.max { $0.occurredAt < $1.occurredAt }

        return SmartRoutingRouteStats(
            routeKey: routeKey,
            providerID: exemplar?.providerID ?? "unknown",
            model: exemplar?.model ?? "unspecified",
            taskIntent: exemplar?.taskIntent ?? "unspecified",
            runCount: runCount,
            winCount: winCount,
            followUpCount: followUpCount,
            failedCount: failedCount,
            unknownCount: unknownCount,
            winRate: ratio(winCount, runCount),
            followUpRate: ratio(followUpCount, runCount),
            estimatedCostTotal: estimatedCost,
            actualCostTotal: actualCost,
            estimatedTokensTotal: estimatedTokens,
            actualTokensTotal: actualTokens,
            averageCostDelta: runCount > 0 ? (actualCost - estimatedCost) / Double(runCount) : 0,
            averageTokenDelta: runCount > 0 ? Double(actualTokens - estimatedTokens) / Double(runCount) : 0,
            lastRunAt: exemplar?.occurredAt ?? .distantPast
        )
    }

    private static func normalized(_ value: String?, fallback: String) -> String {
        blankToNil(value) ?? fallback
    }

    private static func blankToNil(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    private func ratio(_ numerator: Int, _ denominator: Int) -> Double {
        guard denominator > 0 else { return 0 }
        return Double(numerator) / Double(denominator)
    }
}
