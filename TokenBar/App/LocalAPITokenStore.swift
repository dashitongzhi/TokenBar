import Foundation
import Security

struct LocalAPITokenStore {
    private let fileManager: FileManager
    private let tokenURL: URL

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first ?? fileManager.temporaryDirectory
        let directory = support.appendingPathComponent("TokenBar", isDirectory: true)
        try? fileManager.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        tokenURL = directory.appendingPathComponent("local-api-token")
    }

    func token() -> String {
        if let existing = try? String(contentsOf: tokenURL, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines),
           existing.isEmpty == false {
            tightenPermissions()
            return existing
        }

        let generated = Self.generateToken()
        do {
            try Data(generated.utf8).write(to: tokenURL, options: [.atomic])
            tightenPermissions()
        } catch {
            return generated
        }
        return generated
    }

    private func tightenPermissions() {
        try? fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: tokenURL.path)
    }

    private static func generateToken() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        if status == errSecSuccess {
            return Data(bytes)
                .base64EncodedString()
                .replacingOccurrences(of: "+", with: "-")
                .replacingOccurrences(of: "/", with: "_")
                .replacingOccurrences(of: "=", with: "")
        }

        return [UUID().uuidString, UUID().uuidString].joined(separator: "")
    }
}
