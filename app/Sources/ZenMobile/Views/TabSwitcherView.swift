import SwiftUI
import ZenCore

/// The phone's tabs as paged cards (Arc Search's switcher), opening on the
/// current one, with the desktop-tabs button bottom-left.
struct TabSwitcherView: View {
    @Environment(BrowserModel.self) var browser
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
                    ScrollViewReader { proxy in
                        ScrollView(.horizontal, showsIndicators: false) {
                            LazyHStack(spacing: 16) {
                                ForEach(browser.tabs) { tab in
                                    card(tab)
                                }
                            }
                            .padding(24)
                        }
                        // Open on the current tab. Scrolls one update after
                        // appearing: on Android the proxy can only scroll once
                        // the row has been laid out.
                        .onAppear { scrollTarget = browser.selectedTabId }
                        .onChange(of: scrollTarget) { _, target in
                            if let target {
                                proxy.scrollTo(target, anchor: .center)
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
                    NavigationLink {
                        LibraryView { url in
                            browser.open(url)
                            dismiss()
                        }
                    } label: {
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
            .navigationDestination(isPresented: $showDesktopTabs) {
                DesktopTabsView { url, title in
                    browser.open(url, title: title)
                    dismiss()
                }
            }
        }
    }

    private func card(_ tab: BrowserModel.Tab) -> some View {
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
