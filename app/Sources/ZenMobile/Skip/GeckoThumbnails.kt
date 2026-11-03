// Plain Kotlin, copied into the Android build as is (see GeckoPrompts.kt).
package zen.mobile

import android.graphics.Bitmap
import android.os.Handler
import android.os.Looper
import java.io.File
import org.mozilla.geckoview.GeckoView

/** Pictures of pages for the tab switcher's cards. */
internal object GeckoThumbnails {
    /**
     * Captures what [view] shows, scales it to [width] pixels wide and saves
     * it as a JPEG at [path], off the main thread. [done] runs on the main
     * thread with whether it worked.
     */
    fun capture(view: GeckoView, path: String, width: Int, done: (Boolean) -> Unit) {
        val main = Handler(Looper.getMainLooper())
        view.capturePixels().accept({ bitmap: Bitmap? ->
            if (bitmap == null || bitmap.width == 0) {
                done(false)
            } else {
                Thread {
                    val saved = try {
                        val height = (bitmap.height.toLong() * width / bitmap.width).toInt().coerceAtLeast(1)
                        val scaled = Bitmap.createScaledBitmap(bitmap, width, height, true)
                        File(path).outputStream().use { scaled.compress(Bitmap.CompressFormat.JPEG, 70, it) }
                        true
                    } catch (e: Exception) {
                        android.util.Log.e("ZenThumbnails", "Saving a thumbnail failed", e)
                        false
                    }
                    main.post { done(saved) }
                }.start()
            }
        }, { _: Throwable? ->
            done(false)
        })
    }
}
