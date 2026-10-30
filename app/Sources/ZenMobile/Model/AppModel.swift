import Foundation
import Observation
import SkipFuse
import SkipKeychain
import ZenCore

/// Owns the Firefox account, the synced stores and the sync loop, and
/// publishes what the UI shows: desktop tabs and Zen Spaces.
///
/// All Rust calls block on I/O, so they run off the main actor.
@MainActor @Observable final class AppModel {
    enum AccountState: Equatable {
        case signedOut
        /// The OAuth page to show in `SignInView`.
        case signingIn(URL)
        case signedIn(email: String?)
        /// Signed in, but the session expired or the password changed.
        case needsReauthentication
    }

    private(set) var account: AccountState = .signedOut
    private(set) var desktopTabs: [ClientRemoteTabs] = []
    private(set) var spaces: ZenSpacesSnapshot?
    private(set) var isSyncing = false
    private(set) var lastSyncError: String?

    private var fxa: FirefoxAccount
    private let tabsStore: TabsStore
    private let spacesStore: ZenSpacesStore
    private let syncManager: ZenSyncManager
    private let deviceName: String

    init(dataDirectory: URL, deviceName: String) {
        zenInitialize()
        self.deviceName = deviceName
        tabsStore = TabsStore(path: dataDirectory.appendingPathComponent("tabs.db").path)
        // A store that can't open (corrupt file) is just a cache: start over.
        let spacesPath = dataDirectory.appendingPathComponent("spaces.db").path
        if let store = try? ZenSpacesStore(path: spacesPath) {
            spacesStore = store
        } else {
            try? FileManager.default.removeItem(atPath: spacesPath)
            spacesStore = try! ZenSpacesStore(path: spacesPath)
        }
        syncManager = ZenSyncManager(tabs: tabsStore, spaces: spacesStore)
        fxa = Self.restoreAccount()
        reloadLocalData()
    }

    // MARK: Saved account

    /// The serialized account (refresh token and sync keys) lives in the
    /// Keychain on iOS and in encrypted preferences on Android, never in
    /// UserDefaults or a plain file.
    private static let accountKey = "io.github.asyrique.zenmobile.fxa.account"

    private static func restoreAccount() -> FirefoxAccount {
        do {
            if let json = try Keychain.shared.string(forKey: accountKey) {
                return try FirefoxAccount.fromJson(data: json)
            }
        } catch {
            logger.error("Restoring the Firefox account failed: \(error)")
        }
        return FirefoxAccount(config: zenFxaConfig())
    }

    private func persistAccount() {
        do {
            try Keychain.shared.set(try fxa.toJson(), forKey: Self.accountKey, access: .firstUnlockThisDeviceOnly)
        } catch {
            logger.error("Saving the Firefox account failed: \(error)")
        }
    }

    private func forgetAccount() {
        do {
            try Keychain.shared.removeValue(forKey: Self.accountKey)
        } catch {
            logger.error("Removing the Firefox account failed: \(error)")
        }
    }

    // MARK: Account

    func start() async {
        let device = zenDeviceConfig(name: deviceName)
        let state = await run { try $0.processEvent(event: .initialize(deviceConfig: device)) }
        await apply(state)
        if case .signedIn = account {
            await sync(reason: .startup)
        }
    }

    func beginSignIn() async {
        let state = await run {
            try $0.processEvent(event: .beginOAuthFlow(
                service: "sync", scopes: zenSyncScopes(), entrypoint: "zenmobile"))
        }
        await apply(state)
    }

    /// Call for every main-frame navigation in the sign-in web view.
    /// Returns true if the navigation was the OAuth redirect and should be cancelled.
    func interceptSignInNavigation(_ url: URL) -> Bool {
        guard let redirect = zenParseOauthRedirect(url: url.absoluteString) else {
            return false
        }
        Task {
            let state = await run {
                try $0.processEvent(event: .completeOAuthFlow(code: redirect.code, state: redirect.state))
            }
            await apply(state)
            if case .signedIn = account {
                await sync(reason: .user)
            }
        }
        return true
    }

    func cancelSignIn() async {
        let state = await run { try $0.processEvent(event: .cancelOAuthFlow) }
        await apply(state)
    }

    func signOut() async {
        let state = await run { try $0.processEvent(event: .disconnect) }
        syncManager.disconnect()
        forgetAccount()
        UserDefaults.standard.removeObject(forKey: Self.syncStateKey)
        await apply(state)
        reloadLocalData()
    }

    private func run(_ body: @escaping @Sendable (FirefoxAccount) throws -> FxaState) async -> FxaState? {
        let fxa = self.fxa
        return await Task.detached {
            do {
                return try body(fxa)
            } catch {
                logger.error("FxA event failed: \(error)")
                return nil
            }
        }.value
    }

    private func apply(_ state: FxaState?) async {
        guard let state else { return }
        switch state {
        case .uninitialized, .disconnected:
            account = .signedOut
        case let .authenticating(oauthUrl, _):
            account = URL(string: oauthUrl).map(AccountState.signingIn) ?? .signedOut
        case .connected:
            let fxa = self.fxa
            let email = await Task.detached { try? fxa.getProfile(ignoreCache: false).email }.value
            account = .signedIn(email: email)
        case .authIssues:
            account = .needsReauthentication
        }
        persistAccount()
    }

    // MARK: Sync

    private static let syncStateKey = "zen.sync.persistedState"

    func sync(reason: ZenSyncReason) async {
        guard case .signedIn = account, !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false }

        let params = ZenSyncParams(
            reason: reason,
            persistedState: UserDefaults.standard.string(forKey: Self.syncStateKey),
            deviceName: deviceName)
        let (fxa, manager) = (self.fxa, syncManager)
        let outcome: Result<ZenSyncResult, Error> = await Task.detached {
            Result { try manager.sync(account: fxa, params: params) }
        }.value

        switch outcome {
        case let .success(result):
            UserDefaults.standard.set(result.persistedState, forKey: Self.syncStateKey)
            lastSyncError = result.status == .ok ? nil : "\(result.status)"
            if result.status == .authError {
                account = .needsReauthentication
            }
        case let .failure(error):
            lastSyncError = "\(error)"
        }
        persistAccount()
        reloadLocalData()
    }

    private func reloadLocalData() {
        desktopTabs = tabsStore.getAll()
            .filter { !$0.remoteTabs.isEmpty }
            .sorted { $0.lastModified > $1.lastModified }
        spaces = try? spacesStore.snapshot()
    }
}
