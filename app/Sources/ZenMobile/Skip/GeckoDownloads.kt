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
import org.mozilla.geckoview.GeckoRuntime
import org.mozilla.geckoview.GeckoWebExecutor
import org.mozilla.geckoview.WebRequest
import org.mozilla.geckoview.WebResponse

/** Downloads on Android: saving what Gecko can't show, and opening it. */
internal object GeckoDownloads {
    /** The app's Downloads folder, which the file provider can share from. */
    fun directory(context: Context): File = File(context.filesDir, "Downloads").apply { mkdirs() }

    /**
     * Saves [response] (a page's download, which Gecko has already fetched
     * with the page's cookies) into [directory] on a background thread.
     * [report] runs on the main thread with (file name, percent or -1 if the
     * size is unknown, state: 0 running, 1 done, 2 failed): once as it
     * starts, as it progresses, and when it ends.
     */
    fun save(response: WebResponse, directory: File, report: (String, Int, Int) -> Unit) {
        val body = response.body ?: return
        val name = URLUtil.guessFileName(
            response.uri,
            header(response, "Content-Disposition"),
            header(response, "Content-Type"),
        )
        val length = header(response, "Content-Length")?.toLongOrNull() ?: -1L
        val file = freeFile(directory, name)
        val main = Handler(Looper.getMainLooper())
        report(file.name, -1, 0)
        Thread {
            val succeeded = try {
                body.use { input ->
                    file.outputStream().use { output ->
                        val buffer = ByteArray(64 * 1024)
                        var copied = 0L
                        var lastReport = 0L
                        while (true) {
                            val count = input.read(buffer)
                            if (count < 0) break
                            output.write(buffer, 0, count)
                            copied += count
                            val now = System.currentTimeMillis()
                            if (length > 0 && now - lastReport > 250) {
                                lastReport = now
                                val percent = (copied * 100 / length).toInt().coerceIn(0, 100)
                                main.post { report(file.name, percent, 0) }
                            }
                        }
                    }
                }
                true
            } catch (e: Exception) {
                android.util.Log.e("ZenDownloads", "Download of ${response.uri} failed", e)
                file.delete()
                false
            }
            main.post { report(file.name, 100, if (succeeded) 1 else 2) }
        }.start()
    }

    /** Fetches [uri] (an image from a page's menu) and saves it like a download. */
    fun fetch(runtime: GeckoRuntime, uri: String, directory: File, report: (String, Int, Int) -> Unit) {
        GeckoWebExecutor(runtime).fetch(WebRequest(uri)).accept({ response: WebResponse? ->
            if (response != null) save(response, directory, report)
        }, { error: Throwable? ->
            android.util.Log.e("ZenDownloads", "Fetching $uri failed", error)
        })
    }

    private fun header(response: WebResponse, name: String): String? =
        response.headers.entries.firstOrNull { it.key.equals(name, ignoreCase = true) }?.value

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
