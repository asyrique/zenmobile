package zen.mobile.e2e

import android.content.Intent
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import androidx.test.uiautomator.By
import androidx.test.uiautomator.BySelector
import androidx.test.uiautomator.Direction
import androidx.test.uiautomator.StaleObjectException
import androidx.test.uiautomator.UiDevice
import androidx.test.uiautomator.UiObject2
import androidx.test.uiautomator.Until
import java.io.File
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TestWatcher
import org.junit.runner.Description
import org.junit.runner.RunWith

/**
 * End-to-end: launch the real app, open a page in GeckoView through the
 * address bar, go to a second page in the same tab and back, check the page
 * titles reach our tab switcher, follow a link that opens a new window (it
 * becomes a tab) and open a private tab. (Unlike the iOS test, it can't check
 * tabs survive a restart: the test runs inside the app's process.)
 *
 * Driven from outside the app with UiAutomator, using the SwiftUI
 * accessibilityIdentifiers (Skip exposes them as resource ids). Screenshots
 * of each step land in the app's external files dir, under screenshots/,
 * for CI to pull.
 *
 * Arguments (am instrument -e): url and title (the page title to expect).
 * CI serves scripts/ci/e2e-site and passes its address.
 */
@RunWith(AndroidJUnit4::class)
class BrowsingTest {
    private val instrumentation = InstrumentationRegistry.getInstrumentation()
    private val device = UiDevice.getInstance(instrumentation)
    private val context = instrumentation.targetContext
    private val args = InstrumentationRegistry.getArguments()
    private val url = args.getString("url") ?: "http://127.0.0.1:8765/"
    private val title = args.getString("title") ?: "Zen E2E"
    private val secondTitle = "Zen E2E second"
    private val screenshots = File(context.getExternalFilesDir(null), "screenshots").apply { mkdirs() }
    private var step = 0

    @get:Rule
    val onFailure = object : TestWatcher() {
        override fun failed(e: Throwable?, description: Description?) {
            screenshot("failure")
            // What was on screen, for working out why a selector never matched.
            device.dumpWindowHierarchy(File(screenshots, "failure-hierarchy.xml"))
        }
    }

    private fun screenshot(name: String) {
        step += 1
        device.waitForIdle()
        device.takeScreenshot(File(screenshots, "%02d-%s.png".format(step, name)))
    }

    /** Finds a tab card's text, scrolling the tab switcher's row if needed. */
    private fun findInTabs(text: String): UiObject2 {
        repeat(4) {
            device.wait(Until.findObject(By.text(text)), 3_000)?.let { return it }
            device.findObject(By.scrollable(true))?.scroll(Direction.RIGHT, 1f)
        }
        return waitFor(By.text(text), 10_000)
    }

    /**
     * Taps what [selector] finds, finding it again if the screen re-renders
     * in between (lists that fill in asynchronously replace their rows).
     */
    private fun tap(selector: BySelector, timeoutMs: Long = 30_000) {
        repeat(3) {
            try {
                waitFor(selector, timeoutMs).click()
                return
            } catch (e: StaleObjectException) {
                device.waitForIdle()
            }
        }
        waitFor(selector, timeoutMs).click()
    }

    /** The first of [selectors] to appear; on failure, saves the screen's hierarchy. */
    private fun findAny(vararg selectors: BySelector, timeoutMs: Long = 30_000): UiObject2 {
        val deadline = System.currentTimeMillis() + timeoutMs
        while (System.currentTimeMillis() < deadline) {
            for (selector in selectors) {
                device.findObject(selector)?.let { return it }
            }
            Thread.sleep(500)
        }
        // Saved with the screenshots, which CI uploads.
        File(screenshots, "hierarchy.xml").outputStream().use { device.dumpWindowHierarchy(it) }
        throw AssertionError("Timed out after ${timeoutMs}ms waiting for any of ${selectors.toList()}")
    }

    private fun waitFor(selector: BySelector, timeoutMs: Long = 30_000): UiObject2 =
        device.wait(Until.findObject(selector), timeoutMs)
            ?: throw AssertionError("Timed out after ${timeoutMs}ms waiting for $selector")

    @Test
    fun browseToAPage() {
        val launch = context.packageManager.getLaunchIntentForPackage(context.packageName)!!
            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK)
        context.startActivity(launch)

        // First launch initializes NSS, SQLite and the Gecko runtime.
        waitFor(By.res("newTabButton"), 120_000)
        screenshot("start")

        waitFor(By.res("newTabButton")).click()
        waitFor(By.res("addressField")).click()
        // Type with key events, as a person would. UiObject2.setText doesn't
        // reach Compose text fields (their editable node isn't the tagged one).
        device.waitForIdle()
        device.executeShellCommand("input text $url")
        // Go stays disabled until the field has text: proof the typing landed.
        val go = waitFor(By.res("addressGo").enabled(true), 10_000)
        screenshot("address-bar")
        go.click()

        waitFor(By.res("webContent"))
        device.wait(Until.gone(By.res("addressField")), 10_000)
        // Let Gecko lay out and paint before the screenshot.
        Thread.sleep(10_000)
        screenshot("page")

        // A JavaScript confirm() shows our dialog; OK reaches the page.
        waitFor(By.text("Ask to confirm"), 30_000).click()
        waitFor(By.res("promptMessage"), 30_000)
        screenshot("confirm-dialog")
        waitFor(By.res("promptOK")).click()
        waitFor(By.text("Confirmed"), 30_000)

        // A <select> menu opens the app's list; the choice reaches the page.
        // Gecko exposes a collapsed <select> as a combo box (a Spinner) named
        // by its label; its text depends on the version.
        findAny(By.clazz("android.widget.Spinner"), By.desc("Fruit"), By.text("Fruit"), By.text("Apple")).click()
        // The option's text is a child of the button carrying the id.
        waitFor(By.res("promptChoice").hasDescendant(By.text("Banana")), 30_000).click()
        waitFor(By.text("Chose Banana"), 30_000)

        // Bookmark the page from the page menu.
        waitFor(By.res("pageMenu")).click()
        waitFor(By.text("Add bookmark")).click()

        // A download lands in Downloads (tab switcher → Library → Downloads),
        // and the bookmark in Mobile Bookmarks (Library → Bookmarks).
        waitFor(By.text("Download a file"), 30_000).click()
        waitFor(By.res("tabsButton")).click()
        // Let the tab switcher finish sliding up: a navigation tap that lands
        // mid-animation can leave the pushed screen blank (Skip on Android).
        device.waitForIdle()
        Thread.sleep(1_000)
        waitFor(By.res("libraryButton")).click()
        waitFor(By.res("downloadsButton")).click()
        waitFor(By.res("downloadName").text("zen-e2e.bin"), 60_000)
        screenshot("downloads")
        device.pressBack()
        waitFor(By.res("bookmarksButton")).click()
        tap(By.text("Mobile Bookmarks"))
        waitFor(By.res("bookmarkTitle").text(title), 30_000)
        screenshot("bookmarks")
        // Bookmarks folder, Bookmarks, Library, then the tab switcher.
        repeat(4) { device.pressBack() }

        // Find in page: Gecko counts matches; the page has one "Zen".
        waitFor(By.res("pageMenu")).click()
        waitFor(By.text("Find in page")).click()
        waitFor(By.res("findField")).click()
        device.waitForIdle()
        device.executeShellCommand("input text Zen")
        waitFor(By.res("findStatus").text("1 of 1"), 30_000)
        screenshot("find")
        waitFor(By.res("findDone")).click()


        // Somewhere else in the same tab, through its address. The address
        // bar starts with the page's address; clear it first.
        waitFor(By.res("addressPill")).click()
        waitFor(By.res("addressClear")).click()
        waitFor(By.res("addressField")).click()
        device.waitForIdle()
        device.executeShellCommand("input text ${url}second.html")
        waitFor(By.res("addressGo").enabled(true), 10_000).click()
        device.wait(Until.gone(By.res("addressField")), 10_000)
        // Back becomes possible once Gecko reports the new history entry.
        waitFor(By.res("backButton").enabled(true), 60_000)
        Thread.sleep(5_000)
        screenshot("second-page")

        // The title travels GeckoView → Kotlin delegate → Swift page → tab card.
        waitFor(By.res("tabsButton")).click()
        waitFor(By.text(secondTitle), 60_000)
        device.pressBack()

        waitFor(By.res("backButton").enabled(true)).click()
        waitFor(By.res("forwardButton").enabled(true), 60_000)
        Thread.sleep(5_000)
        screenshot("back")
        waitFor(By.res("tabsButton")).click()
        waitFor(By.text(title), 60_000)
        screenshot("tab-switcher")
        device.pressBack()

        // A link that opens a new window opens a new tab. GeckoView exposes
        // the page to accessibility, so UiAutomator can find the link.
        waitFor(By.text("Open in a new tab"), 30_000).click()
        Thread.sleep(5_000)
        waitFor(By.res("tabsButton")).click()
        waitFor(By.text(secondTitle), 60_000)
        screenshot("new-window-tab")
        device.pressBack()

        // A private tab, marked in the tab switcher.
        waitFor(By.res("newTabButton")).click()
        val toggle = waitFor(By.res("privateToggle")).visibleBounds
        device.click(toggle.right - 40, toggle.centerY())
        waitFor(By.res("addressField")).click()
        device.waitForIdle()
        device.executeShellCommand("input text $url")
        waitFor(By.res("addressGo").enabled(true), 10_000).click()
        device.wait(Until.gone(By.res("addressField")), 10_000)
        Thread.sleep(5_000)
        waitFor(By.res("tabsButton")).click()
        findInTabs("Private")
        screenshot("private-tab")
        device.pressBack()

        // History suggests the page in a new tab's address bar.
        waitFor(By.res("newTabButton")).click()
        waitFor(By.res("addressField")).click()
        device.waitForIdle()
        device.executeShellCommand("input text Zen")
        val suggestion = waitFor(By.res("suggestion"), 30_000)
        screenshot("suggestions")
        suggestion.click()
        device.wait(Until.gone(By.res("addressField")), 10_000)
        Thread.sleep(5_000)

        // A sign-in offers to save the password (Gecko's login manager finds
        // the form), and it's listed in Settings → Passwords. Gecko doesn't
        // fill saved passwords into http pages, so filling isn't checked here.
        waitFor(By.res("addressPill")).click()
        waitFor(By.res("addressClear")).click()
        waitFor(By.res("addressField")).click()
        device.waitForIdle()
        device.executeShellCommand("input text ${url}login.html")
        waitFor(By.res("addressGo").enabled(true), 10_000).click()
        device.wait(Until.gone(By.res("addressField")), 10_000)
        waitFor(By.text("Sign in"), 60_000)
        Thread.sleep(3_000)
        val fields = device.wait(Until.findObjects(By.clazz("android.widget.EditText")), 30_000)
        assertTrue("No sign-in fields", fields != null && fields.size >= 2)
        fields!![0].click()
        device.waitForIdle()
        device.executeShellCommand("input text zen-tester")
        fields[1].click()
        device.waitForIdle()
        device.executeShellCommand("input text hunter2")
        device.pressEnter()
        val saveMessage = waitFor(By.res("promptMessage"), 60_000)
        assertTrue(saveMessage.text.contains("zen-tester"))
        screenshot("save-password")
        waitFor(By.res("promptOK")).click()
        Thread.sleep(3_000)
        waitFor(By.res("tabsButton")).click()
        device.waitForIdle()
        Thread.sleep(1_000)
        waitFor(By.res("settingsButton")).click()
        waitFor(By.res("passwordsButton")).click()
        waitFor(By.res("savedLogin"), 30_000).click()
        waitFor(By.res("savedUsername").text("zen-tester"), 30_000)
        waitFor(By.res("showPassword")).click()
        waitFor(By.res("savedPassword").text("hunter2"), 10_000)
        screenshot("saved-password")
        // The saved login, Passwords, Settings, then the tab switcher.
        repeat(4) { device.pressBack() }

        waitFor(By.res("spacesButton")).click()
        waitFor(By.res("spacesEmptyState"))
        screenshot("spaces")
    }
}
