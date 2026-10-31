// Plain Kotlin, copied into the Android build as is (see GeckoPrompts.kt).
package zen.mobile

import org.mozilla.geckoview.GeckoResult
import org.mozilla.geckoview.GeckoRuntime
import org.mozilla.geckoview.WebExtension
import org.mozilla.geckoview.WebExtensionController

/**
 * Ad blocking on Android: uBlock Origin, installed from addons.mozilla.org
 * (signed by Mozilla) as on Firefox for Android, when the setting is on, and
 * removed when it's turned off.
 */
internal object GeckoAdBlocking {
    private const val ID = "uBlock0@raymondhill.net"
    private const val XPI = "https://addons.mozilla.org/firefox/downloads/latest/ublock-origin/latest.xpi"

    @Volatile
    var enabled = false

    fun apply(runtime: GeckoRuntime) {
        val controller = runtime.webExtensionController
        controller.setPromptDelegate(object : WebExtensionController.PromptDelegate {
            // Turning ad blocking on in Settings is the consent; nothing else
            // gets installed this way.
            override fun onInstallPromptRequest(
                extension: WebExtension,
                permissions: Array<String>,
                origins: Array<String>,
                dataCollectionPermissions: Array<String>,
            ): GeckoResult<WebExtension.PermissionPromptResponse> {
                val ours = extension.id == ID
                return GeckoResult.fromValue(WebExtension.PermissionPromptResponse(ours, ours, false))
            }
        })
        controller.list().accept({ extensions ->
            val installed = extensions?.firstOrNull { it.id == ID }
            if (enabled && installed == null) {
                controller.install(XPI).accept({ extension ->
                    // Private tabs get ads blocked too.
                    if (extension != null) controller.setAllowedInPrivateBrowsing(extension, true)
                }, { error ->
                    android.util.Log.e("ZenAdBlocking", "Installing uBlock Origin failed", error)
                })
            } else if (!enabled && installed != null) {
                controller.uninstall(installed)
            }
        }, { error ->
            android.util.Log.e("ZenAdBlocking", "Listing extensions failed", error)
        })
    }
}
