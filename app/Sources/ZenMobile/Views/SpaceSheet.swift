import SwiftUI
import ZenCore

/// Arc Search's Spaces screen, filled with Zen desktop's sidebar: the Space's
/// gradient, its Essentials, its folders and pinned tabs, and a bar of
/// Space icons along the bottom to switch between them.
struct SpaceSheet: View {
    @Environment(AppModel.self) var app
    @Environment(\.dismiss) var dismiss
    let open: (URL, String, String?) -> Void
    @State var selectedSpace: String?
    @State var collapsedFolders: Set<String> = []

    var body: some View {
        if let snapshot = app.spaces, snapshot.lastSyncMillis != nil, !snapshot.spaces.isEmpty {
            let space = snapshot.spaces.first { $0.uuid == selectedSpace } ?? snapshot.spaces[0]
            VStack(spacing: 0) {
                header(space)
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        essentials(snapshot, space: space)
                        ForEach(visibleRows(space), id: \.self) { row in
                            rowView(row)
                        }
                    }
                    .padding(.horizontal, 24)
                }
                spacesBar(snapshot.spaces, current: space)
            }
            .background(space.background.ignoresSafeArea())
            .foregroundStyle(.white)
        } else {
            SpacesEmptyState(signedIn: app.account != .signedOut, onDesktopTabs: nil)
        }
    }

    private func header(_ space: ZenSpace) -> some View {
        HStack {
            Text(space.name)
                .font(.largeTitle.bold())
            Spacer()
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.headline)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(Color.white.opacity(0.2)))
            }
            .accessibilityLabel(Text("Close"))
            .accessibilityIdentifier("closeSpaces")
        }
        .padding(24)
    }

    /// Essentials for the Space's container (or no container), as a tile grid.
    @ViewBuilder private func essentials(_ snapshot: ZenSpacesSnapshot, space: ZenSpace) -> some View {
        let tabs = snapshot.essentials
            .first { $0.container?.guid == space.container?.guid }?.tabs ?? []
        if !tabs.isEmpty {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 64))], spacing: 12) {
                ForEach(tabs, id: \.id) { tab in
                    Button { openTab(tab) } label: {
                        FaviconView(tab: tab, size: 28)
                            .frame(width: 64, height: 64)
                            .background(RoundedRectangle(cornerRadius: 16).fill(Color.white.opacity(0.15)))
                    }
                    .accessibilityLabel(Text(tab.title))
                }
            }
            .padding(.bottom, 16)
        }
    }

    /// Rows minus the contents of collapsed folders.
    private func visibleRows(_ space: ZenSpace) -> [ZenSidebarRow] {
        var hiddenBelowDepth: UInt32?
        var rows: [ZenSidebarRow] = []
        for row in space.rows {
            if let depth = hiddenBelowDepth {
                if row.depth > depth { continue }
                hiddenBelowDepth = nil
            }
            rows.append(row)
            if case let .folder(folder) = row.item, collapsedFolders.contains(folder.id) {
                hiddenBelowDepth = row.depth
            }
        }
        return rows
    }

    @ViewBuilder private func rowView(_ row: ZenSidebarRow) -> some View {
        HStack(spacing: 14) {
            switch row.item {
            case let .folder(folder):
                Button {
                    if collapsedFolders.contains(folder.id) {
                        collapsedFolders.remove(folder.id)
                    } else {
                        collapsedFolders.insert(folder.id)
                    }
                } label: {
                    HStack(spacing: 14) {
                        Image(systemName: folder.isLive ? "dot.radiowaves.left.and.right" : "folder.fill")
                            .frame(width: 28)
                        Text(folder.name).font(.title3)
                        Spacer()
                    }
                }
            case let .tab(tab):
                Button { openTab(tab) } label: {
                    HStack(spacing: 14) {
                        FaviconView(tab: tab, size: 22).frame(width: 28)
                        Text(tab.title).font(.title3).lineLimit(1)
                        Spacer()
                    }
                }
            case let .split(split):
                Button { if let first = split.tabs.first { openTab(first) } } label: {
                    HStack(spacing: 14) {
                        Image(systemName: "rectangle.split.2x1").frame(width: 28)
                        Text(split.tabs.map(\.title).joined(separator: " | "))
                            .font(.title3).lineLimit(1)
                        Spacer()
                    }
                }
            }
        }
        .padding(.leading, CGFloat(row.depth) * 24)
        .padding(.vertical, 10)
    }

    private func spacesBar(_ spaces: [ZenSpace], current: ZenSpace) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 20) {
                ForEach(spaces, id: \.uuid) { space in
                    Button { selectedSpace = space.uuid } label: {
                        Group {
                            if let emoji = space.emoji {
                                Text(emoji).font(.title2)
                            } else {
                                Circle().fill(Color.white.opacity(0.6)).frame(width: 14, height: 14)
                            }
                        }
                        .frame(width: 40, height: 40)
                        .opacity(space.uuid == current.uuid ? 1 : 0.45)
                    }
                    .accessibilityLabel(Text(space.name))
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
        }
        .background(Color.white.opacity(0.08))
    }

    private func openTab(_ tab: ZenTab) {
        guard let url = URL(string: tab.url) else { return }
        open(url, tab.title, tab.id)
    }
}

struct SpacesEmptyState: View {
    let signedIn: Bool
    let onDesktopTabs: (() -> Void)?

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "square.stack.3d.up")
                .font(.largeTitle)
            if signedIn {
                Text("No Spaces yet")
                    .font(.title2.bold())
                Text("Zen desktop syncs Spaces when Spaces sync is turned on. It's on by default in Zen Twilight; on release builds set services.sync.engine.spaces to true in about:config, then sync.")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            } else {
                Text("Sign in to see your Spaces")
                    .font(.title2.bold())
            }
        }
        .padding(32)
        .accessibilityIdentifier("spacesEmptyState")
    }
}

/// Desktop only sends data: URL favicons; anything else shows the site's initial.
struct FaviconView: View {
    let tab: ZenTab
    let size: CGFloat

    var body: some View {
        Text(String(tab.displayHost.replacingOccurrences(of: "www.", with: "").prefix(1)).uppercased())
            .font(.system(size: size * 0.7, weight: .bold))
            .frame(width: size, height: size)
            .background(RoundedRectangle(cornerRadius: size / 4).fill(Color.white.opacity(0.25)))
    }
}
