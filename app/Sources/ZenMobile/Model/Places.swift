import Foundation
import Observation
// Skip Fuse bridges @Observable to Compose only in files that import it.
import SkipFuse
import ZenCore

/// History and bookmarks, in application-services' Places database (the
/// same component Firefox's apps use). Once registered with sync, history
/// and bookmarks sync with Firefox and Zen desktop when signed in.
///
/// Database calls block, so they run off the main actor.
@MainActor @Observable final class Places {
    /// Firefox's bookmark roots.
    enum Root {
        static let all = "root________"
        static let menu = "menu________"
        static let toolbar = "toolbar_____"
        static let other = "unfiled_____"
        static let mobile = "mobile______"
    }

    struct Suggestion: Identifiable {
        let url: URL
        let title: String

        var id: URL { url }
    }

    struct Visit: Identifiable {
        let url: URL
        let title: String
        let date: Date

        var id: String { "\(date.timeIntervalSince1970) \(url)" }
    }

    /// A folder's contents, folders first as Firefox shows them.
    struct Folder {
        struct Bookmark: Identifiable {
            let guid: String
            let url: URL
            let title: String

            var id: String { guid }
        }

        struct Subfolder: Identifiable {
            let guid: String
            let title: String

            var id: String { guid }
        }

        let title: String
        var folders: [Subfolder] = []
        var bookmarks: [Bookmark] = []
    }

    /// Kept alive: sync finds Places through a weak reference to it.
    private let api: PlacesApi?
    private let connection: PlacesConnection?

    init(path: String) {
        do {
            let api = try placesApiNew(dbPath: path)
            api.registerWithSyncManager()
            connection = try api.newConnection(connType: .readWrite)
            self.api = api
        } catch {
            logger.error("Opening history and bookmarks failed: \(error)")
            api = nil
            connection = nil
        }
    }

    // MARK: History

    /// Records a visit to a web page (not for private tabs).
    func recordVisit(_ url: URL, title: String?) {
        guard Self.isWeb(url) else { return }
        write { try $0.applyObservation(visit: VisitObservation(url: url.absoluteString, title: title, visitType: .link)) }
    }

    /// Updates the title of a page already visited.
    func recordTitle(_ title: String, for url: URL) {
        guard Self.isWeb(url), !title.isEmpty else { return }
        write { try $0.applyObservation(visit: VisitObservation(url: url.absoluteString, title: title, visitType: nil)) }
    }

    /// The most recent visits, newest first.
    func recentVisits(limit: Int = 200) async -> [Visit] {
        let infos = await read { try $0.getVisitPage(offset: 0, count: Int64(limit), excludeTypes: 0) } ?? []
        return infos.compactMap { info in
            guard let url = URL(string: info.url) else { return nil }
            let title = info.title.flatMap { $0.isEmpty ? nil : $0 } ?? (url.host ?? info.url)
            return Visit(url: url, title: title, date: Date(timeIntervalSince1970: Double(info.timestamp) / 1000))
        }
    }

    func clearHistory() async {
        _ = await read { try $0.deleteEverythingHistory() }
    }

    /// Pages from history and bookmarks matching what's typed, best first.
    func suggestions(for text: String, limit: Int = 6) async -> [Suggestion] {
        let query = text.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return [] }
        let results = await read { try $0.queryAutocomplete(search: query, limit: Int32(limit)) } ?? []
        return results.compactMap { result in
            URL(string: result.url).map { Suggestion(url: $0, title: result.title.isEmpty ? result.url : result.title) }
        }
    }

    // MARK: Bookmarks

    func isBookmarked(_ url: URL) async -> Bool {
        let items = await read { try $0.bookmarksGetAllWithUrl(url: url.absoluteString) } ?? []
        return !items.isEmpty
    }

    /// Bookmarks the page in Mobile Bookmarks, or removes its bookmarks if
    /// it has any. Returns whether it's bookmarked now.
    func toggleBookmark(_ url: URL, title: String) async -> Bool {
        let address = url.absoluteString
        return await read { connection in
            let existing = try connection.bookmarksGetAllWithUrl(url: address)
            if existing.isEmpty {
                _ = try connection.bookmarksInsert(bookmark: .bookmark(b: InsertableBookmark(
                    parentGuid: Root.mobile, position: .append, url: address, title: title)))
                return true
            }
            for case let .bookmark(bookmark) in existing {
                _ = try connection.bookmarksDelete(id: bookmark.guid)
            }
            return false
        } ?? false
    }

    func deleteBookmark(guid: String) async {
        _ = await read { try $0.bookmarksDelete(id: guid) }
    }

    /// A bookmark folder's direct contents.
    func folder(_ guid: String) async -> Folder? {
        let item = await read { try $0.bookmarksGetByGuid(guid: guid, getDirectChildren: true) } ?? nil
        guard case let .folder(folder)? = item else {
            return nil
        }
        var contents = Folder(title: Self.title(of: folder))
        for child in folder.childNodes ?? [] {
            switch child {
            case let .folder(subfolder):
                contents.folders.append(Folder.Subfolder(guid: subfolder.guid, title: Self.title(of: subfolder)))
            case let .bookmark(bookmark):
                if let url = URL(string: bookmark.url) {
                    let title = bookmark.title.flatMap { $0.isEmpty ? nil : $0 } ?? (url.host ?? bookmark.url)
                    contents.bookmarks.append(Folder.Bookmark(guid: bookmark.guid, url: url, title: title))
                }
            case .separator:
                break
            }
        }
        return contents
    }

    // MARK: Helpers

    private static func isWeb(_ url: URL) -> Bool {
        url.scheme == "https" || url.scheme == "http"
    }

    /// Roots have no titles in the database; these are Firefox's names.
    private static func title(of folder: BookmarkFolder) -> String {
        switch folder.guid {
        case Root.all: return "Bookmarks"
        case Root.menu: return "Bookmarks Menu"
        case Root.toolbar: return "Bookmarks Toolbar"
        case Root.other: return "Other Bookmarks"
        case Root.mobile: return "Mobile Bookmarks"
        default: return folder.title ?? "Folder"
        }
    }

    private func write(_ body: @escaping @Sendable (PlacesConnection) throws -> Void) {
        guard let connection else { return }
        Task.detached {
            do {
                try body(connection)
            } catch {
                logger.error("Places write failed: \(error)")
            }
        }
    }

    private func read<T: Sendable>(_ body: @escaping @Sendable (PlacesConnection) throws -> T) async -> T? {
        guard let connection else { return nil }
        return await Task.detached {
            do {
                return try body(connection)
            } catch {
                logger.error("Places read failed: \(error)")
                return nil
            }
        }.value
    }
}
