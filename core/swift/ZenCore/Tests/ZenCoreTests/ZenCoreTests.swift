// Smoke tests for the Swift ↔ Rust boundary: these run the generated
// bindings against a real libzen_core, on whatever platform builds them.
import Foundation
import XCTest
import ZenCore

final class ZenCoreTests: XCTestCase {
    override class func setUp() {
        zenInitialize()
    }

    private func tempPath(_ name: String) -> String {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("zencore-\(UUID().uuidString)-\(name)")
            .path
    }

    func testAccountConfig() {
        let config = zenFxaConfig()
        XCTAssertEqual(config.clientId, "a2270f727f45f648")
        XCTAssertEqual(config.server, .release)
        XCTAssertTrue(zenSyncScopes().contains("https://identity.mozilla.com/apps/oldsync"))
        XCTAssertEqual(zenDeviceConfig(name: "Phone").deviceType, .mobile)
    }

    func testOAuthRedirectParsing() {
        let redirect = zenParseOauthRedirect(
            url: zenFxaConfig().redirectUri + "?code=abc&state=xyz")
        XCTAssertEqual(redirect, OAuthRedirect(code: "abc", state: "xyz"))
        XCTAssertNil(zenParseOauthRedirect(url: "https://example.com/?code=abc&state=xyz"))
    }

    func testEmptySpacesStore() throws {
        let store = try ZenSpacesStore(path: tempPath("spaces.db"))
        let snapshot = try store.snapshot()
        XCTAssertTrue(snapshot.spaces.isEmpty)
        XCTAssertTrue(snapshot.essentials.isEmpty)
        XCTAssertNil(snapshot.lastSyncMillis)
    }

    func testSyncNeedsASignedInAccount() throws {
        let manager = ZenSyncManager(
            tabs: TabsStore(path: tempPath("tabs.db")),
            spaces: try ZenSpacesStore(path: tempPath("spaces.db")))
        let account = FirefoxAccount(config: zenFxaConfig())
        let params = ZenSyncParams(reason: .user, persistedState: nil, deviceName: "Phone")
        XCTAssertThrowsError(try manager.sync(account: account, params: params)) { error in
            guard case ZenSyncError.AccountNotReady = error else {
                return XCTFail("unexpected error \(error)")
            }
        }
    }

    func testPlacesHistoryAndBookmarks() throws {
        let api = try placesApiNew(dbPath: tempPath("places.db"))
        let places = try api.newConnection(connType: .readWrite)
        let url = "https://zen-browser.app/"
        try places.applyObservation(visit: VisitObservation(url: url, title: "Zen Browser", visitType: .link))
        XCTAssertEqual(try places.queryAutocomplete(search: "zen", limit: 5).first?.url, url)
        XCTAssertEqual(try places.getVisitPage(offset: 0, count: 10, excludeTypes: 0).first?.title, "Zen Browser")
        _ = try places.bookmarksInsert(bookmark: .bookmark(b: InsertableBookmark(
            parentGuid: "mobile______", position: .append, url: url, title: "Zen")))
        XCTAssertEqual(try places.bookmarksGetAllWithUrl(url: url).count, 1)
    }

    func testLoginsStore() throws {
        let key = try createKey()
        let store = try LoginStore(
            path: tempPath("logins.db"),
            encdec: createManagedEncdec(keyManager: createStaticKeyManager(key: key)))
        let entry = LoginEntry(
            origin: "https://zen-browser.app", httpRealm: nil, formActionOrigin: "https://zen-browser.app",
            usernameField: "user", passwordField: "pass", password: "hunter2", username: "zen")
        let login = try store.add(login: entry)
        let candidates = try store.listCandidatesByOrigin(origins: ["https://zen-browser.app"], domains: [])
        XCTAssertEqual(candidates.map(\.id), [login.id])
        XCTAssertEqual(try store.getMany(ids: [login.id]).first?.password, "hunter2")
        XCTAssertEqual(try store.findLoginToUpdate(look: entry)?.id, login.id)
    }

    func testAccountStateMachineStartsDisconnected() throws {
        let account = FirefoxAccount(config: zenFxaConfig())
        let state = try account.processEvent(
            event: .initialize(deviceConfig: zenDeviceConfig(name: "Phone")))
        XCTAssertEqual(state, .disconnected)
    }

    /// Talks to accounts.firefox.com. Opt in with ZEN_NETWORK_TESTS=1.
    func testBeginOAuthFlowProducesSignInURL() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["ZEN_NETWORK_TESTS"] == "1")
        let account = FirefoxAccount(config: zenFxaConfig())
        _ = try account.processEvent(
            event: .initialize(deviceConfig: zenDeviceConfig(name: "Phone")))
        let state = try account.processEvent(
            event: .beginOAuthFlow(service: "sync", scopes: zenSyncScopes(), entrypoint: "zenmobile"))
        guard case let .authenticating(oauthUrl, _) = state else {
            return XCTFail("unexpected state \(state)")
        }
        let url = try XCTUnwrap(URLComponents(string: oauthUrl))
        XCTAssertEqual(url.host, "accounts.firefox.com")
        let query = Dictionary(uniqueKeysWithValues: (url.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        XCTAssertEqual(query["client_id"], "a2270f727f45f648")
        XCTAssertEqual(query["redirect_uri"], zenFxaConfig().redirectUri)
        XCTAssertNotNil(query["keys_jwk"], "sync needs scoped keys")
    }
}
