// Plain Kotlin, copied into the Android build as is (Skip copies .kt files
// from a module's Skip/ folder). The activity-result launchers and Compose
// state below read more clearly in Kotlin than transpiled from Swift.
package zen.mobile

import android.content.Context
import android.net.Uri
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.platform.LocalContext
import org.mozilla.geckoview.Autocomplete
import org.mozilla.geckoview.GeckoResult
import org.mozilla.geckoview.GeckoSession
import org.mozilla.geckoview.GeckoSession.PermissionDelegate
import org.mozilla.geckoview.GeckoSession.PermissionDelegate.ContentPermission
import org.mozilla.geckoview.GeckoSession.PromptDelegate
import org.mozilla.geckoview.GeckoSession.PromptDelegate.PromptResponse

/**
 * A tab's JavaScript dialogs, <select> menus, saved-password prompts,
 * permission requests and file pickers.
 *
 * Dialogs and site permissions go to the app's own UI (Swift, through [ask]:
 * id, kind, message, default text) and come back through [answer]. The
 * system file picker and Android's runtime permission prompts need an
 * activity, so [GeckoPromptEffects] launches them from the tab's composition.
 */
internal class GeckoPrompts(
    private val ask: (Int, String, String, String?) -> Unit,
    /** Whether to offer saving passwords and filling saved ones. */
    private val usesLogins: Boolean,
) : PromptDelegate, PermissionDelegate {
    class FilePick(val mimeType: String, val multiple: Boolean, val done: (Context, List<Uri>) -> Unit)
    class AndroidPermissions(val permissions: Array<String>, val done: (Boolean) -> Unit)

    /** A file picker waiting to be shown. */
    var filePick by mutableStateOf<FilePick?>(null)
    /** Android permissions (camera, microphone, location) waiting to be asked for. */
    var androidPermissions by mutableStateOf<AndroidPermissions?>(null)

    private var nextId = 0
    private val pending = mutableMapOf<Int, (Boolean, String?) -> Unit>()

    fun answer(id: Int, accepted: Boolean, text: String?) {
        pending.remove(id)?.invoke(accepted, text)
    }

    private fun <T> request(kind: String, message: String, defaultText: String? = null, complete: (Boolean, String?) -> T): GeckoResult<T> {
        val result = GeckoResult<T>()
        val id = nextId++
        pending[id] = { accepted, text -> result.complete(complete(accepted, text)) }
        ask(id, kind, message, defaultText)
        return result
    }

    // JavaScript dialogs: alert, confirm and prompt.

    override fun onAlertPrompt(session: GeckoSession, prompt: PromptDelegate.AlertPrompt): GeckoResult<PromptResponse> =
        request("alert", prompt.message ?: "") { _, _ -> prompt.dismiss() }

    override fun onButtonPrompt(session: GeckoSession, prompt: PromptDelegate.ButtonPrompt): GeckoResult<PromptResponse> =
        request("confirm", prompt.message ?: "") { accepted, _ ->
            prompt.confirm(if (accepted) PromptDelegate.ButtonPrompt.Type.POSITIVE else PromptDelegate.ButtonPrompt.Type.NEGATIVE)
        }

    override fun onTextPrompt(session: GeckoSession, prompt: PromptDelegate.TextPrompt): GeckoResult<PromptResponse> =
        request("text", prompt.message ?: "", prompt.defaultValue) { accepted, text ->
            if (accepted) prompt.confirm(text ?: "") else prompt.dismiss()
        }

    // <select> menus: one choice from the app's list (multiple-choice lists
    // keep Gecko's default).

    override fun onChoicePrompt(session: GeckoSession, prompt: PromptDelegate.ChoicePrompt): GeckoResult<PromptResponse>? {
        if (prompt.type == PromptDelegate.ChoicePrompt.Type.MULTIPLE) return null
        val choices = mutableListOf<PromptDelegate.ChoicePrompt.Choice>()
        fun add(items: Array<PromptDelegate.ChoicePrompt.Choice>) {
            for (choice in items) {
                val group = choice.items
                if (group != null) add(group) else if (!choice.separator && !choice.disabled) choices.add(choice)
            }
        }
        add(prompt.choices)
        if (choices.isEmpty()) return null
        return request("choice", prompt.title ?: "", choices.joinToString("\n") { it.label }) { accepted, text ->
            val index = text?.toIntOrNull()
            if (accepted && index != null && index in choices.indices) prompt.confirm(choices[index]) else prompt.dismiss()
        }
    }

    // Saved passwords. Gecko finds the forms, fills a single saved login
    // itself and asks here to save a new one or pick among several; the
    // logins come from GeckoLoginStorage.

    override fun onLoginSave(
        session: GeckoSession,
        save: PromptDelegate.AutocompleteRequest<Autocomplete.LoginSaveOption>,
    ): GeckoResult<PromptResponse>? {
        val option = save.options.firstOrNull()
        if (!usesLogins || option == null) return null
        val login = option.value
        val who = if (login.username.isEmpty()) "" else " for ${login.username}"
        val verb = if (login.guid == null) "Save" else "Update"
        return request("saveLogin", "$verb password$who on ${host(login.origin)}?") { accepted, _ ->
            if (accepted) save.confirm(option) else save.dismiss()
        }
    }

    override fun onLoginSelect(
        session: GeckoSession,
        select: PromptDelegate.AutocompleteRequest<Autocomplete.LoginSelectOption>,
    ): GeckoResult<PromptResponse>? {
        val options = select.options
        if (!usesLogins || options.isEmpty()) return null
        val names = options.joinToString("\n") { it.value.username.ifEmpty { "(no username)" } }
        return request("choice", "Fill a saved password", names) { accepted, text ->
            val index = text?.toIntOrNull()
            if (accepted && index != null && index in options.indices) select.confirm(options[index]) else select.dismiss()
        }
    }

    // File uploads (<input type=file>): the system picker.

    override fun onFilePrompt(session: GeckoSession, prompt: PromptDelegate.FilePrompt): GeckoResult<PromptResponse> {
        val result = GeckoResult<PromptResponse>()
        val multiple = prompt.type == PromptDelegate.FilePrompt.Type.MULTIPLE
        // The picker takes one MIME type; anything more specific than one
        // full type (several types, or extensions like ".pdf") gets all files.
        val mimeType = prompt.mimeTypes?.singleOrNull()?.takeIf { it.contains("/") } ?: "*/*"
        filePick = FilePick(mimeType, multiple) { context, uris ->
            val chosen = if (multiple) uris else uris.take(1)
            result.complete(if (chosen.isEmpty()) prompt.dismiss() else prompt.confirm(context, chosen.toTypedArray()))
        }
        return result
    }

    // Site permissions: the app asks the user, as Firefox does.

    override fun onContentPermissionRequest(session: GeckoSession, perm: ContentPermission): GeckoResult<Int>? {
        val what = when (perm.permission) {
            PermissionDelegate.PERMISSION_GEOLOCATION -> "know your location"
            PermissionDelegate.PERMISSION_DESKTOP_NOTIFICATION -> "show notifications"
            // Gecko's own defaults for the rest (autoplay, storage, ...).
            else -> return null
        }
        return request("permission", "${host(perm.uri)} wants to $what.") { accepted, _ ->
            if (accepted) ContentPermission.VALUE_ALLOW else ContentPermission.VALUE_DENY
        }
    }

    override fun onMediaPermissionRequest(
        session: GeckoSession,
        uri: String,
        video: Array<PermissionDelegate.MediaSource>?,
        audio: Array<PermissionDelegate.MediaSource>?,
        callback: PermissionDelegate.MediaCallback,
    ) {
        val what = listOfNotNull(video?.let { "camera" }, audio?.let { "microphone" }).joinToString(" and ")
        request("permission", "${host(uri)} wants to use your $what.") { accepted, _ ->
            if (accepted) callback.grant(video?.firstOrNull(), audio?.firstOrNull()) else callback.reject()
        }
    }

    // Before using the camera, microphone or location for a site, Gecko asks
    // for the Android permission it needs (the user sees the system prompt).
    override fun onAndroidPermissionsRequest(session: GeckoSession, permissions: Array<String>?, callback: PermissionDelegate.Callback) {
        if (permissions.isNullOrEmpty()) {
            callback.grant()
            return
        }
        androidPermissions = AndroidPermissions(permissions) { granted ->
            if (granted) callback.grant() else callback.reject()
        }
    }

    private fun host(uri: String): String = Uri.parse(uri).host ?: uri
}

/** Shows the file picker and Android permission prompts a tab is waiting on. */
@Composable
internal fun GeckoPromptEffects(prompts: GeckoPrompts) {
    val context = LocalContext.current
    val pickFiles = rememberLauncherForActivityResult(ActivityResultContracts.GetMultipleContents()) { uris ->
        prompts.filePick?.let { pick ->
            prompts.filePick = null
            pick.done(context, uris)
        }
    }
    val requestPermissions = rememberLauncherForActivityResult(ActivityResultContracts.RequestMultiplePermissions()) { results ->
        prompts.androidPermissions?.let { ask ->
            prompts.androidPermissions = null
            ask.done(results.values.all { it })
        }
    }
    val filePick = prompts.filePick
    LaunchedEffect(filePick) {
        filePick?.let { pickFiles.launch(it.mimeType) }
    }
    val androidPermissions = prompts.androidPermissions
    LaunchedEffect(androidPermissions) {
        androidPermissions?.let { requestPermissions.launch(it.permissions) }
    }
}
