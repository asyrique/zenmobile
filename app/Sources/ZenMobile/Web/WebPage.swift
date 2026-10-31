import Foundation
import Observation
// Skip Fuse bridges @Observable to Compose only in files that import it.
import SkipFuse
#if canImport(WebKit)
import WebKit
#endif

/// Something a page asks the user: a JavaScript dialog or a permission.
struct PagePrompt: Identifiable {
    enum Kind: String {
        /// alert(): a message and OK.
        case alert
        /// confirm(): OK or Cancel.
        case confirm
        /// prompt(): a line of text.
        case text
        /// A site permission (camera, microphone, location, notifications):
        /// Allow or Block.
        case permission
    }

    let id: Int
    let kind: Kind
    let message: String
    var defaultText = ""
}

/// The find bar's latest result.
struct FindResult: Equatable {
    let found: Bool
    /// Which match is selected, of how many; 0 when the engine doesn't say
    /// (WebKit only reports whether there's a match).
    let current: Int
    let total: Int
}

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
    private(set) var isLoading = false
    /// How far the current load is, from 0 to 1.
    private(set) var progress = 0.0
    /// Whether the page and everything on it came over a secure connection.
    private(set) var isSecure = false
    /// What the page is asking the user, if anything.
    private(set) var prompt: PagePrompt?
    /// The result of the last find in page; nil when not finding.
    private(set) var findResult: FindResult?

    /// A private page keeps nothing (cookies, storage, cache) once closed,
    /// and its tab isn't saved.
    let isPrivate: Bool
    /// Sees every main-frame navigation before it starts; return true to
    /// stop it. The sign-in view uses it to catch the OAuth redirect.
    let shouldCancel: (URL) -> Bool
    /// Called when the URL or title changes, for saving the tab.
    @ObservationIgnored var onChange: (() -> Void)?
    /// Called when the page goes to a new URL, and when its title changes,
    /// for history.
    @ObservationIgnored var onVisit: ((URL) -> Void)?
    @ObservationIgnored var onTitle: ((String, URL) -> Void)?
    /// Called when the page opens a new window (a target=_blank link,
    /// window.open); the browser opens it as a new tab.
    @ObservationIgnored var onOpenWindow: ((URL) -> Void)?
    /// Where the page's downloads go; nil turns downloads away (the
    /// sign-in page).
    @ObservationIgnored var downloads: Downloads?
    @ObservationIgnored private var promptAnswer: ((Bool, String?) -> Void)?
    @ObservationIgnored private var promptCount = 0
    /// Whether the page has reported a location yet; its first one is a
    /// visit even when it's the URL the tab was opened with.
    @ObservationIgnored private var visited = false

    init(url: URL, title: String = "", isPrivate: Bool = false, shouldCancel: @escaping (URL) -> Bool = { _ in false }) {
        self.url = url
        self.title = title
        self.isPrivate = isPrivate
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

    func stop() {
        #if os(Android)
        gecko?.stop()
        #elseif canImport(UIKit)
        webKit?.webView.stopLoading()
        #endif
    }

    /// Finds `text` in the page and selects the next match (or the previous
    /// one, `backwards`), wrapping around. An empty text clears the find.
    func find(_ text: String, backwards: Bool = false) {
        guard !text.isEmpty else {
            endFind()
            return
        }
        #if os(Android)
        gecko?.find(text: text, backwards: backwards) { [weak self] found, current, total in
            self?.findResult = FindResult(found: found, current: current, total: total)
        }
        #elseif canImport(UIKit)
        guard let webView = webKit?.webView else { return }
        let configuration = WKFindConfiguration()
        configuration.backwards = backwards
        configuration.wraps = true
        Task {
            let result = try? await webView.find(text, configuration: configuration)
            findResult = FindResult(found: result?.matchFound ?? false, current: 0, total: 0)
        }
        #endif
    }

    func endFind() {
        findResult = nil
        #if os(Android)
        gecko?.clearFind()
        #elseif canImport(UIKit)
        webKit?.webView.evaluateJavaScript("window.getSelection().removeAllRanges()")
        #endif
    }

    /// Answers the page's prompt: whether the user accepted (OK, Allow) and,
    /// for a text prompt, what they typed.
    func answerPrompt(accepted: Bool, text: String? = nil) {
        let answer = promptAnswer
        prompt = nil
        promptAnswer = nil
        answer?(accepted, text)
    }

    /// Ends the page for good when its tab closes.
    func close() {
        answerPrompt(accepted: false)
        #if os(Android)
        gecko?.close()
        gecko = nil
        #elseif canImport(UIKit)
        webKit = nil
        #endif
    }

    // MARK: Engine callbacks

    fileprivate func didChange(url: URL) {
        guard url != self.url || !visited else { return }
        self.url = url
        visited = true
        onChange?()
        onVisit?(url)
    }

    fileprivate func didChange(title: String?) {
        guard let title, !title.isEmpty, title != self.title else { return }
        self.title = title
        onChange?()
        onTitle?(title, url)
    }

    // Engines report these often, mostly unchanged; an @Observable property
    // notifies on every assignment, so only assign changes (each one
    // re-renders the navigation bar).

    fileprivate func didChange(canGoBack: Bool, canGoForward: Bool) {
        if canGoBack != self.canGoBack { self.canGoBack = canGoBack }
        if canGoForward != self.canGoForward { self.canGoForward = canGoForward }
    }

    fileprivate func didChange(progress: Double, isLoading: Bool) {
        if progress != self.progress { self.progress = progress }
        if isLoading != self.isLoading { self.isLoading = isLoading }
    }

    fileprivate func didChange(isSecure: Bool) {
        if isSecure != self.isSecure { self.isSecure = isSecure }
    }

    fileprivate func openWindow(_ url: URL) {
        onOpenWindow?(url)
    }

    /// Shows a prompt; `answer` gets the user's reply. One at a time: asking
    /// again before the first is answered dismisses the first.
    fileprivate func ask(_ kind: PagePrompt.Kind, message: String, defaultText: String = "", answer: @escaping (Bool, String?) -> Void) {
        answerPrompt(accepted: false)
        promptCount += 1
        prompt = PagePrompt(id: promptCount, kind: kind, message: message, defaultText: defaultText)
        promptAnswer = answer
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
            isPrivate: isPrivate,
            shouldCancel: { [weak self] url in self?.shouldCancel(url) ?? false },
            onLocationChange: { [weak self] url in self?.didChange(url: url) },
            onTitleChange: { [weak self] title in self?.didChange(title: title) },
            onHistoryChange: { [weak self] back, forward in self?.didChange(canGoBack: back, canGoForward: forward) },
            onProgressChange: { [weak self] percent, loading in self?.didChange(progress: Double(percent) / 100, isLoading: loading) },
            onSecurityChange: { [weak self] secure in self?.didChange(isSecure: secure) },
            onOpenWindow: { [weak self] url in self?.openWindow(url) },
            onPrompt: { [weak self] id, kind, message, defaultText in
                self?.ask(PagePrompt.Kind(rawValue: kind) ?? .alert, message: message, defaultText: defaultText ?? "") { [weak self] accepted, text in
                    self?.gecko?.answerPrompt(id: id, accepted: accepted, text: text)
                }
            },
            downloadsDirectory: downloads?.directory.path ?? "",
            onDownload: { [weak self] name, percent, state in
                // state: 0 running, 1 done, 2 failed; percent -1 if unknown.
                if state != 0 {
                    self?.downloads?.finished(name)
                } else if percent < 0 {
                    self?.downloads?.started(name)
                } else {
                    self?.downloads?.update(name, progress: Double(percent) / 100)
                }
            })
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

/// A page's WKWebView and its delegates.
@MainActor private final class WebKitEngine: NSObject, WKNavigationDelegate, WKUIDelegate, WKDownloadDelegate {
    /// Private pages share one in-memory store, gone when the app quits.
    private static let privateDataStore = WKWebsiteDataStore.nonPersistent()

    let webView: WKWebView
    private weak var page: WebPage?
    private var observations: [NSKeyValueObservation] = []
    /// The file each download in progress is going to, and what watches its
    /// progress.
    private var downloadNames: [ObjectIdentifier: String] = [:]
    private var downloadProgress: [ObjectIdentifier: NSKeyValueObservation] = [:]

    init(page: WebPage) {
        self.page = page
        let configuration = WKWebViewConfiguration()
        if page.isPrivate {
            configuration.websiteDataStore = Self.privateDataStore
        }
        if let trackers = ContentBlocker.shared.ruleList {
            configuration.userContentController.add(trackers)
        }
        webView = WKWebView(frame: .zero, configuration: configuration)
        super.init()
        // The tracker list arrives after launch, and the setting can change.
        NotificationCenter.default.addObserver(self, selector: #selector(trackerRulesChanged), name: ContentBlocker.didChange, object: nil)
        webView.navigationDelegate = self
        webView.uiDelegate = self
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
            webView.observe(\.estimatedProgress) { [weak self] webView, _ in
                MainActor.assumeIsolated { self?.reportProgress(webView) }
            },
            webView.observe(\.isLoading) { [weak self] webView, _ in
                MainActor.assumeIsolated { self?.reportProgress(webView) }
            },
            webView.observe(\.hasOnlySecureContent) { [weak self] webView, _ in
                MainActor.assumeIsolated { self?.page?.didChange(isSecure: webView.hasOnlySecureContent) }
            },
        ]
    }

    @objc private func trackerRulesChanged() {
        let rules = webView.configuration.userContentController
        rules.removeAllContentRuleLists()
        if let trackers = ContentBlocker.shared.ruleList {
            rules.add(trackers)
        }
    }

    private func reportHistory(_ webView: WKWebView) {
        page?.didChange(canGoBack: webView.canGoBack, canGoForward: webView.canGoForward)
    }

    private func reportProgress(_ webView: WKWebView) {
        page?.didChange(progress: webView.estimatedProgress, isLoading: webView.isLoading)
    }

    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction) async -> WKNavigationActionPolicy {
        if action.targetFrame?.isMainFrame != false, let url = action.request.url, page?.shouldCancel(url) == true {
            return .cancel
        }
        // A link with the download attribute.
        if action.shouldPerformDownload {
            return page?.downloads == nil ? .cancel : .download
        }
        return .allow
    }

    // What WebKit can't show, or a server says is an attachment, downloads.
    func webView(_ webView: WKWebView, decidePolicyFor response: WKNavigationResponse) async -> WKNavigationResponsePolicy {
        let disposition = (response.response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Content-Disposition") ?? ""
        guard !response.canShowMIMEType || disposition.lowercased().hasPrefix("attachment") else {
            return .allow
        }
        return page?.downloads == nil ? .cancel : .download
    }

    func webView(_ webView: WKWebView, navigationAction: WKNavigationAction, didBecome download: WKDownload) {
        download.delegate = self
    }

    func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse, didBecome download: WKDownload) {
        download.delegate = self
    }

    // MARK: Downloads (to the Downloads folder in Documents)

    func download(_ download: WKDownload, decideDestinationUsing response: URLResponse, suggestedFilename: String) async -> URL? {
        guard let downloads = page?.downloads else { return nil }
        let destination = downloads.destination(for: suggestedFilename)
        let name = destination.lastPathComponent
        downloadNames[ObjectIdentifier(download)] = name
        downloads.started(name)
        downloadProgress[ObjectIdentifier(download)] = download.progress.observe(\.fractionCompleted) { [weak downloads] progress, _ in
            let fraction = progress.fractionCompleted
            Task { @MainActor in downloads?.update(name, progress: fraction) }
        }
        return destination
    }

    func downloadDidFinish(_ download: WKDownload) {
        finish(download)
    }

    func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
        logger.error("Download failed: \(error)")
        finish(download)
    }

    private func finish(_ download: WKDownload) {
        downloadProgress.removeValue(forKey: ObjectIdentifier(download))
        if let name = downloadNames.removeValue(forKey: ObjectIdentifier(download)) {
            page?.downloads?.finished(name)
        }
    }

    // JavaScript dialogs. Camera, microphone and location requests use
    // WebKit's own prompts (and the usage descriptions in Info.plist).

    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo) async {
        _ = await ask(.alert, message)
    }

    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo) async -> Bool {
        await ask(.confirm, message).accepted
    }

    func webView(_ webView: WKWebView, runJavaScriptTextInputPanelWithPrompt prompt: String, defaultText: String?, initiatedByFrame frame: WKFrameInfo) async -> String? {
        let answer = await ask(.text, prompt, defaultText: defaultText ?? "")
        return answer.accepted ? (answer.text ?? "") : nil
    }

    private func ask(_ kind: PagePrompt.Kind, _ message: String, defaultText: String = "") async -> (accepted: Bool, text: String?) {
        guard let page else { return (false, nil) }
        return await withCheckedContinuation { continuation in
            page.ask(kind, message: message, defaultText: defaultText) { accepted, text in
                continuation.resume(returning: (accepted, text))
            }
        }
    }

    // A target=_blank link or window.open: open it as a new tab instead.
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for action: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let url = action.request.url {
            page?.openWindow(url)
        }
        return nil
    }
}

#endif
