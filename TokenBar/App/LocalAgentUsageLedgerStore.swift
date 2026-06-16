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
    private let storeURL: URL

    init(fileManager: FileManager = .default) {
        let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? fileManager.temporaryDirectory
        let directory = support.appendingPathComponent("TokenBar", isDirectory: true)
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        storeURL = directory.appendingPathComponent("local-agent-usage-ledger.json")
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
        guard let data = try? Data(contentsOf: storeURL),
              let ledger = try? JSONDecoder.tokenBar.decode([String: LocalAgentUsageCursor].self, from: data) else {
            return [:]
        }
        return ledger
    }

    private func save(_ ledger: [String: LocalAgentUsageCursor]) {
        guard let data = try? JSONEncoder.tokenBar.encode(ledger) else { return }
        try? data.write(to: storeURL, options: [.atomic])
    }

    private func pruned(_ ledger: [String: LocalAgentUsageCursor], now: Date) -> [String: LocalAgentUsageCursor] {
        let cutoff = now.addingTimeInterval(-14 * 24 * 3600)
        return ledger.filter { $0.value.updatedAt >= cutoff }
    }
}
