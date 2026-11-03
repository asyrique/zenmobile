// Plain Kotlin, copied into the Android build as is (see GeckoPrompts.kt).
package zen.mobile

import android.app.Activity
import android.app.KeyguardManager
import android.app.PendingIntent
import android.app.assist.AssistStructure
import android.content.Context
import android.content.Intent
import android.content.IntentSender
import android.content.pm.PackageManager
import android.os.Bundle
import android.os.CancellationSignal
import android.os.Handler
import android.os.Looper
import android.service.autofill.AutofillService
import android.service.autofill.Dataset
import android.service.autofill.FillCallback
import android.service.autofill.FillRequest
import android.service.autofill.FillResponse
import android.service.autofill.SaveCallback
import android.service.autofill.SaveInfo
import android.service.autofill.SaveRequest
import android.text.InputType
import android.view.View
import android.view.autofill.AutofillId
import android.view.autofill.AutofillManager
import android.view.autofill.AutofillValue
import android.widget.RemoteViews
import java.net.HttpURLConnection
import java.net.URL
import java.security.MessageDigest
import java.util.concurrent.ConcurrentHashMap
import org.json.JSONArray

/**
 * Android's AutoFill service: fills sign-in forms in other browsers and
 * apps with the passwords saved in Zen (AutofillLogins.swift), as Firefox
 * for Android does.
 *
 * - The site is the page's web domain, when a browser or web view reports
 *   one. For an app, it's a domain whose Digital Asset Links file says the
 *   app (by package and signing certificate) may use its logins; package
 *   names alone prove nothing.
 * - Nothing is filled until the user unlocks with the screen lock
 *   (AutofillUnlockActivity).
 * - Sign-ins on web pages are offered for saving.
 * - The browser itself is left to Gecko's own login manager.
 */
class ZenAutofillService : AutofillService() {
    private val main = Handler(Looper.getMainLooper())

    override fun onFillRequest(request: FillRequest, cancellationSignal: CancellationSignal, callback: FillCallback) {
        val structure = request.fillContexts.lastOrNull()?.structure
        val form = structure?.let { AutofillForm.parse(it) }
        android.util.Log.i(TAG, "Fill request: app ${form?.packageName}, site ${form?.webDomain}, " +
            "username field ${form?.username != null}, password field ${form?.password != null}")
        if (form == null || form.packageName == packageName || (form.username == null && form.password == null)) {
            callback.onSuccess(null)
            return
        }
        // Checking an app's asset links needs the network: off the main
        // thread, then back to it for the store.
        Thread {
            val host = form.webDomain ?: AssetLinks.verifiedDomain(this, form.packageName)
            main.post {
                if (cancellationSignal.isCanceled) return@post
                val response = host?.let { response(form, it) }
                android.util.Log.i(TAG, "Fill response for $host: ${if (response == null) "none" else "offered"}")
                callback.onSuccess(response)
            }
        }.start()
    }

    private fun response(form: AutofillForm, host: String): FillResponse? {
        val count = try {
            JSONArray(AutofillLogins.logins(host)).length()
        } catch (e: Exception) {
            android.util.Log.e(TAG, "Reading logins for $host failed", e)
            0
        }
        android.util.Log.i(TAG, "$count saved logins for $host")
        val builder = FillResponse.Builder()
        var empty = true
        if (count > 0) {
            val label = if (count == 1) "Zen: 1 saved password" else "Zen: $count saved passwords"
            builder.setAuthentication(form.ids, AutofillUnlockActivity.intentSender(this, host, form), presentation(this, label))
            empty = false
        }
        // Sign-ins on web pages can be saved; apps' have no address to save
        // them under.
        if (form.webDomain != null && form.password != null) {
            builder.setSaveInfo(SaveInfo.Builder(SaveInfo.SAVE_DATA_TYPE_PASSWORD or SaveInfo.SAVE_DATA_TYPE_USERNAME, form.ids).build())
            empty = false
        }
        return if (empty) null else builder.build()
    }

    override fun onSaveRequest(request: SaveRequest, callback: SaveCallback) {
        val structure = request.fillContexts.lastOrNull()?.structure
        val form = structure?.let { AutofillForm.parse(it) }
        val host = form?.webDomain
        val password = form?.passwordValue
        if (host != null && !password.isNullOrEmpty()) {
            AutofillLogins.save("https://$host", form.usernameValue ?: "", password)
        }
        callback.onSuccess()
    }

    companion object {
        const val TAG = "ZenAutofill"

        fun presentation(context: Context, text: String): RemoteViews =
            RemoteViews(context.packageName, android.R.layout.simple_list_item_1).apply {
                setTextViewText(android.R.id.text1, text)
            }
    }
}

/** A sign-in form found in a screen's structure. */
class AutofillForm(
    val packageName: String,
    val webDomain: String?,
    val username: AutofillId?,
    val password: AutofillId?,
    val usernameValue: String?,
    val passwordValue: String?,
) {
    val ids: Array<AutofillId> get() = listOfNotNull(username, password).toTypedArray()

    companion object {
        fun parse(structure: AssistStructure): AutofillForm {
            var webDomain: String? = null
            var username: AssistStructure.ViewNode? = null
            var password: AssistStructure.ViewNode? = null
            // Text fields in screen order, for the one before the password.
            val textFields = mutableListOf<AssistStructure.ViewNode>()

            fun visit(node: AssistStructure.ViewNode) {
                node.webDomain?.takeIf { it.isNotEmpty() }?.let { webDomain = it }
                if (node.autofillId != null && node.autofillType == View.AUTOFILL_TYPE_TEXT) {
                    when {
                        isPassword(node) -> if (password == null) password = node
                        isUsername(node) -> if (username == null) username = node
                        else -> if (password == null) textFields.add(node)
                    }
                }
                for (i in 0 until node.childCount) visit(node.getChildAt(i))
            }
            for (i in 0 until structure.windowNodeCount) visit(structure.getWindowNodeAt(i).rootViewNode)
            if (username == null && password != null) username = textFields.lastOrNull()

            return AutofillForm(
                packageName = structure.activityComponent.packageName,
                webDomain = webDomain,
                username = username?.autofillId,
                password = password?.autofillId,
                usernameValue = username?.autofillValue?.takeIf { it.isText }?.textValue?.toString(),
                passwordValue = password?.autofillValue?.takeIf { it.isText }?.textValue?.toString(),
            )
        }

        private fun hints(node: AssistStructure.ViewNode): List<String> {
            val html = node.htmlInfo?.attributes?.filter { it.first == "type" || it.first == "autocomplete" || it.first == "name" }
                ?.map { it.second.orEmpty() } ?: emptyList()
            return (node.autofillHints?.toList().orEmpty() + html + listOfNotNull(node.idEntry, node.hint))
                .map { it.lowercase() }
        }

        private fun isPassword(node: AssistStructure.ViewNode): Boolean {
            val type = node.inputType
            val variation = type and InputType.TYPE_MASK_VARIATION
            val textPassword = (type and InputType.TYPE_MASK_CLASS) == InputType.TYPE_CLASS_TEXT &&
                (variation == InputType.TYPE_TEXT_VARIATION_PASSWORD ||
                    variation == InputType.TYPE_TEXT_VARIATION_VISIBLE_PASSWORD ||
                    variation == InputType.TYPE_TEXT_VARIATION_WEB_PASSWORD)
            return textPassword || hints(node).any { it == "password" || it.contains("current-password") || it == View.AUTOFILL_HINT_PASSWORD.lowercase() }
        }

        private fun isUsername(node: AssistStructure.ViewNode): Boolean {
            val words = listOf("user", "email", "login", "account")
            return hints(node).any { hint -> words.any { hint.contains(it) } }
        }
    }
}

/**
 * Asks for the screen lock, then hands Android the saved logins for the
 * site as choices. A device with no screen lock has nothing to ask for.
 */
class AutofillUnlockActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (savedInstanceState != null) return
        val keyguard = getSystemService(KeyguardManager::class.java)
        @Suppress("DEPRECATION") // Its replacement, BiometricPrompt, needs a FragmentActivity.
        val confirm = if (keyguard?.isDeviceSecure == true) {
            keyguard.createConfirmDeviceCredentialIntent("Zen passwords", "Unlock to fill a saved password")
        } else {
            null
        }
        if (confirm == null) {
            finishWithLogins()
        } else {
            @Suppress("DEPRECATION")
            startActivityForResult(confirm, CONFIRM)
        }
    }

    @Deprecated("Activity result API")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        @Suppress("DEPRECATION")
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == CONFIRM && resultCode == RESULT_OK) {
            finishWithLogins()
        } else {
            setResult(RESULT_CANCELED)
            finish()
        }
    }

    private fun finishWithLogins() {
        val host = intent.getStringExtra(EXTRA_HOST)
        @Suppress("DEPRECATION")
        val usernameId = intent.getParcelableExtra<AutofillId>(EXTRA_USERNAME)
        @Suppress("DEPRECATION")
        val passwordId = intent.getParcelableExtra<AutofillId>(EXTRA_PASSWORD)
        val logins = try {
            JSONArray(AutofillLogins.logins(host ?: ""))
        } catch (e: Exception) {
            JSONArray()
        }
        val builder = FillResponse.Builder()
        var datasets = 0
        for (i in 0 until logins.length()) {
            val login = logins.getJSONObject(i)
            val username = login.optString("username")
            val password = login.optString("password")
            @Suppress("DEPRECATION") // Dataset.Builder(Presentations) needs API 33.
            val dataset = Dataset.Builder(ZenAutofillService.presentation(this, username.ifEmpty { "(no username)" }))
            @Suppress("DEPRECATION")
            usernameId?.let { dataset.setValue(it, AutofillValue.forText(username)) }
            @Suppress("DEPRECATION")
            passwordId?.let { dataset.setValue(it, AutofillValue.forText(password)) }
            if (usernameId != null || passwordId != null) {
                builder.addDataset(dataset.build())
                datasets += 1
            }
        }
        if (datasets == 0) {
            setResult(RESULT_CANCELED)
        } else {
            setResult(RESULT_OK, Intent().putExtra(AutofillManager.EXTRA_AUTHENTICATION_RESULT, builder.build()))
        }
        finish()
    }

    companion object {
        private const val CONFIRM = 1
        private const val EXTRA_HOST = "zen.autofill.host"
        private const val EXTRA_USERNAME = "zen.autofill.username"
        private const val EXTRA_PASSWORD = "zen.autofill.password"
        private var nextRequest = 0

        fun intentSender(context: Context, host: String, form: AutofillForm): IntentSender {
            val intent = Intent(context, AutofillUnlockActivity::class.java)
                .putExtra(EXTRA_HOST, host)
                .putExtra(EXTRA_USERNAME, form.username)
                .putExtra(EXTRA_PASSWORD, form.password)
            // Mutable: Android adds the screen's structure to it.
            val flags = PendingIntent.FLAG_CANCEL_CURRENT or PendingIntent.FLAG_MUTABLE
            return PendingIntent.getActivity(context, nextRequest++, intent, flags).intentSender
        }
    }
}

/**
 * Digital Asset Links: a site's /.well-known/assetlinks.json can say an app
 * (package and signing certificate) may use the site's logins. Candidate
 * sites come from the package name (com.example.app → example.com,
 * app.example.com); only the file's say-so counts. Results are cached for
 * the process's life.
 */
object AssetLinks {
    private val verified = ConcurrentHashMap<String, String>()
    private val refused = ConcurrentHashMap.newKeySet<String>()

    fun verifiedDomain(context: Context, packageName: String): String? {
        verified[packageName]?.let { return it }
        if (packageName in refused) return null
        val fingerprints = fingerprints(context, packageName)
        if (fingerprints.isNotEmpty()) {
            for (domain in candidates(packageName)) {
                if (authorizes(domain, packageName, fingerprints)) {
                    verified[packageName] = domain
                    return domain
                }
            }
        }
        refused.add(packageName)
        return null
    }

    private fun candidates(packageName: String): List<String> {
        val parts = packageName.split('.').filter { it.isNotEmpty() }
        if (parts.size < 2) return emptyList()
        val site = "${parts[1]}.${parts[0]}"
        return listOfNotNull(site, parts.getOrNull(2)?.let { "$it.$site" })
    }

    private fun authorizes(domain: String, packageName: String, fingerprints: Set<String>): Boolean = try {
        val connection = URL("https://$domain/.well-known/assetlinks.json").openConnection() as HttpURLConnection
        connection.connectTimeout = 1500
        connection.readTimeout = 1500
        connection.instanceFollowRedirects = false
        val statements = connection.inputStream.bufferedReader().use { JSONArray(it.readText()) }
        (0 until statements.length()).map { statements.getJSONObject(it) }.any { statement ->
            val relations = statement.optJSONArray("relation") ?: JSONArray()
            val grantsLogins = (0 until relations.length()).any { relations.getString(it) == "delegate_permission/common.get_login_creds" }
            val target = statement.optJSONObject("target")
            val certs = target?.optJSONArray("sha256_cert_fingerprints") ?: JSONArray()
            grantsLogins && target?.optString("namespace") == "android_app" &&
                target.optString("package_name") == packageName &&
                (0 until certs.length()).any { certs.getString(it).uppercase() in fingerprints }
        }
    } catch (e: Exception) {
        false
    }

    /** The app's signing certificates' SHA-256 fingerprints, as AA:BB:... */
    private fun fingerprints(context: Context, packageName: String): Set<String> = try {
        val info = context.packageManager.getPackageInfo(packageName, PackageManager.GET_SIGNING_CERTIFICATES)
        val signing = info.signingInfo
        val signatures = when {
            signing == null -> emptyArray()
            signing.hasMultipleSigners() -> signing.apkContentsSigners
            else -> signing.signingCertificateHistory
        }
        signatures.map { signature ->
            MessageDigest.getInstance("SHA-256").digest(signature.toByteArray()).joinToString(":") { "%02X".format(it) }
        }.toSet()
    } catch (e: Exception) {
        emptySet()
    }
}
