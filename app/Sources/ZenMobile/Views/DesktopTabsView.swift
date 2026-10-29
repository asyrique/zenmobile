import SwiftUI
import ZenCore

/// Tabs open on the user's other devices, from Firefox Sync's `tabs` collection.
struct DesktopTabsView: View {
    @Environment(AppModel.self) var app
    let open: (URL, String) -> Void

    var body: some View {
        List {
            if app.desktopTabs.isEmpty {
                Text(app.isSyncing ? "Syncing…" : "No tabs from other devices yet.")
                    .foregroundStyle(.secondary)
            }
            ForEach(app.desktopTabs, id: \.clientId) { device in
                Section(device.clientName) {
                    ForEach(sortedTabs(device), id: \.self) { tab in
                        if let urlString = tab.urlHistory.first, let url = URL(string: urlString) {
                            Button { open(url, tab.title) } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(spacing: 6) {
                                        if tab.pinned {
                                            Image(systemName: "pin.fill").font(.caption)
                                        }
                                        Text(tab.title.isEmpty ? urlString : tab.title).lineLimit(1)
                                    }
                                    Text(url.host ?? urlString)
                                        .font(.footnote)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Desktop tabs")
        .refreshable { await app.sync(reason: .user) }
    }

    /// Pinned first, then in window order, as on desktop.
    private func sortedTabs(_ device: ClientRemoteTabs) -> [RemoteTabRecord] {
        device.remoteTabs.sorted {
            if $0.pinned != $1.pinned { return $0.pinned }
            if $0.windowId != $1.windowId { return $0.windowId < $1.windowId }
            return $0.index < $1.index
        }
    }
}
