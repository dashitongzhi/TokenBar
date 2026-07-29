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
            return Self.pruned(defaults, limit: limit)
        case .loaded(let events):
            saved = events
        }
        let cleaned = Self.pruned(saved, limit: limit)
        if cleaned.count != saved.count {
            save(cleaned)
        }
        return cleaned
    }

    func save(_ events: [AuditEvent]) {
        document.saveRecovering(Self.pruned(events, limit: limit))
    }

    private static func pruned(_ events: [AuditEvent], limit: Int) -> [AuditEvent] {
        let sorted = events.sorted { $0.timestamp > $1.timestamp }
        guard sorted.count > limit else { return sorted }
        return Array(sorted.prefix(limit))
    }

}
