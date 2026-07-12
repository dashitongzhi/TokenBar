import Foundation

@MainActor
final class SmartRoutingLedgerStore {
    private let storeURL: URL
    private let maxRecords = 2_000
    private let retentionSeconds: TimeInterval = 90 * 24 * 3600

    init(fileManager: FileManager = .default, storeURL: URL? = nil) {
        if let storeURL {
            self.storeURL = storeURL
            return
        }
        let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? fileManager.temporaryDirectory
        let directory = support.appendingPathComponent("TokenBar", isDirectory: true)
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        self.storeURL = directory.appendingPathComponent("smart-routing-runs.json")
    }

    func record(_ input: SmartRoutingRunInput, fallbackWorkspaceID: String?, fallbackAgent: AgentProvider, now: Date = .now) -> SmartRoutingRunRecord {
        var record = SmartRoutingRunRecord(
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
            estimatedCostKnown: input.estimatedCost != nil,
            actualCostKnown: input.actualCost != nil,
            estimatedTokens: max(input.estimatedTokens ?? 0, 0),
            actualTokens: max(input.actualTokens ?? ((input.inputTokens ?? 0) + (input.outputTokens ?? 0)), 0),
            estimatedTokensKnown: input.estimatedTokens != nil,
            actualTokensKnown: input.actualTokens != nil || input.inputTokens != nil || input.outputTokens != nil,
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
        if let existingIndex = records.firstIndex(where: { Self.isSameRun($0, record) }) {
            record.id = records[existingIndex].id
            records[existingIndex] = record
        } else {
            records.append(record)
        }
        save(pruned(records, now: now))
        return record
    }

    func stats(now: Date = .now) -> SmartRoutingStatsSnapshot {
        let allRecords = pruned(load(), now: now).sorted { $0.occurredAt > $1.occurredAt }
        let records = allRecords.filter(Self.isProductionRecommendationEligible)
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
        let knownEstimatedCostRecords = records.filter(\.hasKnownEstimatedCost)
        let knownActualCostRecords = records.filter(\.hasKnownActualCost)
        let knownEstimatedTokenRecords = records.filter(\.hasKnownEstimatedTokens)
        let knownActualTokenRecords = records.filter(\.hasKnownActualTokens)

        return SmartRoutingStatsSnapshot(
            generatedAt: now,
            totalRuns: runCount,
            winCount: winCount,
            followUpCount: followUpCount,
            failedCount: failedCount,
            unknownCount: unknownCount,
            winRate: ratio(winCount, runCount),
            followUpRate: ratio(followUpCount, runCount),
            estimatedCostTotal: knownEstimatedCostRecords.reduce(0) { $0 + $1.estimatedCost },
            actualCostTotal: knownActualCostRecords.reduce(0) { $0 + $1.actualCost },
            estimatedCostKnownRunCount: knownEstimatedCostRecords.count,
            actualCostKnownRunCount: knownActualCostRecords.count,
            estimatedTokensTotal: knownEstimatedTokenRecords.reduce(0) { $0 + $1.estimatedTokens },
            actualTokensTotal: knownActualTokenRecords.reduce(0) { $0 + $1.actualTokens },
            estimatedTokensKnownRunCount: knownEstimatedTokenRecords.count,
            actualTokensKnownRunCount: knownActualTokenRecords.count,
            excludedNonProductionRuns: allRecords.count - records.count,
            routeStats: routes,
            recentRuns: Array(records.prefix(20))
        )
    }

    nonisolated static func isProductionRecommendationEligible(_ record: SmartRoutingRunRecord) -> Bool {
        SmartRoutingRecommendationEligibility.isProductionRecommendationEligible(
            SmartRoutingRecommendationMarker(
                taskIntent: record.taskIntent,
                workspaceID: record.workspaceID,
                workspaceName: record.workspaceName,
                sessionID: record.sessionID,
                taskID: record.taskID,
                selectedBy: record.selectedBy,
                model: record.model,
                routingReason: record.routingReason,
                metadata: record.metadata
            )
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

    private nonisolated static func routeKey(_ record: SmartRoutingRunRecord) -> String {
        [record.providerID, record.model.lowercased(), record.taskIntent.lowercased()].joined(separator: "|")
    }

    private func routeStats(routeKey: String, records: [SmartRoutingRunRecord]) -> SmartRoutingRouteStats {
        let runCount = records.count
        let winCount = records.filter(\.isWin).count
        let followUpCount = records.filter { $0.followUpRequired || $0.signal == .followUp }.count
        let failedCount = records.filter { $0.signal == .failed }.count
        let unknownCount = records.filter { $0.signal == .unknown }.count
        let knownEstimatedCostRecords = records.filter(\.hasKnownEstimatedCost)
        let knownActualCostRecords = records.filter(\.hasKnownActualCost)
        let knownEstimatedTokenRecords = records.filter(\.hasKnownEstimatedTokens)
        let knownActualTokenRecords = records.filter(\.hasKnownActualTokens)
        let estimatedCost = knownEstimatedCostRecords.reduce(0) { $0 + $1.estimatedCost }
        let actualCost = knownActualCostRecords.reduce(0) { $0 + $1.actualCost }
        let estimatedTokens = knownEstimatedTokenRecords.reduce(0) { $0 + $1.estimatedTokens }
        let actualTokens = knownActualTokenRecords.reduce(0) { $0 + $1.actualTokens }
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
            estimatedCostKnownRunCount: knownEstimatedCostRecords.count,
            actualCostKnownRunCount: knownActualCostRecords.count,
            estimatedTokensTotal: estimatedTokens,
            actualTokensTotal: actualTokens,
            estimatedTokensKnownRunCount: knownEstimatedTokenRecords.count,
            actualTokensKnownRunCount: knownActualTokenRecords.count,
            averageCostDelta: SmartRoutingCostMetrics.averageCostDelta(
                observations: records.map {
                    SmartRoutingCostObservation(
                        estimated: $0.hasKnownEstimatedCost ? $0.estimatedCost : nil,
                        actual: $0.hasKnownActualCost ? $0.actualCost : nil
                    )
                }
            ),
            averageTokenDelta: SmartRoutingCostMetrics.averageTokenDelta(
                observations: records.map {
                    SmartRoutingTokenObservation(
                        estimated: $0.hasKnownEstimatedTokens ? $0.estimatedTokens : nil,
                        actual: $0.hasKnownActualTokens ? $0.actualTokens : nil
                    )
                }
            ),
            lastRunAt: exemplar?.occurredAt ?? .distantPast
        )
    }

    private static func normalized(_ value: String?, fallback: String) -> String {
        blankToNil(value) ?? fallback
    }

    private nonisolated static func isSameRun(_ lhs: SmartRoutingRunRecord, _ rhs: SmartRoutingRunRecord) -> Bool {
        if let taskID = lhs.taskID, taskID == rhs.taskID, lhs.workspaceID == rhs.workspaceID {
            return true
        }
        guard let sessionID = lhs.sessionID, sessionID == rhs.sessionID else { return false }
        return lhs.workspaceID == rhs.workspaceID &&
            lhs.taskIntent == rhs.taskIntent &&
            lhs.providerID == rhs.providerID &&
            lhs.model.caseInsensitiveCompare(rhs.model) == .orderedSame
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

private extension SmartRoutingRunRecord {
    var hasKnownEstimatedCost: Bool {
        // Records written before the known-value markers were introduced stored
        // numeric values directly. Preserve their existing totals on upgrade.
        estimatedCostKnown != false
    }

    var hasKnownActualCost: Bool {
        actualCostKnown != false
    }

    var hasKnownEstimatedTokens: Bool {
        estimatedTokensKnown != false
    }

    var hasKnownActualTokens: Bool {
        actualTokensKnown != false
    }
}
