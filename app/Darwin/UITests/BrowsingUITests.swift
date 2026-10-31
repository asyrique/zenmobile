import XCTest

/// End-to-end: launch the real app, open a page in WKWebView through the
/// address bar, go to a second page in the same tab and back, check the
/// page's title reaches our tab switcher, then relaunch and check the tab
/// was restored. Mirrors app/Android/app/src/androidTest/.../BrowsingTest.kt
/// (which can't relaunch the app it runs in).
///
/// Screenshots of each step are attached to the result bundle and, when
/// ZEN_SCREENSHOT_DIR is set (pass TEST_RUNNER_ZEN_SCREENSHOT_DIR to
/// xcodebuild), written there as PNGs too.
final class BrowsingUITests: XCTestCase {
    private let app = XCUIApplication()
    private var step = 0
    private var environment: [String: String] { ProcessInfo.processInfo.environment }
    // Defaults match the page CI serves from scripts/ci/e2e-site.
    private var url: String { environment["ZEN_E2E_URL"] ?? "http://127.0.0.1:8765/" }
    private var title: String { environment["ZEN_E2E_TITLE"] ?? "Zen E2E" }
    private var heading: String { environment["ZEN_E2E_HEADING"] ?? "Hello from Zen" }
    private let secondHeading = "Second page"

    override func setUp() {
        continueAfterFailure = false
    }

    override func tearDown() {
        // hasSucceeded is still false here (the run isn't finished); count failures.
        if (testRun?.failureCount ?? 0) > 0 {
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
        waitFor(app.webViews.staticTexts[heading], timeout: 60)
        // WebKit exposes the text before it has painted the page.
        Thread.sleep(forTimeInterval: 2)
        screenshot("page")

        // Somewhere else in the same tab, through its address, then back.
        element("addressPill").tap()
        let tabField = waitFor(app.textFields["addressField"])
        tabField.tap()
        tabField.typeText(url + "second.html")
        element("addressGo").tap()
        waitFor(app.webViews.staticTexts[secondHeading], timeout: 60)
        Thread.sleep(forTimeInterval: 2)
        screenshot("second-page")
        waitFor(element("backButton")).tap()
        waitFor(app.webViews.staticTexts[heading], timeout: 60)
        Thread.sleep(forTimeInterval: 2)
        screenshot("back")

        // The title travels WKWebView → KVO → page → tab card.
        element("tabsButton").tap()
        waitFor(app.staticTexts[title], timeout: 30)
        screenshot("tab-switcher")

        app.swipeDown(velocity: .fast)
        waitFor(element("spacesButton")).tap()
        waitFor(element("spacesEmptyState"))
        screenshot("spaces")

        // Tabs survive a restart.
        app.terminate()
        app.launch()
        waitFor(element("tabsButton"), timeout: 120).tap()
        waitFor(app.staticTexts[title], timeout: 30)
        screenshot("restored")
    }
}
