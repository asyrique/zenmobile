import Foundation
#if canImport(Security)
import Security
#endif

/// Holds the serialized Firefox account (refresh token and sync keys), so it
/// must never land in UserDefaults or a plain file.
///
/// iOS: Keychain, this device only. Android: not implemented yet. The
/// account lives only in memory and the user signs in each launch. Next step
/// is a Keystore-backed implementation in a `#if SKIP` block (or skip-keychain).
struct SecretStore {
    let service: String
    private let accountKey = "account"

    func read() -> String? {
        #if canImport(Security)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: accountKey,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
        #else
        return nil
        #endif
    }

    func write(_ value: String) {
        #if canImport(Security)
        delete()
        let attributes: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: accountKey,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecValueData as String: Data(value.utf8),
        ]
        SecItemAdd(attributes as CFDictionary, nil)
        #endif
    }

    func delete() {
        #if canImport(Security)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: accountKey,
        ]
        SecItemDelete(query as CFDictionary)
        #endif
    }
}
