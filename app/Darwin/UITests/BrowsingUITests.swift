import XCTest

/// End-to-end: launch the real app, open a page in WKWebView through the
/// address bar, and check the page's title reaches our tab switcher.
/// Mirrors app/Android/app/src/androidTest/.../BrowsingTest.kt.
///
/// Screenshots of each step are attached to the result bundle and, when
/// ZEN_SCREENSHOT_DIR is set (pass TEST_RUNNER_ZEN_SCREENSHOT_DIR to
/// xcodebuild), written there as PNGs too.
final class BrowsingUITests: XCTestCase {
    private let app = XCUIApplication()
    private var step = 0
    private var environment: [String: String] { ProcessInfo.processInfo.environment }
    private var url: String { environment["ZEN_E2E_URL"] ?? "https://example.com" }
    private var title: String { environment["ZEN_E2E_TITLE"] ?? "Example Domain" }

    override func setUp() {
        continueAfterFailure = false
    }

    override func tearDown() {
        if testRun?.hasSucceeded == false {
            screenshot("failure")
        }
    }

    private func screenshot(_ name: String) {
        step += 1
        let shot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: shot)
        attachment.name = String(format: "%02d-%@", step, name)
        attachment.lifetime = .keepAlways
        add(attachment)
        if let dir = environment["ZEN_SCREENSHOT_DIR"] {
            let folder = URL(fileURLWithPath: dir, isDirectory: true)
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try? shot.pngRepresentation.write(to: folder.appendingPathComponent("\(attachment.name!).png"))
        }
    }

    private func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier].firstMatch
    }

    @discardableResult
    private func waitFor(_ element: XCUIElement, timeout: TimeInterval = 30) -> XCUIElement {
        XCTAssertTrue(element.waitForExistence(timeout: timeout), "Timed out waiting for \(element)")
        return element
    }

    func testBrowseToAPage() {
        app.launch()

        waitFor(element("newTabButton"), timeout: 120)
        screenshot("start")

        element("newTabButton").tap()
        let field = waitFor(app.textFields["addressField"])
        field.tap()
        field.typeText(url)
        screenshot("address-bar")
        element("addressGo").tap()

        // WebKit exposes page content to accessibility: check it rendered.
        waitFor(app.webViews.staticTexts[title], timeout: 60)
        screenshot("page")

        // The title travels WKWebView → navigation delegate → model → tab card.
        element("tabsButton").tap()
        waitFor(app.staticTexts[title], timeout: 30)
        screenshot("tab-switcher")

        app.swipeDown(velocity: .fast)
        waitFor(element("spacesButton")).tap()
        waitFor(element("spacesEmptyState"))
        screenshot("spaces")
    }
}
