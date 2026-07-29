import Darwin
import Foundation
import OSLog
import Security

nonisolated final class LocalAPITokenStore: @unchecked Sendable {
    private let fileManager: FileManager
    private let tokenURL: URL
    private let lock = NSLock()
    private var cachedToken: String?

    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        let directory: URL
        if let override = ProcessInfo.processInfo.environment["TOKENBAR_STATE_DIR"]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           override.isEmpty == false {
            directory = URL(fileURLWithPath: override, isDirectory: true)
        } else {
            let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? fileManager.temporaryDirectory
            directory = support.appendingPathComponent("TokenBar", isDirectory: true)
        }
        try? fileManager.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        tokenURL = directory.appendingPathComponent("local-api-token")
    }

    func token() -> String {
        lock.lock()
        defer { lock.unlock() }
        if let cachedToken {
            return cachedToken
        }
        if let existing = try? String(contentsOf: tokenURL, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines),
           existing.isEmpty == false {
            tightenPermissions()
            cachedToken = existing
            return existing
        }

        let generated = Self.generateToken()
        do {
            cachedToken = try createSecurely(generated)
        } catch {
            Logger(
                subsystem: Bundle.main.bundleIdentifier ?? "TokenBar",
                category: "local-api"
            ).error("Failed to persist local API token: \(String(describing: error), privacy: .private)")
            // Keep one process-stable fallback token. Authentication remains
            // deterministic even when the filesystem is temporarily
            // unavailable, and the next process will retry persistence.
            cachedToken = generated
            return generated
        }
        return cachedToken ?? generated
    }

    private func createSecurely(_ token: String) throws -> String {
        let descriptor = open(
            tokenURL.path,
            O_WRONLY | O_CREAT | O_EXCL,
            S_IRUSR | S_IWUSR
        )
        if descriptor == -1 {
            if errno == EEXIST,
               let existing = try? String(contentsOf: tokenURL, encoding: .utf8)
                .trimmingCharacters(in: .whitespacesAndNewlines),
               existing.isEmpty == false {
                tightenPermissions()
                return existing
            }
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        defer { close(descriptor) }
        let data = Data(token.utf8)
        try data.withUnsafeBytes { rawBuffer in
            guard let baseAddress = rawBuffer.baseAddress else { return }
            var written = 0
            while written < rawBuffer.count {
                let result = Darwin.write(
                    descriptor,
                    baseAddress.advanced(by: written),
                    rawBuffer.count - written
                )
                guard result > 0 else {
                    throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
                }
                written += result
            }
        }
        guard fsync(descriptor) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        return token
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
