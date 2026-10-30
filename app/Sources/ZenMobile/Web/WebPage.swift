import Foundation
import Observation
// Skip Fuse bridges @Observable to Compose only in files that import it.
import SkipFuse
#if canImport(WebKit)
import WebKit
#endif

/// One tab's live web content.
///
/// It owns the engine (a WKWebView on iOS, a GeckoSession on Android) for as
/// long as the tab is open, so showing another tab and coming back keeps the
/// page, its scroll position and its history. The engine starts when the
/// page is first shown, so tabs restored at launch don't all load at once.
@MainActor @Observable final class WebPage {
    private(set) var url: URL
    private(set) var title: String
    private(set) var canGoBack = false
    private(set) var canGoForward = false

    /// Sees every main-frame navigation before it starts; return true to
    /// stop it. The sign-in view uses it to catch the OAuth redirect.
    let shouldCancel: (URL) -> Bool
    /// Called when the URL or title changes, for saving the tab.
    @ObservationIgnored var onChange: (() -> Void)?

    init(url: URL, title: String = "", shouldCancel: @escaping (URL) -> Bool = { _ in false }) {
        self.url = url
        self.title = title
        self.shouldCancel = shouldCancel
    }

    func load(_ url: URL) {
        self.url = url
        onChange?()
        #if os(Android)
        gecko?.load(url: url)
        #elseif canImport(UIKit)
        webKit?.webView.load(URLRequest(url: url))
        #endif
    }

    func goBack() {
        #if os(Android)
        gecko?.goBack()
        #elseif canImport(UIKit)
        webKit?.webView.goBack()
        #endif
    }

    func goForward() {
        #if os(Android)
        gecko?.goForward()
        #elseif canImport(UIKit)
        webKit?.webView.goForward()
        #endif
    }

    func reload() {
        #if os(Android)
        gecko?.reload()
        #elseif canImport(UIKit)
        webKit?.webView.reload()
        #endif
    }

    /// Ends the page for good when its tab closes.
    func close() {
        #if os(Android)
        gecko?.close()
        gecko = nil
        #elseif canImport(UIKit)
        webKit = nil
        #endif
    }

    // MARK: Engine callbacks

    fileprivate func didChange(url: URL) {
        guard url != self.url else { return }
        self.url = url
        onChange?()
    }

    fileprivate func didChange(title: String?) {
        guard let title, !title.isEmpty, title != self.title else { return }
        self.title = title
        onChange?()
    }

    fileprivate func didChange(canGoBack: Bool, canGoForward: Bool) {
        self.canGoBack = canGoBack
        self.canGoForward = canGoForward
    }

    // MARK: Engines

    #if os(Android)
    @ObservationIgnored private var gecko: GeckoTab?

    /// The tab's Gecko session (Kotlin side, see ZenWebView.swift).
    var geckoTab: GeckoTab {
        if let gecko {
            return gecko
        }
        let tab = GeckoTab(
            url: url,
            shouldCancel: { [weak self] url in self?.shouldCancel(url) ?? false },
            onLocationChange: { [weak self] url in self?.didChange(url: url) },
            onTitleChange: { [weak self] title in self?.didChange(title: title) },
            onHistoryChange: { [weak self] back, forward in self?.didChange(canGoBack: back, canGoForward: forward) })
        gecko = tab
        return tab
    }
    #elseif canImport(UIKit)
    @ObservationIgnored private var webKit: WebKitEngine?

    var webView: WKWebView {
        if let webKit {
            return webKit.webView
        }
        let engine = WebKitEngine(page: self)
        webKit = engine
        engine.webView.load(URLRequest(url: url))
        return engine.webView
    }
    #endif
}

#if !os(Android) && canImport(UIKit)

/// A page's WKWebView and its delegate.
@MainActor private final class WebKitEngine: NSObject, WKNavigationDelegate {
    let webView = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
    private weak var page: WebPage?
    private var observations: [NSKeyValueObservation] = []

    init(page: WebPage) {
        self.page = page
        super.init()
        webView.navigationDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        // KVO also catches titles set after the load finishes and in-page
        // navigations that never finish. WebKit delivers these on the main
        // thread.
        observations = [
            webView.observe(\.url) { [weak self] webView, _ in
                MainActor.assumeIsolated {
                    if let url = webView.url { self?.page?.didChange(url: url) }
                }
            },
            webView.observe(\.title) { [weak self] webView, _ in
                MainActor.assumeIsolated { self?.page?.didChange(title: webView.title) }
            },
            webView.observe(\.canGoBack) { [weak self] webView, _ in
                MainActor.assumeIsolated { self?.reportHistory(webView) }
            },
            webView.observe(\.canGoForward) { [weak self] webView, _ in
                MainActor.assumeIsolated { self?.reportHistory(webView) }
            },
        ]
    }

    private func reportHistory(_ webView: WKWebView) {
        page?.didChange(canGoBack: webView.canGoBack, canGoForward: webView.canGoForward)
    }

    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction) async -> WKNavigationActionPolicy {
        if action.targetFrame?.isMainFrame != false, let url = action.request.url, page?.shouldCancel(url) == true {
            return .cancel
        }
        return .allow
    }
}

#endif
