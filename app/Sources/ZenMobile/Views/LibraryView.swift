import SwiftUI

/// Bookmarks, history and downloads.
struct LibraryView: View {
    /// Opens a page from the library in a new tab.
    let open: (URL) -> Void

    var body: some View {
        List {
            NavigationLink { BookmarksView(guid: Places.Root.all, open: open) } label: {
                Label("Bookmarks", systemImage: "bookmark")
            }
            .accessibilityIdentifier("bookmarksButton")
            NavigationLink { HistoryView(open: open) } label: {
                HStack {
                    ZenSymbolImage(symbol: .history, size: 20)
                    Text("History")
                }
            }
            .accessibilityIdentifier("historyButton")
            NavigationLink { DownloadsView() } label: {
                Label("Downloads", systemImage: "square.and.arrow.down")
            }
            .accessibilityIdentifier("downloadsButton")
        }
        .navigationTitle("Library")
    }
}

/// A bookmark folder: its folders, then its bookmarks. The top level holds
/// Firefox's roots (Mobile, Toolbar, Menu, Other), which sync with desktop.
struct BookmarksView: View {
    @Environment(Places.self) var places
    let guid: String
    let open: (URL) -> Void
    @State var folder: Places.Folder?

    var body: some View {
        List {
            if let folder {
                ForEach(folder.folders) { subfolder in
                    NavigationLink { BookmarksView(guid: subfolder.guid, open: open) } label: {
                        Label(subfolder.title, systemImage: "list.bullet")
                    }
                }
                ForEach(folder.bookmarks) { bookmark in
                    HStack {
                        Button { open(bookmark.url) } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(bookmark.title)
                                    .lineLimit(1)
                                    .accessibilityIdentifier("bookmarkTitle")
                                Text(bookmark.url.host ?? bookmark.url.absoluteString)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Button {
                            Task {
                                await places.deleteBookmark(guid: bookmark.guid)
                                await load()
                            }
                        } label: {
                            Image(systemName: "trash").frame(width: 36, height: 36)
                        }
                        .accessibilityLabel(Text("Delete"))
                    }
                    .buttonStyle(.borderless)
                }
                if folder.folders.isEmpty && folder.bookmarks.isEmpty {
                    Text("No bookmarks here.").foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle(folder?.title ?? "Bookmarks")
        .task { await load() }
    }

    private func load() async {
        folder = await places.folder(guid)
    }
}

/// Recently visited pages, newest first.
struct HistoryView: View {
    @Environment(Places.self) var places
    let open: (URL) -> Void
    @State var visits: [Places.Visit] = []

    var body: some View {
        List {
            if visits.isEmpty {
                Text("No history yet.").foregroundStyle(.secondary)
            }
            ForEach(visits) { visit in
                Button { open(visit.url) } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(visit.title)
                            .lineLimit(1)
                            .accessibilityIdentifier("historyTitle")
                        Text(visit.url.host ?? visit.url.absoluteString)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            if !visits.isEmpty {
                Button("Clear history", role: .destructive) {
                    Task {
                        await places.clearHistory()
                        visits = []
                    }
                }
            }
        }
        .navigationTitle("History")
        .task { visits = await places.recentVisits() }
    }
}
