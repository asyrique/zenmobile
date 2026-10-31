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
