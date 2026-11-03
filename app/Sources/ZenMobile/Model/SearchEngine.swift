import Foundation

/// Where the address bar searches; chosen in Settings, DuckDuckGo by default.
enum SearchEngine: String, CaseIterable, Identifiable {
    case duckDuckGo
    case google
    case bing
    case startpage
    case ecosia
    case brave

    static let settingKey = "searchEngine"

    static var current: SearchEngine {
        UserDefaults.standard.string(forKey: settingKey).flatMap(SearchEngine.init(rawValue:)) ?? .duckDuckGo
    }

    var id: String { rawValue }

    var name: String {
        switch self {
        case .duckDuckGo: return "DuckDuckGo"
        case .google: return "Google"
        case .bing: return "Bing"
        case .startpage: return "Startpage"
        case .ecosia: return "Ecosia"
        case .brave: return "Brave Search"
        }
    }

    /// The search page, and the name of its query parameter.
    private var endpoint: (url: String, query: String) {
        switch self {
        case .duckDuckGo: return ("https://duckduckgo.com/", "q")
        case .google: return ("https://www.google.com/search", "q")
        case .bing: return ("https://www.bing.com/search", "q")
        case .startpage: return ("https://www.startpage.com/sp/search", "query")
        case .ecosia: return ("https://www.ecosia.org/search", "q")
        case .brave: return ("https://search.brave.com/search", "q")
        }
    }

    func url(searching text: String) -> URL? {
        var components = URLComponents(string: endpoint.url)
        components?.queryItems = [URLQueryItem(name: endpoint.query, value: text)]
        return components?.url
    }
}
