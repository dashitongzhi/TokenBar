import Foundation

private struct VerificationRecord: Codable, Equatable {
    var id: String
    var timestamp: Date
}

private struct VersionedVerificationRecord: Codable, Equatable {
    var name: String
    var migrationCount: Int
}

private struct VerificationEnvelope<Payload: Encodable>: Encodable {
    var schemaVersion: Int
    var payload: Payload
}

private struct FailingRecord: Codable, Equatable {
    enum CodingKeys: String, CodingKey {
        case value
    }

    var value: String
    var refusesEncoding: Bool

    init(value: String, refusesEncoding: Bool = false) {
        self.value = value
        self.refusesEncoding = refusesEncoding
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        value = try container.decode(String.self, forKey: .value)
        refusesEncoding = false
    }

    func encode(to encoder: Encoder) throws {
        if refusesEncoding {
            throw VerificationFailure(description: "fixture refused encoding")
        }
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(value, forKey: .value)
    }
}

private struct VerificationFailure: Error, CustomStringConvertible {
    let description: String
}

@main
struct VerifyJSONDocumentStore {
    static func main() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("tokenbar-document-store-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }

        try verifyMissingAndRoundTrip(in: directory)
        try verifyLegacyMigrationAndBackup(in: directory)
        try verifyVersionMigration(in: directory)
        try verifyFutureVersionIsRejected(in: directory)
        try verifyCorruptionIsPreserved(in: directory)
        try verifyCorruptOverwriteRequiresExplicitRecovery(in: directory)
        try verifyFailedSaveKeepsOriginal(in: directory)

        print("Verified JSON document missing, version migration, backup, atomic save, and corruption semantics.")
    }

    private static func verifyMissingAndRoundTrip(in directory: URL) throws {
        let store = JSONDocumentStore<[VerificationRecord]>(
            fileName: "records.json",
            directoryURL: directory
        )

        switch store.load() {
        case .missing:
            break
        default:
            throw VerificationFailure(description: "new document must report missing")
        }

        let records = [fixtureRecord]
        try store.save(records)

        switch store.load() {
        case .loaded(let saved):
            try expect(saved == records, "saved document must round-trip")
        default:
            throw VerificationFailure(description: "saved document did not load")
        }

        let object = try jsonObject(at: store.url)
        try expect(object["schemaVersion"] as? Int == 1, "new documents must declare schema version 1")
        try expect(object["payload"] != nil, "new documents must wrap their payload")
    }

    private static func verifyLegacyMigrationAndBackup(in directory: URL) throws {
        let store = JSONDocumentStore<VersionedVerificationRecord>(
            fileName: "legacy.json",
            directoryURL: directory,
            schemaVersion: 2,
            migrate: { record, sourceVersion in
                guard sourceVersion == 0 || sourceVersion == 1 else {
                    throw VerificationFailure(description: "unexpected legacy source version \(sourceVersion)")
                }
                var migrated = record
                migrated.migrationCount += 1
                return migrated
            }
        )
        let original = VersionedVerificationRecord(name: "legacy", migrationCount: 0)
        let legacyData = try encoder().encode(original)
        try legacyData.write(to: store.url, options: [.atomic])

        switch store.load() {
        case .loaded(let saved):
            try expect(
                saved == VersionedVerificationRecord(name: "legacy", migrationCount: 2),
                "legacy payload must run migrations from schema 0 through the current version"
            )
        default:
            throw VerificationFailure(description: "legacy payload did not migrate")
        }

        let backups = backupURLs(for: store.url)
        try expect(backups.count == 1, "legacy migration must retain exactly one backup")
        try expect(try Data(contentsOf: backups[0]) == legacyData, "legacy backup must preserve original bytes")
        let object = try jsonObject(at: store.url)
        try expect(object["schemaVersion"] as? Int == 2, "legacy payload must migrate to the current version")
    }

    private static func verifyVersionMigration(in directory: URL) throws {
        let store = JSONDocumentStore<VersionedVerificationRecord>(
            fileName: "versioned.json",
            directoryURL: directory,
            schemaVersion: 2,
            migrate: { record, sourceVersion in
                guard sourceVersion == 1 else {
                    throw VerificationFailure(description: "unexpected source version \(sourceVersion)")
                }
                var migrated = record
                migrated.migrationCount += 1
                return migrated
            }
        )
        let original = VersionedVerificationRecord(name: "fixture", migrationCount: 0)
        let oldEnvelope = try envelopeData(payload: original, schemaVersion: 1)
        try oldEnvelope.write(to: store.url, options: [.atomic])

        switch store.load() {
        case .loaded(let migrated):
            try expect(
                migrated == VersionedVerificationRecord(name: "fixture", migrationCount: 1),
                "version migration must transform the payload"
            )
        default:
            throw VerificationFailure(description: "older version did not migrate")
        }

        try expect(backupURLs(for: store.url).count == 1, "version migration must retain a backup")
        let object = try jsonObject(at: store.url)
        try expect(object["schemaVersion"] as? Int == 2, "version migration must persist current version")
    }

    private static func verifyFutureVersionIsRejected(in directory: URL) throws {
        let store = JSONDocumentStore<[VerificationRecord]>(
            fileName: "future.json",
            directoryURL: directory
        )
        let futureData = try envelopeData(payload: [fixtureRecord], schemaVersion: 99)
        try futureData.write(to: store.url, options: [.atomic])

        switch store.load() {
        case .unreadable(let error):
            try expect(
                String(describing: error).contains("99"),
                "unsupported-version error must identify the stored version"
            )
        default:
            throw VerificationFailure(description: "future version must be rejected")
        }

        try expect(try Data(contentsOf: store.url) == futureData, "future document must remain unchanged")
        try expect(backupURLs(for: store.url).isEmpty, "read-only rejection must not create a backup")

        do {
            try store.save([fixtureRecord])
            throw VerificationFailure(description: "automatic save must not overwrite a future document")
        } catch let error as JSONDocumentStoreError {
            try expect(
                String(describing: error).contains("explicit recovery"),
                "future document overwrite must require explicit recovery"
            )
        }
        try expect(try Data(contentsOf: store.url) == futureData, "blocked save must preserve future bytes")
    }

    private static func verifyCorruptionIsPreserved(in directory: URL) throws {
        let store = JSONDocumentStore<[VerificationRecord]>(
            fileName: "corrupt.json",
            directoryURL: directory
        )
        let corruptData = Data("{not-json".utf8)
        try corruptData.write(to: store.url, options: [.atomic])

        switch store.load() {
        case .unreadable:
            break
        default:
            throw VerificationFailure(description: "corrupt document must report unreadable")
        }

        try expect(try Data(contentsOf: store.url) == corruptData, "load must not replace corrupt bytes")
        try expect(backupURLs(for: store.url).isEmpty, "read-only corruption detection must not create a backup")
    }

    private static func verifyCorruptOverwriteRequiresExplicitRecovery(in directory: URL) throws {
        let store = JSONDocumentStore<[VerificationRecord]>(
            fileName: "recover-corrupt.json",
            directoryURL: directory
        )
        let corruptData = Data("{still-not-json".utf8)
        try corruptData.write(to: store.url, options: [.atomic])

        do {
            try store.save([fixtureRecord])
            throw VerificationFailure(description: "automatic save must not overwrite corrupt data")
        } catch let error as JSONDocumentStoreError {
            try expect(
                String(describing: error).contains("explicit recovery"),
                "corrupt document overwrite must require explicit recovery"
            )
        }
        try expect(try Data(contentsOf: store.url) == corruptData, "blocked save must preserve corrupt bytes")
        try expect(backupURLs(for: store.url).isEmpty, "blocked save must not create a backup")

        try store.save([fixtureRecord], allowRecovery: true)

        let backups = backupURLs(for: store.url)
        try expect(backups.count == 1, "overwriting corrupt data must first create one backup")
        try expect(try Data(contentsOf: backups[0]) == corruptData, "corrupt backup must preserve original bytes")
        switch store.load() {
        case .loaded(let saved):
            try expect(saved == [fixtureRecord], "explicit save must recover from corrupt data")
        default:
            throw VerificationFailure(description: "recovered document did not load")
        }
    }

    private static func verifyFailedSaveKeepsOriginal(in directory: URL) throws {
        let store = JSONDocumentStore<FailingRecord>(
            fileName: "failed-save.json",
            directoryURL: directory
        )
        try store.save(FailingRecord(value: "original"))
        let originalData = try Data(contentsOf: store.url)

        do {
            try store.save(FailingRecord(value: "replacement", refusesEncoding: true))
            throw VerificationFailure(description: "fixture save should fail")
        } catch let failure as VerificationFailure where failure.description == "fixture save should fail" {
            throw failure
        } catch {
            // Expected: encoding finishes before the atomic replacement begins.
        }

        try expect(try Data(contentsOf: store.url) == originalData, "failed save must preserve original bytes")
    }

    private static var fixtureRecord: VerificationRecord {
        VerificationRecord(
            id: "fixture",
            timestamp: Date(timeIntervalSince1970: 1_725_408_000)
        )
    }

    private static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }

    private static func envelopeData<Payload: Encodable>(
        payload: Payload,
        schemaVersion: Int
    ) throws -> Data {
        try encoder().encode(
            VerificationEnvelope(schemaVersion: schemaVersion, payload: payload)
        )
    }

    private static func jsonObject(at url: URL) throws -> [String: Any] {
        let data = try Data(contentsOf: url)
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw VerificationFailure(description: "document must be a JSON object")
        }
        return object
    }

    private static func backupURLs(for url: URL) -> [URL] {
        let directory = url.deletingLastPathComponent()
        let prefix = url.lastPathComponent + ".backup-"
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        )) ?? []
        return contents.filter { $0.lastPathComponent.hasPrefix(prefix) }.sorted { $0.path < $1.path }
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
