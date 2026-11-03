// Plain Kotlin, copied into the Android build as is (Skip copies .kt files
// from a module's Skip/ folder). The activity-result launchers and Compose
// state below read more clearly in Kotlin than transpiled from Swift.
package zen.mobile

import android.app.DatePickerDialog
import android.app.TimePickerDialog
import android.content.Context
import android.content.Intent
import android.net.Uri
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.platform.LocalContext
import java.time.LocalDate
import java.time.LocalTime
import java.time.temporal.IsoFields
import org.mozilla.geckoview.AllowOrDeny
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
    /** A date and/or time input's picker: Gecko's type, the current value, and the chosen one (null if cancelled). */
    class DateTimePick(val type: Int, val value: String, val done: (String?) -> Unit)
    class Share(val title: String?, val text: String?, val uri: String?, val done: (Boolean) -> Unit)

    /** A file picker waiting to be shown. */
    var filePick by mutableStateOf<FilePick?>(null)
    /** Android permissions (camera, microphone, location) waiting to be asked for. */
    var androidPermissions by mutableStateOf<AndroidPermissions?>(null)
    var dateTimePick by mutableStateOf<DateTimePick?>(null)
    var share by mutableStateOf<Share?>(null)

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

    // Leaving a page with unsaved changes, and sending a form again.

    override fun onBeforeUnloadPrompt(session: GeckoSession, prompt: PromptDelegate.BeforeUnloadPrompt): GeckoResult<PromptResponse> =
        request("confirm", "Leave this page? Changes you made may not be saved.") { accepted, _ ->
            prompt.confirm(if (accepted) AllowOrDeny.ALLOW else AllowOrDeny.DENY)
        }

    override fun onRepostConfirmPrompt(session: GeckoSession, prompt: PromptDelegate.RepostConfirmPrompt): GeckoResult<PromptResponse> =
        request("confirm", "Send the form again? This page uses information you entered; sending it again repeats any action it took.") { accepted, _ ->
            prompt.confirm(if (accepted) AllowOrDeny.ALLOW else AllowOrDeny.DENY)
        }

    // HTTP authentication: the answer is "username\npassword".

    override fun onAuthPrompt(session: GeckoSession, prompt: PromptDelegate.AuthPrompt): GeckoResult<PromptResponse> {
        val options = prompt.authOptions
        val onlyPassword = (options.flags and PromptDelegate.AuthPrompt.AuthOptions.Flags.ONLY_PASSWORD) != 0
        val where = options.uri?.let { host(it) } ?: "This site"
        return request("auth", prompt.message ?: "$where asks you to sign in.", if (onlyPassword) null else options.username ?: "") { accepted, text ->
            val username = text?.substringBefore('\n') ?: ""
            val password = text?.substringAfter('\n', "") ?: ""
            when {
                !accepted -> prompt.dismiss()
                onlyPassword -> prompt.confirm(password)
                else -> prompt.confirm(username, password)
            }
        }
    }

    // Date and time inputs: Android's pickers (GeckoPromptEffects).

    override fun onDateTimePrompt(session: GeckoSession, prompt: PromptDelegate.DateTimePrompt): GeckoResult<PromptResponse>? {
        val type = prompt.type
        if (type != PromptDelegate.DateTimePrompt.Type.DATE && type != PromptDelegate.DateTimePrompt.Type.TIME &&
            type != PromptDelegate.DateTimePrompt.Type.DATETIME_LOCAL && type != PromptDelegate.DateTimePrompt.Type.MONTH &&
            type != PromptDelegate.DateTimePrompt.Type.WEEK) return null
        val result = GeckoResult<PromptResponse>()
        dateTimePick = DateTimePick(type, prompt.defaultValue ?: "") { value ->
            result.complete(if (value == null) prompt.dismiss() else prompt.confirm(value))
        }
        return result
    }

    // navigator.share(): Android's share sheet.

    override fun onSharePrompt(session: GeckoSession, prompt: PromptDelegate.SharePrompt): GeckoResult<PromptResponse> {
        val result = GeckoResult<PromptResponse>()
        share = Share(prompt.title, prompt.text, prompt.uri) { shared ->
            result.complete(prompt.confirm(if (shared) PromptDelegate.SharePrompt.Result.SUCCESS else PromptDelegate.SharePrompt.Result.FAILURE))
        }
        return result
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
    val dateTimePick = prompts.dateTimePick
    LaunchedEffect(dateTimePick) {
        dateTimePick?.let { pick ->
            prompts.dateTimePick = null
            showDateTimePicker(context, pick)
        }
    }
    val share = prompts.share
    LaunchedEffect(share) {
        share?.let { request ->
            prompts.share = null
            val text = listOfNotNull(request.text, request.uri).joinToString("\n")
            val send = Intent(Intent.ACTION_SEND).setType("text/plain").putExtra(Intent.EXTRA_TEXT, text)
            request.title?.let { send.putExtra(Intent.EXTRA_SUBJECT, it) }
            val shared = try {
                context.startActivity(Intent.createChooser(send, request.title))
                true
            } catch (e: Exception) {
                false
            }
            request.done(shared)
        }
    }
}

/**
 * Android's date and time pickers for Gecko's input types, with values in
 * HTML's formats: 2026-10-31, 2026-10, 2026-W44, 09:30, 2026-10-31T09:30.
 */
private fun showDateTimePicker(context: Context, pick: GeckoPrompts.DateTimePick) {
    val type = pick.type
    val value = pick.value
    val today = LocalDate.now()
    val date = try {
        when (type) {
            PromptDelegate.DateTimePrompt.Type.MONTH -> LocalDate.parse("$value-01")
            PromptDelegate.DateTimePrompt.Type.WEEK -> {
                val (year, week) = value.split("-W").map { it.toInt() }
                today.withYear(year).with(IsoFields.WEEK_OF_WEEK_BASED_YEAR, week.toLong())
            }
            else -> LocalDate.parse(value.substringBefore('T'))
        }
    } catch (e: Exception) {
        today
    }
    val time = try {
        LocalTime.parse(if (value.contains('T')) value.substringAfter('T') else value)
    } catch (e: Exception) {
        LocalTime.now().withSecond(0).withNano(0)
    }
    fun pickTime(done: (LocalTime) -> Unit) {
        TimePickerDialog(context, { _, hour, minute -> done(LocalTime.of(hour, minute)) }, time.hour, time.minute,
            android.text.format.DateFormat.is24HourFormat(context)).apply {
            setOnCancelListener { pick.done(null) }
            show()
        }
    }
    if (type == PromptDelegate.DateTimePrompt.Type.TIME) {
        pickTime { pick.done(it.toString()) }
        return
    }
    DatePickerDialog(context, { _, year, month, day ->
        val chosen = LocalDate.of(year, month + 1, day)
        when (type) {
            PromptDelegate.DateTimePrompt.Type.MONTH -> pick.done("%04d-%02d".format(chosen.year, chosen.monthValue))
            PromptDelegate.DateTimePrompt.Type.WEEK -> pick.done("%04d-W%02d".format(
                chosen.get(IsoFields.WEEK_BASED_YEAR), chosen.get(IsoFields.WEEK_OF_WEEK_BASED_YEAR)))
            PromptDelegate.DateTimePrompt.Type.DATETIME_LOCAL -> pickTime { pick.done("${chosen}T$it") }
            else -> pick.done(chosen.toString())
        }
    }, date.year, date.monthValue - 1, date.dayOfMonth).apply {
        setOnCancelListener { pick.done(null) }
        show()
    }
}
