// Plain Kotlin, copied into the Android build as is (see GeckoPrompts.kt).
package zen.mobile

import android.app.Activity
import android.app.KeyguardManager
import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
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
