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

    var isSignedIn: Bool {
        if case .signedIn = account { return true }
        return false
    }
    private(set) var desktopTabs: [ClientRemoteTabs] = []
    private(set) var spaces: ZenSpacesSnapshot?
    private(set) var isSyncing = false
    private(set) var lastSyncError: String?
    /// The account's other devices that can receive tabs (Send to device).
    private(set) var sendTabDevices: [Device] = []

    /// The app's one model: the UI and background checks share it.
    static let shared = AppModel(dataDirectory: RootContent.dataDirectory(), deviceName: "Zen Mobile")

    /// A tab another device sent here.
    struct ReceivedTab: Codable {
        let url: URL
        let title: String
        /// The sending device's name, when known.
        let sender: String?
    }

    /// Called with tabs other devices sent here, and with the addresses of
    /// tabs another device asked to close here.
    @ObservationIgnored var onTabsReceived: (([ReceivedTab]) -> Void)?
    @ObservationIgnored var onTabsClosed: (([URL]) -> Void)?

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
        await prepareAccount()
        if case .signedIn = account {
            await sync(reason: .startup)
        }
    }

    /// Restores the account's state once, for the UI or a background check,
    /// whichever comes first.
    @ObservationIgnored private var preparing: Task<Void, Never>?

    private func prepareAccount() async {
        if let preparing {
            await preparing.value
            return
        }
        let device = zenDeviceConfig(name: deviceName)
        let task = Task {
            let state = await run { try $0.processEvent(event: .initialize(deviceConfig: device)) }
            await apply(state)
        }
        preparing = task
        await task.value
    }

    /// A check from the background (iOS background refresh, an Android
    /// job): the tabs other devices sent since the last look. No full sync.
    func checkForSentTabs() async -> [ReceivedTab] {
        await prepareAccount()
        guard case .signedIn = account else { return [] }
        return await pollDeviceCommands()
    }

    /// While the app is in the foreground, look for sent tabs every minute
    /// (there's no push: see ADR 0008).
    @ObservationIgnored private var foregroundChecks: Task<Void, Never>?

    func setInForeground(_ inForeground: Bool) {
        foregroundChecks?.cancel()
        foregroundChecks = nil
        guard inForeground else { return }
        foregroundChecks = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                guard let model = self, !Task.isCancelled else { return }
                if case .signedIn = model.account, !model.isSyncing {
                    await model.pollDeviceCommands()
                }
            }
        }
    }

    /// When the app comes back to the foreground: fetch what other devices
    /// sent (there's no push yet, so this and sync are when it arrives).
    func didBecomeActive() async {
        guard case .signedIn = account else { return }
        await sync(reason: .scheduled)
    }

    // MARK: Send tab

    func refreshDevices() async {
        guard case .signedIn = account else {
            sendTabDevices = []
            return
        }
        let fxa = self.fxa
        let devices = await Task.detached { (try? fxa.getDevices(ignoreCache: false)) ?? [] }.value
        sendTabDevices = devices
            .filter { !$0.isCurrentDevice && $0.capabilities.contains(.sendTab) }
            .sorted { ($0.lastAccessTime ?? 0) > ($1.lastAccessTime ?? 0) }
    }

    /// Sends a tab to another device; returns whether it went.
    func sendTab(_ url: URL, title: String, to device: Device) async -> Bool {
        let fxa = self.fxa
        let address = url.absoluteString
        let deviceId = device.id
        return await Task.detached {
            do {
                try fxa.sendSingleTab(targetDeviceId: deviceId, title: title, url: address, isPrivate: false)
                return true
            } catch {
                logger.error("Sending a tab failed: \(error)")
                return false
            }
        }.value
    }

    /// Asks another device to close one of its tabs, then syncs so the
    /// desktop tabs list catches up.
    func closeRemoteTab(_ url: String, onDeviceNamed name: String, id: String) async -> Bool {
        // Remote tabs are listed under their FxA device id; fall back to the
        // name for clients that list them under another id.
        guard let device = sendTabDevices.first(where: { $0.id == id }) ?? sendTabDevices.first(where: { $0.displayName == name }),
              device.capabilities.contains(.closeTabs) else {
            return false
        }
        let fxa = self.fxa
        let deviceId = device.id
        let closed = await Task.detached {
            do {
                if case .ok = try fxa.closeTabs(targetDeviceId: deviceId, urls: [url]) {
                    return true
                }
            } catch {
                logger.error("Closing a remote tab failed: \(error)")
            }
            return false
        }.value
        if closed {
            await sync(reason: .user)
        }
        return closed
    }

    /// Tabs other devices sent here, and tabs they asked to close here.
    /// Received tabs go to the browser, or wait in the inbox for it when
    /// it isn't running (a background check).
    @discardableResult
    private func pollDeviceCommands() async -> [ReceivedTab] {
        let fxa = self.fxa
        let commands = await Task.detached { (try? fxa.pollDeviceCommands()) ?? [] }.value
        var received: [ReceivedTab] = []
        var closed: [URL] = []
        for command in commands {
            switch command {
            case let .tabReceived(sender, payload):
                if let entry = payload.entries.last, let url = URL(string: entry.url) {
                    received.append(ReceivedTab(url: url, title: entry.title, sender: sender?.displayName))
                }
            case let .tabsClosed(_, payload):
                closed += payload.urls.compactMap { URL(string: $0) }
            }
        }
        if !received.isEmpty {
            if let onTabsReceived {
                onTabsReceived(received)
            } else {
                SentTabsInbox.append(received)
            }
        }
        if !closed.isEmpty {
            onTabsClosed?(closed)
        }
        return received
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
        if case .signedIn = account {
            await pollDeviceCommands()
            await refreshDevices()
        }
    }

    private func reloadLocalData() {
        desktopTabs = tabsStore.getAll()
            .filter { !$0.remoteTabs.isEmpty }
            .sorted { $0.lastModified > $1.lastModified }
        spaces = try? spacesStore.snapshot()
    }
}

/// Tabs that arrived while the browser wasn't running (a background
/// check), kept for it to open at its next start.
enum SentTabsInbox {
    private static var file: URL {
        RootContent.dataDirectory().appendingPathComponent("received-tabs.json")
    }

    static func append(_ tabs: [AppModel.ReceivedTab]) {
        let all = read() + tabs
        do {
            try JSONEncoder().encode(all).write(to: file, options: .atomic)
        } catch {
            logger.error("Keeping received tabs failed: \(error)")
        }
    }

    /// The waiting tabs, emptying the inbox.
    static func take() -> [AppModel.ReceivedTab] {
        let all = read()
        try? FileManager.default.removeItem(at: file)
        return all
    }

    private static func read() -> [AppModel.ReceivedTab] {
        guard let data = try? Data(contentsOf: file) else { return [] }
        return (try? JSONDecoder().decode([AppModel.ReceivedTab].self, from: data)) ?? []
    }
}
