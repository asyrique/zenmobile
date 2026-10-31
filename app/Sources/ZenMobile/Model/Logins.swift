import Foundation
import Observation
// Skip Fuse bridges @Observable to Compose only in files that import it.
import SkipFuse
import SkipKeychain
import ZenCore

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

    init(path: String) {
        let (store, failure) = Self.open(path: path)
        self.store = store
        unavailableReason = failure
        // Kept alive by `self`: sync finds the store through a weak reference.
        store?.registerWithSyncManager()
    }

    private static func open(path: String) -> (LoginStore?, String?) {
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
