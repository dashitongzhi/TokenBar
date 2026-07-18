import Foundation

enum JSONDocumentLoadResult<Value> {
    case missing
    case loaded(Value)
    case unreadable(Error)
}

enum JSONDocumentStoreError: Error, CustomStringConvertible {
    case unsupportedVersion(stored: Int, current: Int, url: URL)
    case invalidVersion(stored: Int, url: URL)
    case recoveryRequired(label: String, url: URL)

    var description: String {
        switch self {
        case .unsupportedVersion(let stored, let current, let url):
            return "Unsupported JSON document schema version \(stored) at \(url.path); current version is \(current)."
        case .invalidVersion(let stored, let url):
            return "Invalid JSON document schema version \(stored) at \(url.path)."
        case .recoveryRequired(let label, let url):
            return "Refusing to overwrite \(label) JSON document at \(url.path) without explicit recovery."
        }
    }
}

/// Owns the on-disk contract for a versioned JSON document.
///
/// Existing unversioned payloads are treated as schema version 0 and wrapped
/// without changing their value. Older envelopes are migrated one version at
/// a time. Every automatic rewrite, and every explicit overwrite of an
/// unreadable or incompatible document, first preserves the original bytes in
/// a sibling backup. Normal saves use an atomic file replacement.
struct JSONDocumentStore<Value: Codable> {
    typealias Migration = (_ value: Value, _ sourceVersion: Int) throws -> Value

    let url: URL

    private let fileManager: FileManager
    private let schemaVersion: Int
    private let migrate: Migration

    init(
        fileName: String,
        fileManager: FileManager = .default,
        directoryURL: URL? = nil,
        schemaVersion: Int = 1,
        migrate: @escaping Migration = { value, _ in value }
    ) {
        precondition(schemaVersion > 0, "JSON document schema version must be positive")
        let directory = directoryURL ?? {
            let support = fileManager.urls(
                for: .applicationSupportDirectory,
                in: .userDomainMask
            ).first ?? fileManager.temporaryDirectory
            return support.appendingPathComponent("TokenBar", isDirectory: true)
        }()
        try? fileManager.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        self.fileManager = fileManager
        self.schemaVersion = schemaVersion
        self.migrate = migrate
        url = directory.appendingPathComponent(fileName)
    }

    func load() -> JSONDocumentLoadResult<Value> {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            return .missing
        } catch {
            return .unreadable(error)
        }

        do {
            if let envelope = try? Self.decoder().decode(Envelope.self, from: data) {
                return try load(envelope, originalData: data)
            }

            var legacyValue = try Self.decoder().decode(Value.self, from: data)
            for sourceVersion in 0..<schemaVersion {
                legacyValue = try migrate(legacyValue, sourceVersion)
            }
            try rewriteAfterBackup(
                legacyValue,
                originalData: data,
                backupLabel: "legacy"
            )
            return .loaded(legacyValue)
        } catch {
            return .unreadable(error)
        }
    }

    func save(_ value: Value, allowRecovery: Bool = false) throws {
        let data = try encodedEnvelope(value)
        if let existingData = try existingData() {
            let backupLabel = backupLabelRequiredBeforeOverwrite(existingData)
            if let backupLabel {
                guard allowRecovery else {
                    throw JSONDocumentStoreError.recoveryRequired(
                        label: backupLabel,
                        url: url
                    )
                }
                try createBackup(originalData: existingData, label: backupLabel)
            }
        }
        try atomicWrite(data)
    }

    private func load(
        _ envelope: Envelope,
        originalData: Data
    ) throws -> JSONDocumentLoadResult<Value> {
        guard envelope.schemaVersion > 0 else {
            throw JSONDocumentStoreError.invalidVersion(
                stored: envelope.schemaVersion,
                url: url
            )
        }
        guard envelope.schemaVersion <= schemaVersion else {
            throw JSONDocumentStoreError.unsupportedVersion(
                stored: envelope.schemaVersion,
                current: schemaVersion,
                url: url
            )
        }
        guard envelope.schemaVersion < schemaVersion else {
            return .loaded(envelope.payload)
        }

        var migrated = envelope.payload
        for sourceVersion in envelope.schemaVersion..<schemaVersion {
            migrated = try migrate(migrated, sourceVersion)
        }
        try rewriteAfterBackup(
            migrated,
            originalData: originalData,
            backupLabel: "v\(envelope.schemaVersion)"
        )
        return .loaded(migrated)
    }

    private func rewriteAfterBackup(
        _ value: Value,
        originalData: Data,
        backupLabel: String
    ) throws {
        let migratedData = try encodedEnvelope(value)
        try createBackup(originalData: originalData, label: backupLabel)
        try atomicWrite(migratedData)
    }

    private func backupLabelRequiredBeforeOverwrite(_ data: Data) -> String? {
        if let envelope = try? Self.decoder().decode(Envelope.self, from: data) {
            guard envelope.schemaVersion != schemaVersion else { return nil }
            return envelope.schemaVersion > 0 ? "v\(envelope.schemaVersion)" : "invalid-version"
        }
        if (try? Self.decoder().decode(Value.self, from: data)) != nil {
            return "legacy"
        }
        return "corrupt"
    }

    private func existingData() throws -> Data? {
        do {
            return try Data(contentsOf: url)
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            return nil
        }
    }

    private func createBackup(originalData: Data, label: String) throws {
        let backupURL = url
            .deletingLastPathComponent()
            .appendingPathComponent(
                "\(url.lastPathComponent).backup-\(label)-\(UUID().uuidString)"
            )
        try originalData.write(to: backupURL, options: [.atomic])
    }

    private func atomicWrite(_ data: Data) throws {
        try fileManager.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try data.write(to: url, options: [.atomic])
    }

    private func encodedEnvelope(_ value: Value) throws -> Data {
        try Self.encoder().encode(
            Envelope(schemaVersion: schemaVersion, payload: value)
        )
    }

    private static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }

    private static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    private struct Envelope: Codable {
        var schemaVersion: Int
        var payload: Value
    }
}
