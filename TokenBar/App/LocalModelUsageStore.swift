import Foundation

struct LocalModelUsageStore {
    private let document: JSONDocumentStore<[ModelUsageRollup]>
    private let calendar = Calendar(identifier: .gregorian)

    init(
        fileManager: FileManager = .default,
        directoryURL: URL? = nil
    ) {
        document = JSONDocumentStore(
            fileName: "local-model-usage-rollups.json",
            fileManager: fileManager,
            directoryURL: directoryURL
        )
    }

    func load(now: Date = .now) -> [ModelUsageRollup] {
        var rollups: [ModelUsageRollup]
        switch document.load() {
        case .missing, .unreadable:
            return []
        case .loaded(let saved):
            rollups = saved
        }

        let day = dayKey(for: now)
        let month = monthKey(for: now)
        for index in rollups.indices {
            resetExpiredBuckets(&rollups[index], day: day, month: month)
        }
        return rollups
    }

    func apply(snapshot: LocalAgentUsageAppliedSnapshot) -> [ModelUsageRollup] {
        var rollups = load(now: snapshot.occurredAt)
        let day = dayKey(for: snapshot.occurredAt)
        let month = monthKey(for: snapshot.occurredAt)
        let model = normalizedModel(snapshot.model)

        let index = rollups.firstIndex {
            $0.agent == snapshot.agent &&
            $0.providerID == snapshot.providerID &&
            normalizedModel($0.model) == model &&
            $0.source == .localAgent
        }

        if let index {
            resetExpiredBuckets(&rollups[index], day: day, month: month)
            rollups[index].spendToday += snapshot.costDelta
            rollups[index].spendMonth += snapshot.costDelta
            rollups[index].tokensToday += snapshot.tokenDelta
            rollups[index].tokensMonth += snapshot.tokenDelta
            rollups[index].requestCountToday += snapshot.requestDelta
            rollups[index].requestCountMonth += snapshot.requestDelta
            rollups[index].lastUpdated = snapshot.occurredAt
        } else {
            rollups.append(ModelUsageRollup(
                agent: snapshot.agent,
                providerID: snapshot.providerID,
                model: snapshot.model,
                source: .localAgent,
                configPath: nil,
                spendToday: snapshot.costDelta,
                spendMonth: snapshot.costDelta,
                tokensToday: snapshot.tokenDelta,
                tokensMonth: snapshot.tokenDelta,
                requestCountToday: snapshot.requestDelta,
                requestCountMonth: snapshot.requestDelta,
                dayKey: day,
                monthKey: month,
                lastUpdated: snapshot.occurredAt
            ))
        }

        save(rollups)
        return rollups
    }

    private func save(_ rollups: [ModelUsageRollup]) {
        try? document.save(rollups)
    }

    private func resetExpiredBuckets(_ rollup: inout ModelUsageRollup, day: String, month: String) {
        if rollup.dayKey != day {
            rollup.spendToday = 0
            rollup.tokensToday = 0
            rollup.requestCountToday = 0
            rollup.dayKey = day
        }
        if rollup.monthKey != month {
            rollup.spendMonth = 0
            rollup.tokensMonth = 0
            rollup.requestCountMonth = 0
            rollup.monthKey = month
        }
    }

    private func dayKey(for date: Date) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
    }

    private func monthKey(for date: Date) -> String {
        let components = calendar.dateComponents([.year, .month], from: date)
        return String(format: "%04d-%02d", components.year ?? 0, components.month ?? 0)
    }

    private func normalizedModel(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
