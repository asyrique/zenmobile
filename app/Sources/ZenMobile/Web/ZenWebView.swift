import Foundation
import SwiftUI
#if canImport(WebKit)
import WebKit
#endif

/// Shows a `WebPage`: its WKWebView on iOS, its GeckoSession on Android.
///
/// The view is only a window onto the page: the page keeps its engine when
/// the view goes away, so a tab can be hidden and shown again without
/// reloading.
///
/// The View conformance lives on the struct itself, with the platform split
/// inside `body`, as in Skip's samples: Skip's Android bridge didn't render a
/// view whose conformance came from a platform-specific extension.
struct ZenWebView: View {
    let page: WebPage

    var body: some View {
        #if os(Android)
        ComposeView {
            // Reading canGoBack here recomposes when it changes, which keeps
            // the system back button in step with the page's history.
            GeckoContentComposer(tab: page.geckoTab, canGoBack: page.canGoBack, isFullScreen: page.isFullScreen)
        }
        #elseif canImport(UIKit)
        WebKitView(webView: page.webView)
        #else
        Text("Web content is not available on this platform.")
        #endif
    }
}

#if !os(Android) && canImport(UIKit)

/// Puts a page's existing WKWebView on screen.
struct WebKitView: UIViewRepresentable {
    let webView: WKWebView

    func makeUIView(context: Context) -> WKWebView {
        webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
    }
}

#endif

#if SKIP
// Kotlin side (transpiled by Skip). GeckoView needs one GeckoRuntime per
// process and one GeckoSession per tab. The Android end-to-end test
// (Redroid in CI) loads pages through this.
import androidx.activity.compose.BackHandler
import androidx.compose.ui.viewinterop.AndroidView
import org.mozilla.geckoview.AllowOrDeny
import org.mozilla.geckoview.ContentBlocking
import org.mozilla.geckoview.GeckoResult
import org.mozilla.geckoview.GeckoRuntime
import org.mozilla.geckoview.GeckoRuntimeSettings
import org.mozilla.geckoview.GeckoSession
import org.mozilla.geckoview.GeckoSessionSettings
import org.mozilla.geckoview.GeckoView

/// Connects Gecko's login manager to the app's saved passwords
/// (GeckoLogins.kt). Public so Kotlin doesn't rename it on the JVM.
struct GeckoLogins {
    public static func connect(fetch: @escaping (String) -> String, save: @escaping (String) -> Void, used: @escaping (String) -> Void) {
        GeckoLoginStorage.fetch = fetch
        GeckoLoginStorage.save = save
        GeckoLoginStorage.used = used
    }
}

final class ZenGeckoRuntime {
    // SKIP @nobridge
    static var shared: GeckoRuntime? = nil

    // SKIP @nobridge
    static func get(_ context: android.content.Context) -> GeckoRuntime {
        if let runtime = shared {
            return runtime
        }
        let settings = GeckoRuntimeSettings.Builder()
            .contentBlocking(ContentBlocking.Settings.Builder()
                .antiTracking(trackingProtection)
                .enhancedTrackingProtectionLevel(etpLevel)
                .build())
            // A single saved login fills its form as the page loads.
            .loginAutofillEnabled(true)
            .build()
        let runtime = GeckoRuntime.create(context.applicationContext, settings)
        shared = runtime
        GeckoLoginStorage.attach(runtime)
        GeckoAdBlocking.apply(runtime)
        return runtime
    }

    /// Applies the content blocking settings to the running runtime.
    // SKIP @nobridge
    static func applyContentBlocking() {
        guard let runtime = shared else { return }
        runtime.settings.contentBlocking.setAntiTracking(trackingProtection)
        runtime.settings.contentBlocking.setEnhancedTrackingProtectionLevel(etpLevel)
        GeckoAdBlocking.apply(runtime)
    }

    // Firefox's standard protection (trackers, social, cryptominers,
    // fingerprinters), or none.
    private static var trackingProtection: Int {
        GeckoContentBlocking.trackers ? ContentBlocking.AntiTracking.DEFAULT : ContentBlocking.AntiTracking.NONE
    }

    private static var etpLevel: Int {
        GeckoContentBlocking.trackers ? ContentBlocking.EtpLevel.DEFAULT : ContentBlocking.EtpLevel.NONE
    }
}

/// A tab's GeckoSession. It outlives the GeckoView showing it: the view is
/// created when the tab is shown and lets go of the session when hidden.
final class GeckoTab {
    private let session: GeckoSession
    private let delegate: ZenGeckoDelegate
    /// Dialogs, permission requests and file pickers (GeckoPrompts.kt).
    // SKIP @nobridge
    let prompts: GeckoPrompts
    /// What to load when the session first opens.
    private var initialURL: URL
    /// The view showing the session, if any. A session can only be in one
    /// view at a time.
    private var view: GeckoView? = nil

    // The methods Swift calls are public: Kotlin renames internal methods
    // on the JVM (load → load$ZenMobile), and Skip's generated bridge looks
    // them up by their Swift names.

    // Explicit so the generated Swift bridge marks the closures @escaping.
    init(url: URL, isPrivate: Bool, shouldCancel: @escaping (URL) -> Bool, onLocationChange: @escaping (URL) -> Void, onTitleChange: @escaping (String?) -> Void, onHistoryChange: @escaping (Bool, Bool) -> Void, onProgressChange: @escaping (Int, Bool) -> Void, onSecurityChange: @escaping (Bool) -> Void, onOpenWindow: @escaping (URL) -> Void, onPrompt: @escaping (Int, String, String, String?) -> Void, downloadsDirectory: String, onDownload: @escaping (String, Int, Int) -> Void, usesLogins: Bool, onFullScreen: @escaping (Bool) -> Void, onContextMenu: @escaping (String?, String?, Int) -> Void) {
        initialURL = url
        // Private mode keeps the session's cookies, storage and cache in
        // memory, apart from normal tabs.
        session = GeckoSession(GeckoSessionSettings.Builder().usePrivateMode(isPrivate).build())
        delegate = ZenGeckoDelegate(shouldCancel: shouldCancel, locationChanged: onLocationChange, titleChanged: onTitleChange, historyChanged: onHistoryChange, progressChanged: onProgressChange, securityChanged: onSecurityChange, openWindow: onOpenWindow, downloadsDirectory: downloadsDirectory, downloadReported: onDownload, fullScreenChanged: onFullScreen, contextMenu: onContextMenu)
        session.navigationDelegate = delegate
        session.contentDelegate = delegate
        session.historyDelegate = delegate
        session.progressDelegate = delegate
        prompts = GeckoPrompts(onPrompt, usesLogins)
        session.promptDelegate = prompts
        session.permissionDelegate = prompts
    }

    public func load(url: URL) {
        if session.isOpen {
            session.loadUri(url.absoluteString)
        } else {
            initialURL = url
        }
    }

    public func goBack() {
        session.goBack()
    }

    public func goForward() {
        session.goForward()
    }

    public func reload() {
        session.reload()
    }

    public func stop() {
        session.stop()
    }

    /// Finds `text`, selecting the next match (or the previous); `onResult`
    /// gets whether it was found and which match of how many.
    public func find(text: String, backwards: Bool, onResult: @escaping (Bool, Int, Int) -> Void) {
        GeckoFind.find(session, text, backwards, onResult)
    }

    public func clearFind() {
        session.finder.clear()
    }

    /// The user's answer to the dialog or permission request `id`.
    public func answerPrompt(id: Int, accepted: Bool, text: String?) {
        prompts.answer(id, accepted, text)
    }

    public func close() {
        session.close()
    }

    public func exitFullScreen() {
        session.exitFullScreen()
    }

    /// Asks sites for their desktop layout (a desktop user agent and
    /// viewport), or the mobile one, and reloads.
    public func setDesktopMode(desktop: Bool) {
        session.settings.userAgentMode = desktop ? GeckoSessionSettings.USER_AGENT_MODE_DESKTOP : GeckoSessionSettings.USER_AGENT_MODE_MOBILE
        session.settings.viewportMode = desktop ? GeckoSessionSettings.VIEWPORT_MODE_DESKTOP : GeckoSessionSettings.VIEWPORT_MODE_MOBILE
        if session.isOpen {
            session.reload()
        }
    }

    /// Saves `url` (an image) to Downloads.
    public func download(url: URL) {
        guard let runtime = ZenGeckoRuntime.shared, !delegate.downloadsDirectory.isEmpty else { return }
        GeckoDownloads.fetch(runtime, url.absoluteString, java.io.File(delegate.downloadsDirectory), delegate.downloadReported)
    }

    /// Shows the session in `view`, opening it (and loading the first page)
    /// the first time.
    // SKIP @nobridge
    func attach(to view: GeckoView) {
        if !session.isOpen {
            session.open(ZenGeckoRuntime.get(view.context))
            session.loadUri(initialURL.absoluteString)
        }
        if let shown = self.view, shown !== view {
            shown.releaseSession()
        }
        self.view = view
        session.setActive(true)
        view.setSession(session)
    }

    /// Lets go of the session so another view can show it later.
    // SKIP @nobridge
    func detach(from view: GeckoView) {
        guard self.view === view else {
            return
        }
        self.view = nil
        session.setActive(false)
        view.releaseSession()
    }
}

private final class ZenGeckoDelegate: GeckoSession.NavigationDelegate, GeckoSession.ContentDelegate, GeckoSession.HistoryDelegate, GeckoSession.ProgressDelegate {
    // Named apart from the delegate methods below, which Kotlin would
    // otherwise confuse with them.
    let shouldCancel: (URL) -> Bool
    let locationChanged: (URL) -> Void
    let titleChanged: (String?) -> Void
    let historyChanged: (Bool, Bool) -> Void
    let progressChanged: (Int, Bool) -> Void
    let securityChanged: (Bool) -> Void
    let openWindow: (URL) -> Void
    let downloadsDirectory: String
    let downloadReported: (String, Int, Int) -> Void
    let fullScreenChanged: (Bool) -> Void
    let contextMenu: (String?, String?, Int) -> Void
    var canGoBack = false
    var canGoForward = false
    var progress = 0
    var isLoading = false

    init(shouldCancel: @escaping (URL) -> Bool, locationChanged: @escaping (URL) -> Void, titleChanged: @escaping (String?) -> Void, historyChanged: @escaping (Bool, Bool) -> Void, progressChanged: @escaping (Int, Bool) -> Void, securityChanged: @escaping (Bool) -> Void, openWindow: @escaping (URL) -> Void, downloadsDirectory: String, downloadReported: @escaping (String, Int, Int) -> Void, fullScreenChanged: @escaping (Bool) -> Void, contextMenu: @escaping (String?, String?, Int) -> Void) {
        self.shouldCancel = shouldCancel
        self.locationChanged = locationChanged
        self.titleChanged = titleChanged
        self.historyChanged = historyChanged
        self.progressChanged = progressChanged
        self.securityChanged = securityChanged
        self.openWindow = openWindow
        self.downloadsDirectory = downloadsDirectory
        self.downloadReported = downloadReported
        self.fullScreenChanged = fullScreenChanged
        self.contextMenu = contextMenu
    }

    override func onFullScreen(session: GeckoSession, fullScreen: Bool) {
        fullScreenChanged(fullScreen)
    }

    // A long press: the link and/or media under the finger, and the media's
    // type (ContextElement.TYPE_IMAGE is 1).
    override func onContextMenu(session: GeckoSession, screenX: Int, screenY: Int, element: GeckoSession.ContentDelegate.ContextElement) {
        if element.linkUri != nil || element.srcUri != nil {
            contextMenu(element.linkUri, element.srcUri, element.type)
        }
    }

    // What Gecko can't show (a file to download, a link with download):
    // save it to the Downloads folder (GeckoDownloads.kt).
    override func onExternalResponse(session: GeckoSession, response: org.mozilla.geckoview.WebResponse) {
        if downloadsDirectory.isEmpty {
            response.body?.close()
            return
        }
        GeckoDownloads.save(response, java.io.File(downloadsDirectory), downloadReported)
    }

    /// What Gecko shows itself; any other scheme belongs to another app.
    private static let webSchemes: Set<String> = ["http", "https", "about", "data", "blob", "file", "javascript", "view-source", "moz-extension", "resource"]

    override func onLoadRequest(session: GeckoSession, request: GeckoSession.NavigationDelegate.LoadRequest) -> GeckoResult<AllowOrDeny>? {
        // Links for other apps (tel:, mailto:, intent:, ...) open them, when
        // the user tapped one: pages don't get to launch apps by themselves.
        let scheme = (request.uri.components(separatedBy: ":").first ?? "").lowercased()
        if !Self.webSchemes.contains(scheme) {
            if request.hasUserGesture, let fallback = ExternalApps.open(ProcessInfo.processInfo.androidContext, request.uri) {
                session.loadUri(fallback)
            }
            return GeckoResult.fromValue(AllowOrDeny.DENY)
        }
        guard let url = URL(string: request.uri) else {
            return GeckoResult.fromValue(AllowOrDeny.ALLOW)
        }
        if shouldCancel(url) {
            return GeckoResult.fromValue(AllowOrDeny.DENY)
        }
        // A target=_blank link or window.open: open it as a new tab instead.
        if request.target == GeckoSession.NavigationDelegate.TARGET_WINDOW_NEW {
            openWindow(url)
            return GeckoResult.fromValue(AllowOrDeny.DENY)
        }
        return GeckoResult.fromValue(AllowOrDeny.ALLOW)
    }

    override func onPageStart(session: GeckoSession, url: String) {
        progress = 0
        isLoading = true
        progressChanged(progress, isLoading)
    }

    override func onProgressChange(session: GeckoSession, progress: Int) {
        self.progress = progress
        progressChanged(progress, isLoading)
    }

    override func onPageStop(session: GeckoSession, success: Bool) {
        isLoading = false
        progressChanged(progress, isLoading)
    }

    override func onSecurityChange(session: GeckoSession, securityInfo: GeckoSession.ProgressDelegate.SecurityInformation) {
        securityChanged(securityInfo.isSecure)
    }

    override func onLocationChange(session: GeckoSession, url: String?, perms: kotlin.collections.List<GeckoSession.PermissionDelegate.ContentPermission>, hasUserGesture: Bool) {
        if let url, let location = URL(string: url) {
            locationChanged(location)
        }
    }

    override func onCanGoBack(session: GeckoSession, canGoBack: Bool) {
        self.canGoBack = canGoBack
        historyChanged(canGoBack, canGoForward)
    }

    override func onCanGoForward(session: GeckoSession, canGoForward: Bool) {
        self.canGoForward = canGoForward
        historyChanged(canGoBack, canGoForward)
    }

    override func onTitleChange(session: GeckoSession, title: String?) {
        titleChanged(title)
    }

    // Back and forward restore pages from Gecko's cache without another
    // onTitleChange, so take the title from the history entry we're on.
    override func onHistoryStateChange(session: GeckoSession, historyList: GeckoSession.HistoryDelegate.HistoryList) {
        let index = historyList.currentIndex
        if index >= 0 && index < historyList.size {
            titleChanged(historyList.get(index).title)
        }
    }
}

struct GeckoContentComposer : ContentComposer {
    let tab: GeckoTab
    let canGoBack: Bool
    let isFullScreen: Bool

    init(tab: GeckoTab, canGoBack: Bool, isFullScreen: Bool) {
        self.tab = tab
        self.canGoBack = canGoBack
        self.isFullScreen = isFullScreen
    }

    @Composable func Compose(context: ComposeContext) {
        // The system back button goes back in the page while it can, and
        // otherwise does what it normally does; in full screen it leaves
        // full screen first.
        BackHandler(enabled: canGoBack && !isFullScreen) {
            tab.goBack()
        }
        BackHandler(enabled: isFullScreen) {
            tab.exitFullScreen()
        }
        FullScreenEffect(isFullScreen)
        GeckoPromptEffects(tab.prompts)
        AndroidView(factory: { ctx in
            let view = GeckoView(ctx)
            tab.attach(to: view)
            return view
        }, modifier: context.modifier, update: { view in
        }, onRelease: { view in
            tab.detach(from: view)
        })
    }
}
#endif
