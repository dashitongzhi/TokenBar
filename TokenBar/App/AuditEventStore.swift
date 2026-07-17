import Foundation

struct AuditEventStore {
    private let document: JSONDocumentStore<[AuditEvent]>
    private let limit: Int

    init(
        fileManager: FileManager = .default,
        directoryURL: URL? = nil,
        limit: Int = 100
    ) {
        self.limit = limit
        document = JSONDocumentStore(
            fileName: "audit-events.json",
            fileManager: fileManager,
            directoryURL: directoryURL
        )
    }

    func load(defaults: [AuditEvent]) -> [AuditEvent] {
        let saved: [AuditEvent]
        switch document.load() {
        case .missing:
            return Self.pruned(defaults, limit: limit)
        case .unreadable:
            let cleanedDefaults = Self.pruned(defaults, limit: limit)
            save(cleanedDefaults)
            return cleanedDefaults
        case .loaded(let events):
            saved = events
        }
        let cleaned = Self.pruned(Self.removingDemoEvents(saved), limit: limit)
        if cleaned.count != saved.count {
            save(cleaned)
        }
        return cleaned
    }

    func save(_ events: [AuditEvent]) {
        try? document.save(Self.pruned(Self.removingDemoEvents(events), limit: limit))
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
