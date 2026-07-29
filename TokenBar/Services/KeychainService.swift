import Foundation
import Security

actor KeychainService {
    static let shared = KeychainService()
    private let service = "com.tokenbar.api-keys"

    func store(value: String, for key: String, workspace: String = "default") throws {
        let account = accountName(workspace: workspace, key: key)
        let data = Data(value.utf8)
        let query = baseQuery(account: account, dataProtection: true)
        let update: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]

        let status = SecItemUpdate(query as CFDictionary, update as CFDictionary)
        if status == errSecSuccess { return }
        if status != errSecItemNotFound { throw KeychainError.status(status) }

        var item = query
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        let addStatus = SecItemAdd(item as CFDictionary, nil)
        guard addStatus == errSecSuccess else { throw KeychainError.status(addStatus) }
    }

    func retrieve(key: String, workspace: String = "default") throws -> String? {
        let account = accountName(workspace: workspace, key: key)
        if let value = try retrieve(account: account, dataProtection: true) {
            return value
        }

        // Migrate the legacy ambiguous account name/login-keychain item on first read.
        let legacyAccount = "\(workspace).\(key)"
        guard let legacyValue = try retrieve(account: legacyAccount, dataProtection: false) else {
            return nil
        }
        try store(value: legacyValue, for: key, workspace: workspace)
        SecItemDelete(baseQuery(account: legacyAccount, dataProtection: false) as CFDictionary)
        return legacyValue
    }

    func delete(key: String, workspace: String = "default") throws {
        let accounts = [
            (accountName(workspace: workspace, key: key), true),
            ("\(workspace).\(key)", false)
        ]
        for (account, dataProtection) in accounts {
            let status = SecItemDelete(baseQuery(account: account, dataProtection: dataProtection) as CFDictionary)
            guard status == errSecSuccess || status == errSecItemNotFound else {
                throw KeychainError.status(status)
            }
        }
    }

    private func retrieve(account: String, dataProtection: Bool) throws -> String? {
        var query = baseQuery(account: account, dataProtection: dataProtection)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw KeychainError.status(status) }
        guard let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func baseQuery(account: String, dataProtection: Bool) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecUseDataProtectionKeychain as String: dataProtection
        ]
    }

    private func accountName(workspace: String, key: String) -> String {
        "\(workspace.utf8.count):\(workspace)\(key.utf8.count):\(key)"
    }
}

enum KeychainError: LocalizedError {
    case status(OSStatus)

    var errorDescription: String? {
        switch self {
        case .status(let status):
            SecCopyErrorMessageString(status, nil) as String? ?? "Keychain error \(status)"
        }
    }
}
