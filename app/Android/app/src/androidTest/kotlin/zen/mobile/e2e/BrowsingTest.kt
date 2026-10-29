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
 * address bar, and check the page's title reaches our tab switcher.
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
    private val screenshots = File(context.getExternalFilesDir(null), "screenshots").apply { mkdirs() }
    private var step = 0

    @get:Rule
    val onFailure = object : TestWatcher() {
        override fun failed(e: Throwable?, description: Description?) {
            screenshot("failure")
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
        val field = waitFor(By.res("addressField"))
        field.click()
        field.text = url
        screenshot("address-bar")
        waitFor(By.res("addressGo")).click()

        waitFor(By.res("webContent"))
        device.wait(Until.gone(By.res("addressField")), 10_000)
        // Let Gecko lay out and paint before the screenshot.
        Thread.sleep(10_000)
        screenshot("page")

        // The title travels GeckoView → Kotlin delegate → Swift model → tab card.
        waitFor(By.res("tabsButton")).click()
        waitFor(By.text(title), 60_000)
        screenshot("tab-switcher")

        device.pressBack()
        waitFor(By.res("spacesButton")).click()
        waitFor(By.res("spacesEmptyState"))
        screenshot("spaces")
    }
}
