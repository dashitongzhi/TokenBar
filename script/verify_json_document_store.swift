import Foundation

private struct VerificationRecord: Codable, Equatable {
    var id: String
    var timestamp: Date
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

        let records = [
            VerificationRecord(
                id: "fixture",
                timestamp: Date(timeIntervalSince1970: 1_725_408_000)
            )
        ]
        try store.save(records)

        switch store.load() {
        case .loaded(let saved):
            try expect(saved == records, "saved document must round-trip")
        default:
            throw VerificationFailure(description: "saved document did not load")
        }

        try Data("{not-json".utf8).write(to: store.url, options: [.atomic])
        switch store.load() {
        case .unreadable:
            break
        default:
            throw VerificationFailure(description: "corrupt document must report unreadable")
        }

        print("Verified JSON document missing, atomic round-trip, and corruption semantics.")
    }

    private static func expect(
        _ condition: @autoclosure () -> Bool,
        _ message: String
    ) throws {
        guard condition() else {
            throw VerificationFailure(description: message)
        }
    }
}
