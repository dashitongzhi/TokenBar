import Foundation

enum JSONDocumentLoadResult<Value> {
    case missing
    case loaded(Value)
    case unreadable(Error)
}

struct JSONDocumentStore<Value: Codable> {
    let url: URL

    init(
        fileName: String,
        fileManager: FileManager = .default,
        directoryURL: URL? = nil
    ) {
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
        url = directory.appendingPathComponent(fileName)
    }

    func load() -> JSONDocumentLoadResult<Value> {
        do {
            let data = try Data(contentsOf: url)
            return .loaded(try Self.decoder().decode(Value.self, from: data))
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            return .missing
        } catch {
            return .unreadable(error)
        }
    }

    func save(_ value: Value) throws {
        let data = try Self.encoder().encode(value)
        try data.write(to: url, options: [.atomic])
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
}
