package zen.mobile.e2e

import android.content.Intent
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import androidx.test.uiautomator.By
import androidx.test.uiautomator.BySelector
import androidx.test.uiautomator.UiDevice
import androidx.test.uiautomator.UiObject2
import androidx.test.uiautomator.Until
import java.io.File
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
        waitFor(By.text("Private"), 30_000)
        screenshot("private-tab")
        device.pressBack()

        waitFor(By.res("spacesButton")).click()
        waitFor(By.res("spacesEmptyState"))
        screenshot("spaces")
    }
}
