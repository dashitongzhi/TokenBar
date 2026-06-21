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
        guard let data = try? Data(contentsOf: storeURL),
              let saved = try? JSONDecoder.tokenBar.decode([AuditEvent].self, from: data) else {
            return Self.pruned(defaults, limit: limit)
        }
        return Self.pruned(saved, limit: limit)
    }

    func save(_ events: [AuditEvent]) {
        guard let data = try? JSONEncoder.tokenBar.encode(Self.pruned(events, limit: limit)) else { return }
        try? data.write(to: storeURL, options: [.atomic])
    }

    private static func pruned(_ events: [AuditEvent], limit: Int) -> [AuditEvent] {
        let sorted = events.sorted { $0.timestamp > $1.timestamp }
        guard sorted.count > limit else { return sorted }
        return Array(sorted.prefix(limit))
    }
}
