package zen.mobile.e2e

import android.app.Activity
import android.content.Intent
import android.os.Bundle
import android.text.InputType
import android.view.View
import android.view.ViewStructure
import android.widget.EditText
import android.widget.LinearLayout
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import androidx.test.uiautomator.By
import androidx.test.uiautomator.BySelector
import androidx.test.uiautomator.StaleObjectException
import androidx.test.uiautomator.UiDevice
import androidx.test.uiautomator.UiObject2
import androidx.test.uiautomator.Until
import java.io.File
import org.junit.Test
import org.junit.runner.RunWith
import zen.mobile.AutofillLogins

/**
 * Zen as Android's AutoFill service: another browser's sign-in form (a
 * stand-in activity reporting a web domain, as a browser's web view does)
 * gets a saved password after unlocking. Redroid has no screen lock, so
 * unlocking passes straight through.
 */
@RunWith(AndroidJUnit4::class)
class AutofillTest {
    private val instrumentation = InstrumentationRegistry.getInstrumentation()
    private val device = UiDevice.getInstance(instrumentation)
    private val context = instrumentation.targetContext
    private val screenshots = File(context.getExternalFilesDir(null), "screenshots").apply { mkdirs() }

    @Test
    fun fillsAnotherBrowsersSignInForm() {
        device.executeShellCommand("settings put secure autofill_service ${context.packageName}/zen.mobile.ZenAutofillService")
        instrumentation.runOnMainSync {
            AutofillLogins.save("https://${AutofillTestActivity.DOMAIN}", "zen-autofill", "autofill-secret")
        }
        instrumentation.context.startActivity(
            Intent(instrumentation.context, AutofillTestActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))

        try {
            waitFor(By.desc("testUsername"), 30_000).click()
            // AutoFill offers Zen's saved passwords; unlocking lists them.
            tap(By.text("Zen: 1 saved password"))
            tap(By.text("zen-autofill"))
            waitFor(By.desc("testUsername").text("zen-autofill"), 30_000)
            device.takeScreenshot(File(screenshots, "90-autofill.png"))
        } catch (e: Throwable) {
            device.takeScreenshot(File(screenshots, "91-autofill-failure.png"))
            File(screenshots, "autofill-hierarchy.xml").outputStream().use { device.dumpWindowHierarchy(it) }
            throw e
        } finally {
            device.executeShellCommand("settings delete secure autofill_service")
        }
    }

    private fun waitFor(selector: BySelector, timeoutMs: Long = 30_000): UiObject2 =
        device.wait(Until.findObject(selector), timeoutMs)
            ?: throw AssertionError("Timed out after ${timeoutMs}ms waiting for $selector")

    private fun tap(selector: BySelector) {
        repeat(3) {
            try {
                waitFor(selector).click()
                return
            } catch (e: StaleObjectException) {
                device.waitForIdle()
            }
        }
        waitFor(selector).click()
    }
}

/** A sign-in form on "autofill.example", as another browser would show it. */
class AutofillTestActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val form = object : LinearLayout(this) {
            override fun onProvideAutofillStructure(structure: ViewStructure, flags: Int) {
                super.onProvideAutofillStructure(structure, flags)
                structure.setWebDomain(DOMAIN)
            }
        }
        form.orientation = LinearLayout.VERTICAL
        form.setPadding(48, 200, 48, 48)
        form.addView(EditText(this).apply {
            hint = "Username"
            contentDescription = "testUsername"
            setAutofillHints(View.AUTOFILL_HINT_USERNAME)
            importantForAutofill = View.IMPORTANT_FOR_AUTOFILL_YES
        })
        form.addView(EditText(this).apply {
            hint = "Password"
            contentDescription = "testPassword"
            inputType = InputType.TYPE_CLASS_TEXT or InputType.TYPE_TEXT_VARIATION_PASSWORD
            setAutofillHints(View.AUTOFILL_HINT_PASSWORD)
            importantForAutofill = View.IMPORTANT_FOR_AUTOFILL_YES
        })
        setContentView(form)
    }

    companion object {
        const val DOMAIN = "autofill.example"
    }
}
