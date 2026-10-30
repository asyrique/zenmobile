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
///
/// The View conformance lives on the struct itself, with the platform split
/// inside `body`, as in Skip's samples: Skip's Android bridge didn't render a
/// view whose conformance came from a platform-specific extension.
struct ZenWebView: View {
    let url: URL
    var shouldCancel: (URL) -> Bool = { _ in false }
    var didNavigate: (URL, String?) -> Void = { _, _ in }

    var body: some View {
        #if os(Android)
        ComposeView {
            GeckoContentComposer(url: url, shouldCancel: shouldCancel, didNavigate: didNavigate)
        }
        #elseif canImport(UIKit)
        WebKitView(url: url, shouldCancel: shouldCancel, didNavigate: didNavigate)
        #else
        Text("Web content is not available on this platform.")
        #endif
    }
}

#if !os(Android) && canImport(UIKit)

/// WKWebView for ZenWebView on iOS.
struct WebKitView: UIViewRepresentable {
    let url: URL
    let shouldCancel: (URL) -> Bool
    let didNavigate: (URL, String?) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
        webView.navigationDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        context.coordinator.observe(webView)
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

    @MainActor final class Coordinator: NSObject, WKNavigationDelegate {
        var parent: WebKitView
        /// The page the web view is on, so updateUIView only loads when the
        /// caller asks for a different one.
        var loadedURL: URL?
        private var observations: [NSKeyValueObservation] = []

        init(_ parent: WebKitView) {
            self.parent = parent
        }

        /// Reports title and URL changes. KVO also catches titles set after
        /// the load finishes and in-page navigations that never finish.
        func observe(_ webView: WKWebView) {
            // WebKit delivers these on the main thread.
            observations = [
                webView.observe(\.title) { [weak self] webView, _ in
                    MainActor.assumeIsolated { self?.report(webView) }
                },
                webView.observe(\.url) { [weak self] webView, _ in
                    MainActor.assumeIsolated { self?.report(webView) }
                },
            ]
        }

        private func report(_ webView: WKWebView) {
            guard let url = webView.url else { return }
            loadedURL = url
            parent.didNavigate(url, webView.title)
        }

        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction) async -> WKNavigationActionPolicy {
            if action.targetFrame?.isMainFrame != false, let url = action.request.url, parent.shouldCancel(url) {
                return .cancel
            }
            return .allow
        }
    }
}

#endif

#if SKIP
// Kotlin side (transpiled by Skip). GeckoView needs one GeckoRuntime per
// process and one GeckoSession per tab. The Android end-to-end test
// (Redroid in CI) loads a page through this.
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
            let view = GeckoView(ctx)
            do {
                let delegate = ZenNavigationDelegate(shouldCancel: shouldCancel, didNavigate: didNavigate)
                delegate.currentURL = url
                let session = GeckoSession()
                session.navigationDelegate = delegate
                session.contentDelegate = delegate
                session.open(ZenGeckoRuntime.get(ctx))
                view.setSession(session)
                session.loadUri(url.absoluteString)
            } catch {
                android.util.Log.e("ZenWebView", "GeckoView setup failed: \(error)")
            }
            return view
        }, modifier: context.modifier, update: { view in
        })
    }
}
#endif
