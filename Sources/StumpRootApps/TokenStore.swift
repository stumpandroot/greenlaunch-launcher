import Foundation
import Security

/// Keeps the GitHub token in the macOS keychain.
enum TokenStore {
    private static let service = "co.greenlaunch.launcher"
    private static let account = "github-token"

    private static var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    static func read() -> String? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let token = String(data: data, encoding: .utf8),
              !token.isEmpty
        else { return nil }
        return token
    }

    static func save(_ token: String) {
        delete()
        guard !token.isEmpty else { return }
        var item = baseQuery
        item[kSecValueData as String] = Data(token.utf8)
        SecItemAdd(item as CFDictionary, nil)
    }

    static func delete() {
        SecItemDelete(baseQuery as CFDictionary)
    }
}
