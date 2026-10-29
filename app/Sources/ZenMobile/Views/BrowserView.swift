import SwiftUI
import ZenCore

/// The home surface: the current page full-bleed, with an Arc Search-style
/// bottom bar (tabs · new tab · Space sheet).
struct BrowserView: View {
    @Environment(AppModel.self) var app
    @Environment(BrowserModel.self) var browser
    @State var showSpaces = false
    @State var showTabs = false
    @State var showAddressBar = false

    var body: some View {
        ZStack(alignment: .bottom) {
            content
                .ignoresSafeArea(edges: .top)
            BottomBar(
                tabCount: browser.tabs.count,
                onTabs: { showTabs = true },
                onNewTab: { showAddressBar = true },
                onSpaces: { showSpaces = true })
        }
        .sheet(isPresented: $showSpaces) {
            SpaceSheet { url, title, zenTabId in
                browser.open(url, title: title, zenTabId: zenTabId)
                showSpaces = false
            }
        }
        .sheet(isPresented: $showTabs) {
            TabSwitcherView()
        }
        .sheet(isPresented: $showAddressBar) {
            AddressBarView { url in
                browser.open(url)
                showAddressBar = false
            }
        }
    }

    @ViewBuilder private var content: some View {
        if let tab = browser.selectedTab {
            ZenWebView(url: tab.url, didNavigate: { url, title in
                browser.didNavigate(tab.id, to: url, title: title)
            })
            .id(tab.id)
            .accessibilityIdentifier("webContent")
        } else {
            StartPage(showSpaces: { showSpaces = true }, showAddressBar: { showAddressBar = true })
        }
    }
}

struct BottomBar: View {
    /// Space content should leave below itself for the bar.
    static let height: CGFloat = 72

    let tabCount: Int
    let onTabs: () -> Void
    let onNewTab: () -> Void
    let onSpaces: () -> Void

    var body: some View {
        HStack {
            Button(action: onTabs) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.primary, lineWidth: 2)
                        .frame(width: 30, height: 30)
                    Text("\(tabCount)")
                        .font(.footnote.bold())
                }
            }
            .accessibilityLabel(Text("Tabs"))
            .accessibilityIdentifier("tabsButton")
            Spacer()
            Button(action: onNewTab) {
                Image(systemName: "plus")
                    .font(.title2.bold())
                    .frame(width: 88, height: 44)
                    .background(Capsule().fill(Color.primary.opacity(0.15)))
            }
            .accessibilityLabel(Text("New tab"))
            .accessibilityIdentifier("newTabButton")
            Spacer()
            Button(action: onSpaces) {
                Image(systemName: "chevron.up")
                    .font(.title3.bold())
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(Color.primary.opacity(0.15)))
            }
            .accessibilityLabel(Text("Spaces"))
            .accessibilityIdentifier("spacesButton")
        }
        .foregroundStyle(Color.primary)
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
    }
}

/// Shown when no tab is open. Browsing never needs an account: syncing with
/// Firefox is offered once, can be put off, and lives in Settings after that.
struct StartPage: View {
    @Environment(AppModel.self) var app
    @AppStorage("syncPromptDismissed") var syncPromptDismissed = false
    let showSpaces: () -> Void
    let showAddressBar: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            Text("Zen")
                .font(.largeTitle.bold())
                .accessibilityIdentifier("startTitle")
            Button("Search or enter address", action: showAddressBar)
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("startSearch")
            if case .signedIn = app.account {
                Button("Open a Space", action: showSpaces)
            }
            Spacer()
            syncPrompt
        }
        .padding(32)
        // Keep everything clear of the floating bottom bar.
        .padding(.bottom, BottomBar.height)
    }

    @ViewBuilder private var syncPrompt: some View {
        switch app.account {
        case .needsReauthentication:
            SyncPromptCard(
                message: "Your Firefox account needs you to sign in again to keep syncing.",
                signInTitle: "Sign in again",
                onDismiss: nil)
        case .signedOut, .signingIn:
            if !syncPromptDismissed {
                SyncPromptCard(
                    message: "Sign in with your Firefox account to see the tabs and Spaces open on your desktop. You can do this later in Settings.",
                    signInTitle: "Sign in",
                    onDismiss: { syncPromptDismissed = true })
            }
        case .signedIn:
            EmptyView()
        }
    }
}

/// An optional invitation to sync, never a gate.
struct SyncPromptCard: View {
    let message: String
    let signInTitle: String
    let onDismiss: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Sync with Firefox").font(.headline)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            HStack {
                NavigationLink(signInTitle) { SignInView() }
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("syncPromptSignIn")
                Spacer()
                if let onDismiss {
                    Button("Not now", action: onDismiss)
                        .accessibilityIdentifier("syncPromptDismiss")
                }
            }
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 20).fill(Color.primary.opacity(0.08)))
        .accessibilityIdentifier("syncPrompt")
    }
}

struct AddressBarView: View {
    let onSubmit: (URL) -> Void
    @State var text = ""

    var body: some View {
        VStack {
            HStack {
                TextField("Search or enter address", text: $text)
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()
                    .onSubmit(submit)
                    .accessibilityIdentifier("addressField")
                Button("Go", action: submit)
                    .buttonStyle(.borderedProminent)
                    .disabled(text.isEmpty)
                    .accessibilityIdentifier("addressGo")
            }
            .padding()
            Spacer()
        }
        .presentationDetents([.medium])
    }

    private func submit() {
        if let url = BrowserModel.url(forInput: text) {
            onSubmit(url)
        }
    }
}
