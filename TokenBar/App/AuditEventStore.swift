import Foundation

struct AuditEventStore {
    private let storeURL: URL
    private let limit: Int

    init(fileManager: FileManager = .default, limit: Int = 100) {
        self.limit = limit
        let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? fileManager.temporaryDirectory
        let directory = support.appendingPathComponent("TokenBar", isDirectory: true)
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        storeURL = directory.appendingPathComponent("audit-events.json")
    }

    func load(defaults: [AuditEvent]) -> [AuditEvent] {
        guard let data = try? Data(contentsOf: storeURL) else {
            return Self.pruned(defaults, limit: limit)
        }
        guard let saved = try? JSONDecoder.tokenBar.decode([AuditEvent].self, from: data) else {
            let cleanedDefaults = Self.pruned(defaults, limit: limit)
            save(cleanedDefaults)
            return cleanedDefaults
        }
        let cleaned = Self.pruned(Self.removingDemoEvents(saved), limit: limit)
        if cleaned.count != saved.count {
            save(cleaned)
        }
        return cleaned
    }

    func save(_ events: [AuditEvent]) {
        guard let data = try? JSONEncoder.tokenBar.encode(Self.pruned(Self.removingDemoEvents(events), limit: limit)) else { return }
        try? data.write(to: storeURL, options: [.atomic])
    }

    private static func pruned(_ events: [AuditEvent], limit: Int) -> [AuditEvent] {
        let sorted = events.sorted { $0.timestamp > $1.timestamp }
        guard sorted.count > limit else { return sorted }
        return Array(sorted.prefix(limit))
    }

    private static func removingDemoEvents(_ events: [AuditEvent]) -> [AuditEvent] {
        events.filter { event in
            demoEventMarkers.contains { marker in
                event.detail.localizedCaseInsensitiveContains(marker)
                    || event.provider.localizedCaseInsensitiveContains(marker)
            } == false
        }
    }

    private static let demoEventMarkers = [
        "Client App",
        "Personal Lab",
        "Production Fix",
        "Ship Client",
        "claude-opus"
    ]
}
