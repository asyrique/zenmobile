// Plain Kotlin, copied into the Android build as is (see GeckoPrompts.kt):
// the Android system services the app uses (screen lock, clipboard, share
// sheet, other apps, full screen).
package zen.mobile

import android.app.Activity
import android.app.KeyguardManager
import android.content.ActivityNotFoundException
import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.content.ContextWrapper
import android.content.Intent
import android.net.Uri
import androidx.compose.runtime.DisposableEffect
import androidx.compose.ui.platform.LocalView
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import androidx.core.view.WindowInsetsControllerCompat
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.ui.platform.LocalContext

/**
 * Asks for the screen lock (PIN, pattern, password or biometrics) whenever
 * [attempt] changes; [done] gets whether the user passed. A device with no
 * screen lock has nothing to ask for, and passes.
 */
@Composable
internal fun DeviceAuthEffect(attempt: Int, done: (Boolean) -> Unit) {
    val context = LocalContext.current
    val confirm = rememberLauncherForActivityResult(ActivityResultContracts.StartActivityForResult()) { result ->
        done(result.resultCode == Activity.RESULT_OK)
    }
    LaunchedEffect(attempt) {
        val keyguard = context.getSystemService(KeyguardManager::class.java)
        @Suppress("DEPRECATION") // Its replacement, BiometricPrompt, needs a FragmentActivity.
        val intent = if (keyguard?.isDeviceSecure == true) {
            keyguard.createConfirmDeviceCredentialIntent("Passwords", "Show your saved passwords")
        } else {
            null
        }
        if (intent == null) done(true) else confirm.launch(intent)
    }
}

internal object Clipboards {
    fun copy(context: Context, text: String) {
        val clipboard = context.getSystemService(ClipboardManager::class.java) ?: return
        clipboard.setPrimaryClip(ClipData.newPlainText("Zen", text))
    }
}

internal object Sharing {
    /** The share sheet, for a link or text. */
    fun share(context: Context, text: String) {
        val send = Intent(Intent.ACTION_SEND).setType("text/plain").putExtra(Intent.EXTRA_TEXT, text)
        context.startActivity(Intent.createChooser(send, null).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
    }
}

/** Links for other apps: tel:, mailto:, sms:, geo:, market:, intent: and the like. */
internal object ExternalApps {
    /**
     * Opens [uri] in the app that handles it. Returns the page to load instead
     * when no app does and the link names one (an intent: link's
     * browser_fallback_url), else null.
     */
    fun open(context: Context, uri: String): String? {
        val intent = try {
            if (uri.startsWith("intent:")) Intent.parseUri(uri, Intent.URI_INTENT_SCHEME) else Intent(Intent.ACTION_VIEW, Uri.parse(uri))
        } catch (e: Exception) {
            return null
        }
        val fallback = intent.getStringExtra("browser_fallback_url")?.takeIf { it.startsWith("https://") || it.startsWith("http://") }
        // Only what a link may open: a browsable activity, never a named
        // component of some app.
        intent.addCategory(Intent.CATEGORY_BROWSABLE)
        intent.component = null
        intent.selector = null
        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        return try {
            context.startActivity(intent)
            null
        } catch (e: ActivityNotFoundException) {
            fallback
        }
    }
}

/** Hides the status and navigation bars while a page (a video) is full screen. */
@Composable
internal fun FullScreenEffect(fullScreen: Boolean) {
    val view = LocalView.current
    DisposableEffect(fullScreen) {
        var context = view.context
        while (context is ContextWrapper && context !is Activity) context = context.baseContext
        val window = (context as? Activity)?.window
        val controller = window?.let { WindowCompat.getInsetsController(it, view) }
        if (fullScreen) {
            controller?.systemBarsBehavior = WindowInsetsControllerCompat.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
            controller?.hide(WindowInsetsCompat.Type.systemBars())
        }
        onDispose {
            if (fullScreen) controller?.show(WindowInsetsCompat.Type.systemBars())
        }
    }
}
