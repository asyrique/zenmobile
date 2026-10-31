// Plain Kotlin, copied into the Android build as is (see GeckoPrompts.kt).
package zen.mobile

import android.content.Context
import android.content.Intent
import android.os.Handler
import android.os.Looper
import android.webkit.MimeTypeMap
import android.webkit.URLUtil
import androidx.core.content.FileProvider
import java.io.File
import org.mozilla.geckoview.WebResponse

/** Downloads on Android: saving what Gecko can't show, and opening it. */
internal object GeckoDownloads {
    /** The app's Downloads folder, which the file provider can share from. */
    fun directory(context: Context): File = File(context.filesDir, "Downloads").apply { mkdirs() }

    /**
     * Saves [response] (a page's download, which Gecko has already fetched
     * with the page's cookies) into [directory] on a background thread.
     * [report] runs on the main thread: (file name, finished, succeeded),
     * first when it starts and then when it ends.
     */
    fun save(response: WebResponse, directory: File, report: (String, Boolean, Boolean) -> Unit) {
        val body = response.body ?: return
        val name = URLUtil.guessFileName(
            response.uri,
            response.headers["Content-Disposition"] ?: response.headers["content-disposition"],
            response.headers["Content-Type"] ?: response.headers["content-type"],
        )
        val file = freeFile(directory, name)
        val main = Handler(Looper.getMainLooper())
        report(file.name, false, false)
        Thread {
            val succeeded = try {
                body.use { input -> file.outputStream().use { input.copyTo(it) } }
                true
            } catch (e: Exception) {
                android.util.Log.e("ZenDownloads", "Download of ${response.uri} failed", e)
                file.delete()
                false
            }
            main.post { report(file.name, true, succeeded) }
        }.start()
    }

    /** Opens a downloaded file in an app that can show it. */
    fun open(context: Context, path: String) {
        val file = File(path)
        val uri = FileProvider.getUriForFile(context, "${context.packageName}.files", file)
        val type = MimeTypeMap.getSingleton().getMimeTypeFromExtension(file.extension.lowercase()) ?: "*/*"
        val view = Intent(Intent.ACTION_VIEW).setDataAndType(uri, type).addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        context.startActivity(Intent.createChooser(view, file.name).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
    }

    private fun freeFile(directory: File, name: String): File {
        var file = File(directory, name)
        var count = 1
        while (file.exists()) {
            file = File(directory, if (file.extension.isEmpty()) "${name} ($count)" else "${name.substringBeforeLast('.')} ($count).${name.substringAfterLast('.')}")
            count += 1
        }
        return file
    }
}
