import Foundation
import SwiftUI
#if canImport(WebKit)
import WebKit
#endif

/// A web view, backed by WKWebView on iOS and GeckoView on Android.
///
/// `shouldCancel` sees every main-frame navigation before it starts; return
/// true to stop it (used to catch the OAuth redirect). `didNavigate` reports
/// the committed URL and the page title.
struct ZenWebView {
    let url: URL
    var shouldCancel: (URL) -> Bool = { _ in false }
    var didNavigate: (URL, String?) -> Void = { _, _ in }
}

#if os(Android)

extension ZenWebView: View {
    var body: some View {
        ComposeView {
            GeckoContentComposer(url: url, shouldCancel: shouldCancel, didNavigate: didNavigate)
        }
    }
}

#elseif canImport(UIKit)

extension ZenWebView: UIViewRepresentable {
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
        webView.navigationDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        webView.load(URLRequest(url: url))
        context.coordinator.loadedURL = url
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.parent = self
        // Only reload when the caller asked for a different page, not when
        // the page navigated by itself.
        if context.coordinator.loadedURL != url {
            context.coordinator.loadedURL = url
            webView.load(URLRequest(url: url))
        }
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var parent: ZenWebView
        var loadedURL: URL?

        init(_ parent: ZenWebView) {
            self.parent = parent
        }

        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                     decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void) {
            if action.targetFrame?.isMainFrame != false, let url = action.request.url, parent.shouldCancel(url) {
                decisionHandler(.cancel)
            } else {
                decisionHandler(.allow)
            }
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            if let url = webView.url {
                loadedURL = loadedURL ?? url
                parent.didNavigate(url, webView.title)
            }
        }
    }
}

#endif

#if SKIP
// Kotlin side (transpiled by Skip). GeckoView needs one GeckoRuntime per
// process and one GeckoSession per tab.
//
// PROTOTYPE (Roadmap M0): written against GeckoView 159's API but not yet
// built. What to check first on a Mac: that the closures cross the
// Swift↔Kotlin bridge, and the delegate override signatures.
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

private final class ZenNavigationDelegate: GeckoSession.NavigationDelegate, GeckoSession.ContentDelegate {
    let shouldCancel: (URL) -> Bool
    let didNavigate: (URL, String?) -> Void
    var currentURL: URL? = nil

    init(shouldCancel: @escaping (URL) -> Bool, didNavigate: @escaping (URL, String?) -> Void) {
        self.shouldCancel = shouldCancel
        self.didNavigate = didNavigate
    }

    override func onLoadRequest(session: GeckoSession, request: GeckoSession.NavigationDelegate.LoadRequest) -> GeckoResult<AllowOrDeny>? {
        if let url = URL(string: request.uri), shouldCancel(url) {
            return GeckoResult.fromValue(AllowOrDeny.DENY)
        }
        return GeckoResult.fromValue(AllowOrDeny.ALLOW)
    }

    override func onTitleChange(session: GeckoSession, title: String?) {
        if let url = currentURL {
            didNavigate(url, title)
        }
    }
}

struct GeckoContentComposer : ContentComposer {
    let url: URL
    let shouldCancel: (URL) -> Bool
    let didNavigate: (URL, String?) -> Void

    // Explicit so the generated Swift bridge marks the closures @escaping.
    init(url: URL, shouldCancel: @escaping (URL) -> Bool, didNavigate: @escaping (URL, String?) -> Void) {
        self.url = url
        self.shouldCancel = shouldCancel
        self.didNavigate = didNavigate
    }

    @Composable func Compose(context: ComposeContext) {
        AndroidView(factory: { ctx in
            let delegate = ZenNavigationDelegate(shouldCancel: shouldCancel, didNavigate: didNavigate)
            delegate.currentURL = url
            let session = GeckoSession()
            session.navigationDelegate = delegate
            session.contentDelegate = delegate
            session.open(ZenGeckoRuntime.get(ctx))
            let view = GeckoView(ctx)
            view.setSession(session)
            session.loadUri(url.absoluteString)
            return view
        }, modifier: context.modifier, update: { view in
        })
    }
}
#endif
