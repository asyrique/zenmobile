// Plain Kotlin, copied into the Android build as is (see GeckoPrompts.kt).
package zen.mobile

import org.mozilla.geckoview.GeckoSession

/** Find in page on Android: Gecko's finder, which reports match counts. */
internal object GeckoFind {
    /** [done] gets (found, current match, total matches), on the main thread. */
    fun find(session: GeckoSession, text: String, backwards: Boolean, done: (Boolean, Int, Int) -> Unit) {
        val flags = if (backwards) GeckoSession.FINDER_FIND_BACKWARDS else GeckoSession.FINDER_FIND_FORWARD
        session.finder.find(text, flags).accept { result ->
            if (result != null) done(result.found, result.current, result.total)
        }
    }
}
