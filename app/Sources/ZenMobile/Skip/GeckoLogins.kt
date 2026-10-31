// Plain Kotlin, copied into the Android build as is (see GeckoPrompts.kt).
package zen.mobile

import org.json.JSONArray
import org.json.JSONObject
import org.mozilla.geckoview.Autocomplete
import org.mozilla.geckoview.GeckoResult
import org.mozilla.geckoview.GeckoRuntime

/**
 * Gecko's saved-password storage: its login manager finds sign-in forms,
 * fills them and offers to save what's submitted, and reads and writes the
 * logins here. They live in the app's logins store (Logins.swift), reached
 * through the functions [GeckoLogins] connects. Logins cross as JSON:
 * guid, origin, formActionOrigin, httpRealm, username, password.
 *
 * The store blocks, so calls run off the main thread.
 */
internal object GeckoLoginStorage : Autocomplete.StorageDelegate {
    /** Base domain → JSON array of logins. */
    @Volatile var fetch: ((String) -> String)? = null
    /** JSON login → saved (added, or updating the one it matches). */
    @Volatile var save: ((String) -> Unit)? = null
    /** Guid of a login that was filled. */
    @Volatile var used: ((String) -> Unit)? = null

    fun attach(runtime: GeckoRuntime) {
        runtime.setAutocompleteStorageDelegate(this)
    }

    override fun onLoginFetch(domain: String): GeckoResult<Array<Autocomplete.LoginEntry>>? {
        val fetch = fetch ?: return null
        val result = GeckoResult<Array<Autocomplete.LoginEntry>>()
        Thread {
            val logins = try {
                val array = JSONArray(fetch(domain))
                Array(array.length()) { entry(array.getJSONObject(it)) }
            } catch (e: Exception) {
                android.util.Log.e("ZenLogins", "Reading logins failed", e)
                emptyArray()
            }
            result.complete(logins)
        }.start()
        return result
    }

    override fun onLoginSave(login: Autocomplete.LoginEntry) {
        val save = save ?: return
        val json = JSONObject()
            .put("guid", login.guid ?: JSONObject.NULL)
            .put("origin", login.origin)
            .put("formActionOrigin", login.formActionOrigin ?: JSONObject.NULL)
            .put("httpRealm", login.httpRealm ?: JSONObject.NULL)
            .put("username", login.username)
            .put("password", login.password)
            .toString()
        Thread { save(json) }.start()
    }

    override fun onLoginUsed(login: Autocomplete.LoginEntry, usedFields: Int) {
        val used = used ?: return
        val guid = login.guid ?: return
        Thread { used(guid) }.start()
    }

    private fun entry(json: JSONObject): Autocomplete.LoginEntry =
        Autocomplete.LoginEntry.Builder()
            .guid(json.text("guid"))
            .origin(json.getString("origin"))
            .formActionOrigin(json.text("formActionOrigin"))
            .httpRealm(json.text("httpRealm"))
            .username(json.text("username") ?: "")
            .password(json.getString("password"))
            .build()

    // optString turns null into "null".
    private fun JSONObject.text(key: String): String? = if (isNull(key)) null else getString(key)
}
