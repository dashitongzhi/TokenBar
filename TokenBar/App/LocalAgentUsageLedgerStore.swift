import Foundation

struct LocalAgentUsageCursor: Codable, Equatable {
    var costUSD: Double
    var tokens: Double
    var requestCount: Int
    var updatedAt: Date
}

struct LocalAgentUsageDelta: Equatable {
    var costUSD: Double
    var tokens: Double
    var requestCount: Int
}

struct LocalAgentUsageLedgerStore {
    private let document: JSONDocumentStore<[String: LocalAgentUsageCursor]>

    init(
        fileManager: FileManager = .default,
        directoryURL: URL? = nil
    ) {
        document = JSONDocumentStore(
            fileName: "local-agent-usage-ledger.json",
            fileManager: fileManager,
            directoryURL: directoryURL
        )
    }

    func apply(sessionKey: String, cumulativeCost: Double, cumulativeTokens: Double, cumulativeRequestCount: Int, now: Date) -> LocalAgentUsageDelta {
        var ledger = load()
        let previous = ledger[sessionKey]
        let delta = LocalAgentUsageDelta(
            costUSD: max(cumulativeCost - (previous?.costUSD ?? 0), 0),
            tokens: max(cumulativeTokens - (previous?.tokens ?? 0), 0),
            requestCount: max(cumulativeRequestCount - (previous?.requestCount ?? 0), 0)
        )
        ledger[sessionKey] = LocalAgentUsageCursor(
            costUSD: max(cumulativeCost, previous?.costUSD ?? 0),
            tokens: max(cumulativeTokens, previous?.tokens ?? 0),
            requestCount: max(cumulativeRequestCount, previous?.requestCount ?? 0),
            updatedAt: now
        )
        save(pruned(ledger, now: now))
        return delta
    }

    private func load() -> [String: LocalAgentUsageCursor] {
        switch document.load() {
        case .missing, .unreadable:
            return [:]
        case .loaded(let ledger):
            return ledger
        }
    }

    private func save(_ ledger: [String: LocalAgentUsageCursor]) {
        try? document.save(ledger)
    }

    private func pruned(_ ledger: [String: LocalAgentUsageCursor], now: Date) -> [String: LocalAgentUsageCursor] {
        let cutoff = now.addingTimeInterval(-14 * 24 * 3600)
        return ledger.filter { $0.value.updatedAt >= cutoff }
    }
}
