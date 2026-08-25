import Foundation
import Security

/// Generic-password storage, one slot per device profile (account = the
/// profile's UUID). The pre-device-manager app used a single "modem"
/// account; `migrateLegacyPassword` retires it on first launch.
enum Keychain {
    private static let service = "io.8lines.router-menu"

    // MARK: Per-profile API

    static func password(for profileID: UUID) -> String? {
        item(account: profileID.uuidString)
    }

    static func setPassword(_ password: String, for profileID: UUID) {
        setItem(password, account: profileID.uuidString)
    }

    static func deletePassword(for profileID: UUID) {
        deleteItem(account: profileID.uuidString)
    }

    /// Copies the legacy single-slot item into the profile's slot — only
    /// when that slot is empty — then deletes the legacy item. Idempotent,
    /// safe to call every launch.
    static func migrateLegacyPassword(from legacyAccount: String = "modem",
                                      to profileID: UUID) {
        guard let legacy = item(account: legacyAccount) else { return }
        if password(for: profileID) == nil {
            setPassword(legacy, for: profileID)
        }
        deleteItem(account: legacyAccount)
    }

    // MARK: Raw item access (internal so tests can stage a fake legacy slot)

    static func item(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data,
              let string = String(data: data, encoding: .utf8) else {
            return nil
        }
        return string
    }

    static func setItem(_ value: String, account: String) {
        deleteItem(account: account)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: Data(value.utf8),
        ]
        SecItemAdd(query as CFDictionary, nil)
    }

    static func deleteItem(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
