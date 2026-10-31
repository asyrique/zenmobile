import Foundation

#if SKIP
// Kotlin side (transpiled by Skip): file helpers Swift calls on Android,
// implemented in GeckoDownloads.kt. Public so Kotlin doesn't rename them on
// the JVM, where Skip's bridge looks them up.

struct AndroidFiles {
    /// The app's Downloads folder.
    public static func downloadsDirectory() -> String {
        GeckoDownloads.directory(ProcessInfo.processInfo.androidContext).absolutePath
    }

    /// Opens a downloaded file in an app that can show it.
    public static func open(path: String) {
        GeckoDownloads.open(ProcessInfo.processInfo.androidContext, path)
    }
}

/// The clipboard (DeviceAuth.kt).
struct AndroidClipboard {
    public static func copy(text: String) {
        Clipboards.copy(ProcessInfo.processInfo.androidContext, text)
    }
}
#endif
