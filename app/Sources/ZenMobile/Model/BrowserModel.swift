import Foundation
import Observation

/// The phone's own tabs.
@MainActor @Observable final class BrowserModel {
    struct Tab: Identifiable, Equatable {
        let id = UUID()
        var url: URL
        var title: String
        /// Set when the tab was opened from a desktop pin or Essential, so
        /// tapping the same pin again returns here instead of opening a new tab.
        var zenTabId: String?
    }

    private(set) var tabs: [Tab] = []
    var selectedTabId: UUID?

    var selectedTab: Tab? {
        tabs.first { $0.id == selectedTabId }
    }

    func open(_ url: URL, title: String = "", zenTabId: String? = nil) {
        if let zenTabId, let existing = tabs.first(where: { $0.zenTabId == zenTabId }) {
            selectedTabId = existing.id
            return
        }
        let tab = Tab(url: url, title: title.isEmpty ? (url.host ?? url.absoluteString) : title, zenTabId: zenTabId)
        tabs.append(tab)
        selectedTabId = tab.id
    }

    func close(_ id: UUID) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        tabs.remove(at: index)
        if selectedTabId == id {
            selectedTabId = tabs.isEmpty ? nil : tabs[max(0, index - 1)].id
        }
    }

    func didNavigate(_ id: UUID, to url: URL, title: String?) {
        guard let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        tabs[index].url = url
        if let title, !title.isEmpty {
            tabs[index].title = title
        }
    }

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
