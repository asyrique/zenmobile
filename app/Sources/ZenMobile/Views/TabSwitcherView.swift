import SwiftUI
import ZenCore

/// The phone's tabs as paged cards (Arc Search's switcher), opening on the
/// current one, with the desktop-tabs button bottom-left. Tabs are grouped
/// by Zen Space, with a row of the Spaces above to jump between groups.
struct TabSwitcherView: View {
    @Environment(BrowserModel.self) var browser
    @Environment(AppModel.self) var app
    @Environment(\.dismiss) var dismiss
    @State var showDesktopTabs = false
    @State var scrollTarget: UUID?

    var body: some View {
        NavigationStack {
            VStack {
                if browser.tabs.isEmpty {
                    Spacer()
                    Text("No open tabs").foregroundStyle(.secondary)
                    Spacer()
                } else {
                    let groups = browser.tabGroups(spaces: app.spaces?.spaces ?? [])
                    if groups.count > 1 {
                        groupBar(groups)
                    }
                    ScrollViewReader { proxy in
                        ScrollView(.horizontal, showsIndicators: false) {
                            LazyHStack(spacing: 16) {
                                ForEach(groups.flatMap(\.tabs)) { tab in
                                    card(tab, group: groups.count > 1 ? groups.first { group in group.tabs.contains { member in member.id == tab.id } } : nil)
                                }
                            }
                            .padding(24)
                        }
                        // Open on the current tab, once the sheet has come
                        // up and laid the row out: scrolling earlier is
                        // ignored (iOS, while presenting) or does nothing
                        // (Android, before the row's first layout).
                        .task {
                            try? await Task.sleep(for: .milliseconds(300))
                            scrollTarget = browser.selectedTabId
                        }
                        .onChange(of: scrollTarget) { _, target in
                            if let target {
                                proxy.scrollTo(target, anchor: .center)
                                // So tapping the same group again scrolls again.
                                scrollTarget = nil
                            }
                        }
                    }
                }
                HStack {
                    Button { showDesktopTabs = true } label: {
                        ZenSymbolImage(symbol: .desktop)
                            .frame(width: 48, height: 48)
                            .background(Circle().fill(Color.primary.opacity(0.12)))
                    }
                    .accessibilityLabel(Text("Tabs on your desktop"))
                    .accessibilityIdentifier("desktopTabsButton")
                    Spacer()
                    NavigationLink { LibraryView() } label: {
                        ZenSymbolImage(symbol: .library)
                            .frame(width: 48, height: 48)
                            .background(Circle().fill(Color.primary.opacity(0.12)))
                    }
                    .accessibilityLabel(Text("Bookmarks, history and downloads"))
                    .accessibilityIdentifier("libraryButton")
                    Spacer()
                    NavigationLink { AccountView() } label: {
                        Image(systemName: "gearshape")
                            .frame(width: 48, height: 48)
                            .background(Circle().fill(Color.primary.opacity(0.12)))
                    }
                    .accessibilityLabel(Text("Settings"))
                    .accessibilityIdentifier("settingsButton")
                }
                .padding(.horizontal, 24)
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .accessibilityIdentifier("tabsDone")
                }
            }
            // A page opened from the library (or desktop tabs) closes the
            // switcher; closing tabs doesn't.
            .onChange(of: browser.tabs.count) { before, after in
                if after > before {
                    dismiss()
                }
            }
            .navigationDestination(isPresented: $showDesktopTabs) {
                DesktopTabsView { url, title in
                    browser.open(url, title: title)
                    dismiss()
                }
            }
        }
    }

    /// A chip per group; tapping one scrolls to its first tab.
    private func groupBar(_ groups: [BrowserModel.TabGroup]) -> some View {
        let current = groups.first { group in group.tabs.contains { member in member.id == browser.selectedTabId } }?.id
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(groups) { group in
                    Button {
                        scrollTarget = group.tabs.first?.id
                    } label: {
                        HStack(spacing: 6) {
                            if let emoji = group.emoji {
                                Text(emoji)
                            }
                            Text(group.name).lineLimit(1)
                            Text("\(group.tabs.count)").foregroundStyle(.secondary)
                        }
                        .font(.subheadline)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Capsule().fill(Color.primary.opacity(group.id == current ? 0.18 : 0.08)))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("tabGroup")
                }
            }
            .padding(.horizontal, 24)
        }
        .padding(.top, 8)
    }

    private func card(_ tab: BrowserModel.Tab, group: BrowserModel.TabGroup?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(tab.title).font(.headline).lineLimit(1)
                    .accessibilityIdentifier("tabTitle")
                Spacer()
                Button { browser.close(tab.id) } label: { Image(systemName: "xmark") }
                    .accessibilityLabel(Text("Close tab"))
            }
            HStack(spacing: 6) {
                if tab.isPrivate {
                    ZenSymbolImage(symbol: .privateTab, size: 14).font(.caption)
                    Text("Private").font(.footnote.bold())
                }
                Text(tab.url.host ?? tab.url.absoluteString)
                    .font(.footnote)
            }
            .foregroundStyle(.secondary)
            Spacer()
            if let group {
                Text([group.emoji, group.name].compactMap { $0 }.joined(separator: " "))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding()
        .frame(width: 260, height: 420)
        .background(RoundedRectangle(cornerRadius: 28).fill(Color.primary.opacity(0.08)))
        .onTapGesture {
            browser.selectedTabId = tab.id
            dismiss()
        }
    }
}
