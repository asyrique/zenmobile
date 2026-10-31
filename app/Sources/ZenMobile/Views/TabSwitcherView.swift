import SwiftUI
import ZenCore

/// The phone's tabs as paged cards (Arc Search's switcher), with the
/// desktop-tabs button bottom-left.
struct TabSwitcherView: View {
    @Environment(BrowserModel.self) var browser
    @Environment(\.dismiss) var dismiss
    @State var showDesktopTabs = false

    var body: some View {
        NavigationStack {
            VStack {
                if browser.tabs.isEmpty {
                    Spacer()
                    Text("No open tabs").foregroundStyle(.secondary)
                    Spacer()
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 16) {
                            ForEach(browser.tabs) { tab in
                                card(tab)
                            }
                        }
                        .padding(24)
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
                    NavigationLink { DownloadsView() } label: {
                        Image(systemName: "square.and.arrow.down")
                            .frame(width: 48, height: 48)
                            .background(Circle().fill(Color.primary.opacity(0.12)))
                    }
                    .accessibilityLabel(Text("Downloads"))
                    .accessibilityIdentifier("downloadsButton")
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
