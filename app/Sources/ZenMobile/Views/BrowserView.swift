import SwiftUI
import ZenCore

/// The home surface: the current page full-bleed, with an Arc Search-style
/// bottom bar (tabs · new tab · Space sheet) and, while a page is open, its
/// navigation controls above it.
struct BrowserView: View {
    @Environment(AppModel.self) var app
    @Environment(BrowserModel.self) var browser
    @State var showSpaces = false
    @State var showTabs = false
    @State var showAddressBar = false
    /// Whether the address bar loads into the current tab (tapped its
    /// address) rather than opening a new one.
    @State var addressBarEditsTab = false
    /// What the address bar starts with: the page's address when editing it.
    @State var addressBarStart = ""
    /// Where the address bar asked to go, carried out once it has closed.
    @State var addressBarDestination: (url: URL, isPrivate: Bool)?
    @State var findingInPage = false

    var body: some View {
        ZStack(alignment: .bottom) {
            content
                .ignoresSafeArea(edges: .top)
            VStack(spacing: 0) {
                if let tab = browser.selectedTab {
                    if findingInPage {
                        FindBar(page: tab.page, onDone: { findingInPage = false })
                    } else {
                        NavigationBar(
                            page: tab.page,
                            onAddress: { openAddressBar(editingTab: true) },
                            onFind: { findingInPage = true })
                    }
                }
                BottomBar(
                    tabCount: browser.tabs.count,
                    onTabs: { showTabs = true },
                    onNewTab: { openAddressBar(editingTab: false) },
                    onSpaces: { showSpaces = true })
            }
            .background(.ultraThinMaterial)
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
        .sheet(isPresented: showsPrompt) {
            if let page = browser.selectedTab?.page, let prompt = page.prompt {
                PromptView(prompt: prompt, host: page.url.host ?? "This page") { accepted, text in
                    page.answerPrompt(accepted: accepted, text: text)
                }
            }
        }
        // Goes where the address bar said once it has closed: a new tab's web
        // view created under the open keyboard (Android) takes over input,
        // and later text fields lose the keyboard partway through typing.
        .sheet(isPresented: $showAddressBar, onDismiss: goToAddress) {
            AddressBarView(text: addressBarStart, allowsPrivate: !addressBarEditsTab) { url, isPrivate in
                addressBarDestination = (url, isPrivate)
                showAddressBar = false
            }
        }
    }

    /// Whether the current tab's page is asking something; dismissing the
    /// sheet answers no.
    private var showsPrompt: Binding<Bool> {
        Binding(
            get: { browser.selectedTab?.page.prompt != nil },
            set: { shown in
                if !shown {
                    browser.selectedTab?.page.answerPrompt(accepted: false)
                }
            })
    }

    private func goToAddress() {
        guard let (url, isPrivate) = addressBarDestination else { return }
        addressBarDestination = nil
        if addressBarEditsTab, let tab = browser.selectedTab {
            tab.page.load(url)
        } else {
            browser.open(url, isPrivate: isPrivate)
        }
    }

    private func openAddressBar(editingTab: Bool) {
        addressBarEditsTab = editingTab
        // Editing starts with the page's address, to change or replace.
        addressBarStart = editingTab ? (browser.selectedTab?.url.absoluteString ?? "") : ""
        showAddressBar = true
    }

    @ViewBuilder private var content: some View {
        if let tab = browser.selectedTab {
            ZenWebView(page: tab.page)
                // Android's AndroidView sizes to its content unless told to fill.
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .id(tab.id)
                .accessibilityIdentifier("webContent")
        } else {
            StartPage(showSpaces: { showSpaces = true }, showAddressBar: { openAddressBar(editingTab: false) })
        }
    }
}

/// Back, forward, the page's address (tap to go somewhere else in this tab),
/// reload or stop, and share; with the load's progress along the top.
struct NavigationBar: View {
    @Environment(Places.self) var places
    let page: WebPage
    let onAddress: () -> Void
    let onFind: () -> Void
    @State var isBookmarked = false

    var body: some View {
        VStack(spacing: 0) {
            if page.isLoading {
                ProgressView(value: page.progress)
                    .progressViewStyle(.linear)
                    .accessibilityIdentifier("pageProgress")
            }
            HStack(spacing: 8) {
                Button { page.goBack() } label: {
                    Image(systemName: "chevron.left").frame(width: 36, height: 36)
                }
                .disabled(!page.canGoBack)
                .accessibilityLabel(Text("Back"))
                .accessibilityIdentifier("backButton")
                Button { page.goForward() } label: {
                    Image(systemName: "chevron.right").frame(width: 36, height: 36)
                }
                .disabled(!page.canGoForward)
                .accessibilityLabel(Text("Forward"))
                .accessibilityIdentifier("forwardButton")
                Button(action: onAddress) {
                    HStack(spacing: 6) {
                        if page.isPrivate {
                            ZenSymbolImage(symbol: .privateTab, size: 14).font(.caption)
                        }
                        // A padlock for pages that came entirely over HTTPS.
                        Image(systemName: page.isSecure ? "lock" : "info.circle")
                            .font(.caption)
                            .accessibilityLabel(Text(page.isSecure ? "Secure connection" : "Connection not secure"))
                            .accessibilityIdentifier("securityIndicator")
                        Text(page.url.host ?? page.url.absoluteString)
                            .font(.footnote)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 36)
                    .background(Capsule().fill(Color.primary.opacity(0.1)))
                }
                .accessibilityLabel(Text("Address"))
                .accessibilityIdentifier("addressPill")
                if page.isLoading {
                    Button { page.stop() } label: {
                        Image(systemName: "xmark").frame(width: 36, height: 36)
                    }
                    .accessibilityLabel(Text("Stop"))
                    .accessibilityIdentifier("stopButton")
                } else {
                    Button { page.reload() } label: {
                        Image(systemName: "arrow.clockwise.circle").frame(width: 36, height: 36)
                    }
                    .accessibilityLabel(Text("Reload"))
                    .accessibilityIdentifier("reloadButton")
                }
                ShareLink(item: page.url) {
                    Image(systemName: "square.and.arrow.up").frame(width: 36, height: 36)
                }
                .accessibilityLabel(Text("Share"))
                .accessibilityIdentifier("shareButton")
                Menu {
                    Button(isBookmarked ? "Remove bookmark" : "Add bookmark") {
                        let (url, title) = (page.url, page.title)
                        Task { isBookmarked = await places.toggleBookmark(url, title: title) }
                    }
                    Button("Find in page", action: onFind)
                } label: {
                    Image(systemName: "ellipsis").frame(width: 36, height: 36)
                }
                .accessibilityLabel(Text("More"))
                .accessibilityIdentifier("pageMenu")
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)
        }
        .foregroundStyle(Color.primary)
        .task(id: page.url) { isBookmarked = await places.isBookmarked(page.url) }
    }
}

/// Find in page: the text to find, where the match is, previous and next.
struct FindBar: View {
    let page: WebPage
    let onDone: () -> Void
    @State var text = ""
    @FocusState var fieldFocused: Bool

    var body: some View {
        HStack(spacing: 8) {
            TextField("Find in page", text: $text)
                .textFieldStyle(.roundedBorder)
                .autocorrectionDisabled()
                .onSubmit { page.find(text) }
                .focused($fieldFocused)
                .accessibilityIdentifier("findField")
            if let status {
                Text(status)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("findStatus")
            }
            Button { page.find(text, backwards: true) } label: {
                Image(systemName: "chevron.up").frame(width: 36, height: 36)
            }
            .disabled(text.isEmpty)
            .accessibilityLabel(Text("Previous match"))
            Button { page.find(text) } label: {
                Image(systemName: "chevron.down").frame(width: 36, height: 36)
            }
            .disabled(text.isEmpty)
            .accessibilityLabel(Text("Next match"))
            Button("Done") {
                // Let go of the keyboard before the bar goes away: removed
                // while focused, on Android the next text field loses the
                // keyboard partway through typing.
                fieldFocused = false
                page.endFind()
                onDone()
            }
            .accessibilityIdentifier("findDone")
        }
        .foregroundStyle(Color.primary)
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .onChange(of: text) { _, newText in
            page.find(newText)
        }
    }

    /// "2 of 5" where the engine counts matches (Gecko), otherwise whether
    /// there's one (WebKit).
    private var status: String? {
        guard let result = page.findResult else { return nil }
        if !result.found {
            return "Not found"
        }
        return result.total > 0 ? "\(result.current) of \(result.total)" : "Found"
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

/// A page's JavaScript dialog (alert, confirm, prompt) or permission request.
struct PromptView: View {
    let prompt: PagePrompt
    let host: String
    let onAnswer: (Bool, String?) -> Void
    @State var text: String

    init(prompt: PagePrompt, host: String, onAnswer: @escaping (Bool, String?) -> Void) {
        self.prompt = prompt
        self.host = host
        self.onAnswer = onAnswer
        _text = State(initialValue: prompt.defaultText)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if prompt.kind != .permission {
                Text("\(host) says").font(.headline)
            }
            Text(prompt.message)
                .accessibilityIdentifier("promptMessage")
            if prompt.kind == .text {
                TextField("", text: $text)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("promptField")
            }
            HStack {
                Spacer()
                if prompt.kind != .alert {
                    Button(prompt.kind == .permission ? "Block" : "Cancel") { onAnswer(false, nil) }
                        .accessibilityIdentifier("promptCancel")
                }
                Button(prompt.kind == .permission ? "Allow" : "OK") { onAnswer(true, text) }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("promptOK")
            }
            Spacer()
        }
        .padding()
        .presentationDetents([.medium])
    }
}

struct AddressBarView: View {
    @Environment(Places.self) var places
    /// Whether to offer opening the page in a private tab.
    let allowsPrivate: Bool
    let onSubmit: (URL, Bool) -> Void
    @State var text: String
    @State var isPrivate = false
    /// Pages from history and bookmarks matching the text.
    @State var suggestions: [Places.Suggestion] = []

    init(text: String = "", allowsPrivate: Bool, onSubmit: @escaping (URL, Bool) -> Void) {
        _text = State(initialValue: text)
        self.allowsPrivate = allowsPrivate
        self.onSubmit = onSubmit
    }

    var body: some View {
        VStack(alignment: .leading) {
            HStack {
                TextField("Search or enter address", text: $text)
                    .textFieldStyle(.roundedBorder)
                    .autocorrectionDisabled()
                    .onSubmit(submit)
                    .accessibilityIdentifier("addressField")
                if !text.isEmpty {
                    Button { text = "" } label: {
                        Image(systemName: "xmark").frame(width: 32, height: 32)
                    }
                    .accessibilityLabel(Text("Clear"))
                    .accessibilityIdentifier("addressClear")
                }
                Button("Go", action: submit)
                    .buttonStyle(.borderedProminent)
                    .disabled(text.isEmpty)
                    .accessibilityIdentifier("addressGo")
            }
            if allowsPrivate {
                Toggle("Private tab", isOn: $isPrivate)
                    .accessibilityIdentifier("privateToggle")
            }
            ForEach(suggestions) { suggestion in
                Button { onSubmit(suggestion.url, isPrivate) } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(suggestion.title).lineLimit(1)
                        Text(suggestion.url.absoluteString)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .accessibilityIdentifier("suggestion")
            }
            Spacer()
        }
        .padding()
        // Full height, so suggestions show above the keyboard.
        .presentationDetents([.large])
        // Once typing pauses: updating the list on every keystroke can make
        // Android's text field lose the keyboard partway through typing.
        .task(id: text) {
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            suggestions = await places.suggestions(for: text)
        }
    }

    private func submit() {
        if let url = BrowserModel.url(forInput: text) {
            onSubmit(url, isPrivate)
        }
    }
}
