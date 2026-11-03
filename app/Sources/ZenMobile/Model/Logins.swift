import Foundation
import Observation
// Skip Fuse bridges @Observable to Compose only in files that import it.
import SkipFuse
import SkipKeychain
import ZenCore
#if !os(Android) && canImport(AuthenticationServices)
import AuthenticationServices
import Security
#endif

/// Saved passwords, in application-services' logins database (the one
/// Firefox's apps use). Usernames and passwords are encrypted in it with a
/// key kept in the Keychain (iOS) or encrypted preferences (Android). Once
/// registered with sync, logins sync with Firefox and Zen desktop when
/// signed in.
///
/// The store is thread-safe and its calls block, so they run off the main
/// actor; the engines' form filling calls it from their own threads.
@MainActor @Observable final class Logins {
    /// Every saved login, for the Passwords screen; loaded by `reload()`.
    private(set) var saved: [Login] = []
    /// Why saved passwords can't be used, if the store didn't open.
    let unavailableReason: String?

    nonisolated let store: LoginStore?

    private static let keyName = "io.github.asyrique.zenmobile.logins.key"

    /// The app's one store: the browser and Android's AutoFill service (which
    /// can run without the browser's UI) share it.
    static let shared = Logins(path: databasePath())

    init(path: String) {
        let (store, failure) = Self.open(path: path)
        self.store = store
        unavailableReason = failure
        // Kept alive by `self`: sync finds the store through a weak reference.
        store?.registerWithSyncManager()
        updateAutofillIdentities()
    }

    // MARK: Shared with the iOS AutoFill extension

    /// The App Group and Keychain group the iOS AutoFill extension
    /// (Darwin/CredentialProvider) shares; keep them in step with it.
    static let appGroup = "group.io.github.asyrique.zenmobile"
    private static let sharedKeychainGroup = "io.github.asyrique.zenmobile.shared"
    private static let bundleIdentifier = "io.github.asyrique.zenmobile"

    /// On iOS the database lives in the App Group container, where the
    /// AutoFill extension can read it; one saved before that moves there.
    private static func databasePath() -> String {
        let local = RootContent.dataDirectory().appendingPathComponent("logins.db")
        #if !os(Android) && canImport(AuthenticationServices)
        if let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup) {
            let shared = container.appendingPathComponent("logins.db")
            let files = FileManager.default
            if !files.fileExists(atPath: shared.path), files.fileExists(atPath: local.path) {
                for suffix in ["", "-wal", "-shm"] {
                    try? files.moveItem(atPath: local.path + suffix, toPath: shared.path + suffix)
                }
            }
            return shared.path
        }
        #endif
        return local.path
    }

    /// Moves a logins key saved before the AutoFill extension existed (in
    /// the app's own Keychain group) to the shared group. It's copied
    /// before the old one goes, so a failure leaves it where it was.
    private static func shareKey() {
        #if !os(Android) && canImport(AuthenticationServices)
        let find: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: keyName,
            kSecMatchLimit as String: kSecMatchLimitAll,
            kSecReturnAttributes as String: true,
        ]
        var found: AnyObject?
        guard SecItemCopyMatching(find as CFDictionary, &found) == errSecSuccess,
              let items = found as? [[String: Any]],
              !items.contains(where: { ($0[kSecAttrAccessGroup as String] as? String)?.hasSuffix(sharedKeychainGroup) == true }),
              let item = items.first,
              let group = item[kSecAttrAccessGroup as String] as? String else { return }
        let read: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: keyName,
            kSecAttrAccessGroup as String: group,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecReturnData as String: true,
        ]
        var data: AnyObject?
        guard SecItemCopyMatching(read as CFDictionary, &data) == errSecSuccess, let key = data as? Data else { return }
        // The app's own group is "<team ID>.<bundle ID>"; the shared one
        // has the same prefix.
        let prefix = group.hasSuffix(bundleIdentifier) ? String(group.dropLast(bundleIdentifier.count)) : ""
        let add: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: keyName,
            kSecAttrAccessGroup as String: prefix + sharedKeychainGroup,
            kSecAttrAccessible as String: item[kSecAttrAccessible as String] ?? kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecValueData as String: key,
        ]
        guard SecItemAdd(add as CFDictionary, nil) == errSecSuccess else { return }
        let old: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: keyName,
            kSecAttrAccessGroup as String: group,
        ]
        SecItemDelete(old as CFDictionary)
        #endif
    }

    /// Tells iOS which logins Zen has (site and username, never the
    /// password), so AutoFill can suggest them above the keyboard.
    nonisolated func updateAutofillIdentities() {
        #if !os(Android) && canImport(AuthenticationServices)
        guard let store else { return }
        Task.detached {
            let identityStore = ASCredentialIdentityStore.shared
            guard await identityStore.state().isEnabled else { return }
            let identities = ((try? store.list()) ?? []).compactMap { login -> ASPasswordCredentialIdentity? in
                guard let host = URL(string: login.origin)?.host else { return nil }
                return ASPasswordCredentialIdentity(
                    serviceIdentifier: ASCredentialServiceIdentifier(identifier: host, type: .domain),
                    user: login.username,
                    recordIdentifier: login.id)
            }
            _ = try? await identityStore.replaceCredentialIdentities(with: identities)
        }
        #endif
    }

    private static func open(path: String) -> (LoginStore?, String?) {
        // NSS, which encryption needs; the AutoFill service can get here
        // before anything else has started it.
        zenInitialize()
        shareKey()
        do {
            var isNewKey = false
            let key: String
            // A read error (say, before first unlock) must not replace the
            // key: that would make every saved login unreadable.
            if let stored = try Keychain.shared.string(forKey: keyName) {
                key = stored
            } else {
                key = try createKey()
                try Keychain.shared.set(key, forKey: keyName, access: .firstUnlockThisDeviceOnly)
                isNewKey = true
            }
            let store = try LoginStore(path: path, encdec: createManagedEncdec(keyManager: createStaticKeyManager(key: key)))
            if isNewKey {
                // A no-op for a new database. An existing one was encrypted
                // with a key that's gone (the app was restored from a backup,
                // which leaves this-device-only keys behind): clear it, and
                // sync brings the logins back.
                try store.wipeLocal()
            }
            return (store, nil)
        } catch {
            logger.error("Opening saved passwords failed: \(error)")
            return (nil, "\(error)")
        }
    }

    // MARK: The Passwords screen

    func reload() async {
        let all = await run { try $0.list() } ?? []
        saved = all.sorted { ($0.origin, $0.username) < ($1.origin, $1.username) }
    }

    func delete(_ id: String) async {
        _ = await run { try $0.delete(id: id) }
        updateAutofillIdentities()
        await reload()
    }

    // MARK: Form filling (any thread)

    /// Logins saved for exactly this origin (`https://example.com`), as
    /// Firefox fills them.
    nonisolated func logins(forOrigin origin: String) -> [Login] {
        guard let store else { return [] }
        do {
            let ids = try store.listCandidatesByOrigin(origins: [origin], domains: []).map(\.id)
            return ids.isEmpty ? [] : try store.getMany(ids: ids)
        } catch {
            logger.error("Reading saved passwords failed: \(error)")
            return []
        }
    }

    /// Logins for a site and its subdomains, which Gecko filters itself.
    nonisolated func logins(forBaseDomain domain: String) -> [Login] {
        guard let store else { return [] }
        do {
            return try store.getByBaseDomain(baseDomain: domain)
        } catch {
            logger.error("Reading saved passwords failed: \(error)")
            return []
        }
    }

    /// The saved login a submitted form would update, if any.
    nonisolated func existing(_ entry: LoginEntry) -> Login? {
        try? store?.findLoginToUpdate(look: entry)
    }

    /// Saves a login, or updates the one it matches.
    nonisolated func save(_ entry: LoginEntry) {
        do {
            _ = try store?.addOrUpdate(login: entry)
            updateAutofillIdentities()
        } catch {
            logger.error("Saving a password failed: \(error)")
        }
    }

    /// Records that a saved login was filled.
    nonisolated func used(_ id: String) {
        try? store?.touch(id: id)
    }

    private func run<T: Sendable>(_ body: @escaping @Sendable (LoginStore) throws -> T) async -> T? {
        guard let store else { return nil }
        return await Task.detached {
            do {
                return try body(store)
            } catch {
                logger.error("Saved passwords: \(error)")
                return nil
            }
        }.value
    }
}

#if os(Android)
extension Logins {
    /// A login as GeckoLogins.kt passes it.
    private struct GeckoLogin: Codable {
        var guid: String?
        var origin: String
        var formActionOrigin: String?
        var httpRealm: String?
        var username: String
        var password: String
    }

    /// Hands Gecko's login manager the saved passwords. Gecko calls these
    /// off the main thread, so they're @Sendable (not main-actor isolated).
    static func connectGecko(_ logins: Logins) {
        GeckoLogins.connect(
            fetch: { @Sendable domain in
                let found = logins.logins(forBaseDomain: domain).map {
                    GeckoLogin(guid: $0.id, origin: $0.origin, formActionOrigin: $0.formActionOrigin,
                               httpRealm: $0.httpRealm, username: $0.username, password: $0.password)
                }
                guard let data = try? JSONEncoder().encode(found) else { return "[]" }
                return String(decoding: data, as: UTF8.self)
            },
            save: { @Sendable json in
                guard let login = try? JSONDecoder().decode(GeckoLogin.self, from: Data(json.utf8)) else { return }
                logins.save(LoginEntry(
                    origin: login.origin, httpRealm: login.httpRealm, formActionOrigin: login.formActionOrigin,
                    usernameField: "", passwordField: "", password: login.password, username: login.username))
            },
            used: { @Sendable guid in logins.used(guid) })
    }
}
#endif
