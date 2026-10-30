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
            GeckoContentComposer(tab: page.geckoTab, canGoBack: page.canGoBack)
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
import org.mozilla.geckoview.GeckoResult
import org.mozilla.geckoview.GeckoRuntime
import org.mozilla.geckoview.GeckoSession
import org.mozilla.geckoview.GeckoView

private final class ZenGeckoRuntime {
    static var shared: GeckoRuntime? = nil

    static func get(_ context: android.content.Context) -> GeckoRuntime {
        if let runtime = shared {
            return runtime
        }
        let runtime = GeckoRuntime.create(context.applicationContext)
        shared = runtime
        return runtime
    }
}

/// A tab's GeckoSession. It outlives the GeckoView showing it: the view is
/// created when the tab is shown and lets go of the session when hidden.
final class GeckoTab {
    private let session: GeckoSession = GeckoSession()
    private let delegate: ZenGeckoDelegate
    /// What to load when the session first opens.
    private var initialURL: URL
    /// The view showing the session, if any. A session can only be in one
    /// view at a time.
    private var view: GeckoView? = nil

    // Explicit so the generated Swift bridge marks the closures @escaping.
    init(url: URL, shouldCancel: @escaping (URL) -> Bool, onLocationChange: @escaping (URL) -> Void, onTitleChange: @escaping (String?) -> Void, onHistoryChange: @escaping (Bool, Bool) -> Void) {
        initialURL = url
        delegate = ZenGeckoDelegate(shouldCancel: shouldCancel, locationChanged: onLocationChange, titleChanged: onTitleChange, historyChanged: onHistoryChange)
        session.navigationDelegate = delegate
        session.contentDelegate = delegate
    }

    func load(url: URL) {
        if session.isOpen {
            session.loadUri(url.absoluteString)
        } else {
            initialURL = url
        }
    }

    func goBack() {
        session.goBack()
    }

    func goForward() {
        session.goForward()
    }

    func reload() {
        session.reload()
    }

    func close() {
        session.close()
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

private final class ZenGeckoDelegate: GeckoSession.NavigationDelegate, GeckoSession.ContentDelegate {
    // Named apart from the delegate methods below, which Kotlin would
    // otherwise confuse with them.
    let shouldCancel: (URL) -> Bool
    let locationChanged: (URL) -> Void
    let titleChanged: (String?) -> Void
    let historyChanged: (Bool, Bool) -> Void
    var canGoBack = false
    var canGoForward = false

    init(shouldCancel: @escaping (URL) -> Bool, locationChanged: @escaping (URL) -> Void, titleChanged: @escaping (String?) -> Void, historyChanged: @escaping (Bool, Bool) -> Void) {
        self.shouldCancel = shouldCancel
        self.locationChanged = locationChanged
        self.titleChanged = titleChanged
        self.historyChanged = historyChanged
    }

    override func onLoadRequest(session: GeckoSession, request: GeckoSession.NavigationDelegate.LoadRequest) -> GeckoResult<AllowOrDeny>? {
        if let url = URL(string: request.uri), shouldCancel(url) {
            return GeckoResult.fromValue(AllowOrDeny.DENY)
        }
        return GeckoResult.fromValue(AllowOrDeny.ALLOW)
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
}

struct GeckoContentComposer : ContentComposer {
    let tab: GeckoTab
    let canGoBack: Bool

    init(tab: GeckoTab, canGoBack: Bool) {
        self.tab = tab
        self.canGoBack = canGoBack
    }

    @Composable func Compose(context: ComposeContext) {
        // The system back button goes back in the page while it can, and
        // otherwise does what it normally does.
        BackHandler(enabled: canGoBack) {
            tab.goBack()
        }
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
