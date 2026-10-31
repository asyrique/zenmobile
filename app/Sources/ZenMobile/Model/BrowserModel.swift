import Foundation
import Observation
// Skip Fuse bridges @Observable to Compose only in files that import it;
// without this the Android UI never sees tabs open.
import SkipFuse

/// The phone's own tabs, saved so they survive a restart.
@MainActor @Observable final class BrowserModel {
    struct Tab: Identifiable {
        let id = UUID()
        /// The live page; it keeps the tab's history while the tab is open.
        let page: WebPage
        /// Set when the tab was opened from a desktop pin or Essential, so
        /// tapping the same pin again returns here instead of opening a new tab.
        var zenTabId: String?

        @MainActor var url: URL { page.url }

        @MainActor var isPrivate: Bool { page.isPrivate }

        @MainActor var title: String {
            page.title.isEmpty ? (page.url.host ?? page.url.absoluteString) : page.title
        }
    }

    private(set) var tabs: [Tab] = []
    var selectedTabId: UUID? {
        didSet { save() }
    }

    var selectedTab: Tab? {
        tabs.first { $0.id == selectedTabId }
    }

    /// Where the open tabs are saved; nil keeps them in memory only.
    @ObservationIgnored private let storeURL: URL?
    /// Where pages' downloads go.
    @ObservationIgnored private let downloads: Downloads?
    /// History, which pages in normal tabs add to.
    @ObservationIgnored private let places: Places?

    init(storeURL: URL? = nil, downloads: Downloads? = nil, places: Places? = nil) {
        self.storeURL = storeURL
        self.downloads = downloads
        self.places = places
        restore()
    }

    func open(_ url: URL, title: String = "", zenTabId: String? = nil, isPrivate: Bool = false) {
        if let zenTabId, let existing = tabs.first(where: { $0.zenTabId == zenTabId }) {
            selectedTabId = existing.id
            return
        }
        let tab = Tab(page: makePage(url: url, title: title, isPrivate: isPrivate), zenTabId: zenTabId)
        tabs.append(tab)
        selectedTabId = tab.id
    }

    // MARK: Tabs from other devices

    /// What arrived from other devices, until shown or dismissed.
    private(set) var receivedNotice: String?
    @ObservationIgnored private var lastReceivedTabId: UUID?

    /// Adds tabs another device sent, in the background, with a notice.
    func receive(_ received: [AppModel.ReceivedTab]) {
        for item in received {
            let tab = Tab(page: makePage(url: item.url, title: item.title), zenTabId: nil)
            tabs.append(tab)
            lastReceivedTabId = tab.id
        }
        save()
        let sender = received.last?.sender ?? "another device"
        receivedNotice = received.count == 1 ? "Tab from \(sender)" : "\(received.count) tabs from \(sender)"
    }

    func showReceived() {
        if let id = lastReceivedTabId, tabs.contains(where: { $0.id == id }) {
            selectedTabId = id
        }
        receivedNotice = nil
    }

    func dismissReceivedNotice() {
        receivedNotice = nil
    }

    /// Closes the tabs another device asked to close here.
    func closeTabs(at urls: [URL]) {
        for tab in tabs where urls.contains(tab.url) {
            close(tab.id)
        }
    }

    func close(_ id: UUID) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        tabs[index].page.close()
        tabs.remove(at: index)
        if selectedTabId == id {
            selectedTabId = tabs.isEmpty ? nil : tabs[max(0, index - 1)].id
        } else {
            save()
        }
    }

    private func makePage(url: URL, title: String, isPrivate: Bool = false) -> WebPage {
        let page = WebPage(url: url, title: title, isPrivate: isPrivate)
        page.downloads = downloads
        // Pages change as the user browses; save each change, so a tab
        // reopens where it was even if the app is killed.
        page.onChange = { [weak self] in self?.save() }
        // Windows a private page opens are private too.
        page.onOpenWindow = { [weak self] url in self?.open(url, isPrivate: isPrivate) }
        // Private pages leave no history.
        if !isPrivate, let places {
            page.onVisit = { [weak places] url in places?.recordVisit(url, title: nil) }
            page.onTitle = { [weak places] title, url in places?.recordTitle(title, for: url) }
        }
        return page
    }

    // MARK: Saving

    private struct SavedTab: Codable {
        var url: URL
        var title: String
        var zenTabId: String?
    }

    private struct SavedTabs: Codable {
        var tabs: [SavedTab]
        var selected: Int?
    }

    private func save() {
        guard let storeURL else { return }
        let kept = tabs.filter { !$0.isPrivate }
        let saved = SavedTabs(
            tabs: kept.map { SavedTab(url: $0.url, title: $0.page.title, zenTabId: $0.zenTabId) },
            selected: kept.firstIndex { $0.id == selectedTabId })
        do {
            try JSONEncoder().encode(saved).write(to: storeURL, options: .atomic)
        } catch {
            logger.error("Saving tabs failed: \(error)")
        }
    }

    private func restore() {
        guard let storeURL, let data = try? Data(contentsOf: storeURL) else { return }
        guard let saved = try? JSONDecoder().decode(SavedTabs.self, from: data) else {
            logger.error("Saved tabs are unreadable; starting with none")
            return
        }
        // Restored pages load when first shown.
        tabs = saved.tabs.map { Tab(page: makePage(url: $0.url, title: $0.title), zenTabId: $0.zenTabId) }
        selectedTabId = saved.selected.flatMap { tabs.indices.contains($0) ? tabs[$0].id : nil }
    }

    // MARK: Input

    /// Turns what the user typed into a URL: a URL if it looks like one,
    /// otherwise a search.
    static func url(forInput input: String) -> URL? {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        if text.contains("://"), let url = URL(string: text) {
            return url
        }
        if !text.contains(" "), text.contains("."), let url = URL(string: "https://\(text)") {
            return url
        }
        var components = URLComponents(string: "https://duckduckgo.com/")!
        components.queryItems = [URLQueryItem(name: "q", value: text)]
        return components.url
    }
}
