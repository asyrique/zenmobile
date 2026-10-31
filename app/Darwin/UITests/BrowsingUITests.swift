import XCTest

/// End-to-end: launch the real app, open a page in WKWebView through the
/// address bar, go to a second page in the same tab and back, check the
/// page's title reaches our tab switcher, follow a link that opens a new
/// window (it becomes a tab), open a private tab, then relaunch and check
/// the tabs were restored, except the private one. Mirrors app/Android/app/src/androidTest/.../BrowsingTest.kt
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
    private let secondTitle = "Zen E2E second"

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

    /// Finds a tab card's text, scrolling the tab switcher's row if needed
    /// (its cards are created as they scroll into view).
    @discardableResult
    private func findInTabs(_ text: String) -> XCUIElement {
        let label = app.staticTexts[text]
        for _ in 0..<4 where !label.waitForExistence(timeout: 3) {
            app.scrollViews.firstMatch.swipeLeft()
        }
        return waitFor(label, timeout: 10)
    }

    @discardableResult
    private func waitFor(_ element: XCUIElement, timeout: TimeInterval = 30) -> XCUIElement {
        XCTAssertTrue(element.waitForExistence(timeout: timeout), "Timed out waiting for \(element)")
        return element
    }

    func testBrowseToAPage() {
        // Lets debug builds skip the passcode prompt in front of saved
        // passwords, which a test can't answer.
        app.launchEnvironment["ZEN_UI_TEST"] = "1"
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

        // A JavaScript confirm() shows our dialog; OK reaches the page.
        waitFor(app.webViews.buttons["Ask to confirm"]).tap()
        waitFor(element("promptMessage"))
        screenshot("confirm-dialog")
        element("promptOK").tap()
        waitFor(app.webViews.staticTexts["Confirmed"], timeout: 30)

        // Bookmark the page from the page menu.
        waitFor(element("pageMenu")).tap()
        waitFor(app.buttons["Add bookmark"]).tap()

        // A download lands in Downloads (tab switcher → Library → Downloads),
        // and the bookmark in Mobile Bookmarks (Library → Bookmarks).
        waitFor(app.webViews.links["Download a file"]).tap()
        element("tabsButton").tap()
        waitFor(element("libraryButton")).tap()
        waitFor(element("downloadsButton")).tap()
        let download = waitFor(app.staticTexts.matching(identifier: "downloadName").firstMatch, timeout: 60)
        XCTAssertEqual(download.label, "zen-e2e.bin")
        screenshot("downloads")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        waitFor(element("bookmarksButton")).tap()
        waitFor(app.buttons["Mobile Bookmarks"]).tap()
        let bookmark = waitFor(app.staticTexts.matching(identifier: "bookmarkTitle").firstMatch)
        XCTAssertEqual(bookmark.label, title)
        screenshot("bookmarks")
        app.swipeDown(velocity: .fast)

        // Find in page (WebKit only says whether there's a match).
        waitFor(element("pageMenu")).tap()
        waitFor(app.buttons["Find in page"]).tap()
        let findField = waitFor(app.textFields["findField"])
        findField.tap()
        findField.typeText("Zen")
        XCTAssertEqual(waitFor(element("findStatus")).label, "Found")
        screenshot("find")
        element("findDone").tap()


        // Somewhere else in the same tab, through its address, then back.
        // The address bar starts with the page's address; clear it first.
        element("addressPill").tap()
        waitFor(element("addressClear")).tap()
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
        element("tabsDone").tap()

        // A link that opens a new window opens a new tab.
        waitFor(app.webViews.links["Open in a new tab"]).tap()
        waitFor(app.webViews.staticTexts[secondHeading], timeout: 60)
        element("tabsButton").tap()
        waitFor(app.staticTexts[secondTitle], timeout: 30)
        screenshot("new-window-tab")
        element("tabsDone").tap()

        // A private tab: marked in the tab switcher, not kept after a restart.
        waitFor(element("newTabButton")).tap()
        let privateToggle = waitFor(app.switches["privateToggle"])
        privateToggle.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
        let privateField = waitFor(app.textFields["addressField"])
        privateField.tap()
        privateField.typeText(url)
        element("addressGo").tap()
        waitFor(app.webViews.staticTexts[heading], timeout: 60)
        element("tabsButton").tap()
        findInTabs("Private")
        screenshot("private-tab")
        element("tabsDone").tap()

        // History suggests the page in a new tab's address bar.
        waitFor(element("newTabButton")).tap()
        let suggestField = waitFor(app.textFields["addressField"])
        suggestField.tap()
        suggestField.typeText("Zen")
        let suggestion = waitFor(app.buttons.matching(identifier: "suggestion").firstMatch, timeout: 30)
        screenshot("suggestions")
        suggestion.tap()
        waitFor(app.webViews.staticTexts[heading], timeout: 60)

        // A sign-in offers to save the password; it's listed in Settings →
        // Passwords and fills the form next time.
        element("addressPill").tap()
        waitFor(element("addressClear")).tap()
        let loginField = waitFor(app.textFields["addressField"])
        loginField.tap()
        loginField.typeText(url + "login.html")
        element("addressGo").tap()
        let username = waitFor(app.webViews.textFields["Username"], timeout: 60)
        username.tap()
        username.typeText("zen-tester")
        let password = waitFor(app.webViews.secureTextFields["Password"])
        password.tap()
        password.typeText("hunter2")
        app.webViews.buttons["Sign in"].tap()
        XCTAssertTrue(waitFor(element("promptMessage")).label.contains("zen-tester"))
        screenshot("save-password")
        element("promptOK").tap()
        waitFor(app.webViews.staticTexts[secondHeading], timeout: 60)
        element("tabsButton").tap()
        waitFor(element("settingsButton")).tap()
        waitFor(element("passwordsButton")).tap()
        waitFor(app.buttons.matching(identifier: "savedLogin").firstMatch).tap()
        XCTAssertEqual(waitFor(element("savedUsername")).label, "zen-tester")
        waitFor(element("showPassword")).tap()
        XCTAssertEqual(element("savedPassword").label, "hunter2")
        screenshot("saved-password")
        for _ in 0..<3 {
            app.navigationBars.buttons.element(boundBy: 0).tap()
        }
        waitFor(element("tabsDone")).tap()

        // The form fills when loaded afresh (going back could restore the typed values).
        element("addressPill").tap()
        waitFor(element("addressClear")).tap()
        let againField = waitFor(app.textFields["addressField"])
        againField.tap()
        againField.typeText(url + "login.html")
        element("addressGo").tap()
        let filled = NSPredicate(format: "value == %@", "zen-tester")
        let refilled = app.webViews.textFields["Username"]
        expectation(for: filled, evaluatedWith: refilled)
        waitForExpectations(timeout: 30)
        screenshot("filled-password")

        waitFor(element("spacesButton")).tap()
        waitFor(element("spacesEmptyState"))
        screenshot("spaces")

        // Tabs survive a restart; the private one doesn't.
        app.terminate()
        app.launch()
        waitFor(element("tabsButton"), timeout: 120).tap()
        waitFor(app.staticTexts[title], timeout: 30)
        waitFor(app.staticTexts[secondTitle])
        XCTAssertFalse(app.staticTexts["Private"].exists, "The private tab was restored")
        screenshot("restored")
    }
}
