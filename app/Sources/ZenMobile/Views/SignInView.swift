import SwiftUI
import ZenCore

/// Runs Mozilla's sign-in pages in our own web view and catches the redirect
/// at the end (see `zen_parse_oauth_redirect` in the Rust core).
struct SignInView: View {
    @Environment(AppModel.self) var app
    @Environment(\.dismiss) var dismiss

    var body: some View {
        Group {
            switch app.account {
            case let .signingIn(url):
                SignInWebView(url: url, shouldCancel: { app.interceptSignInNavigation($0) })
            case .signedIn:
                ProgressView().onAppear { dismiss() }
            case .signedOut, .needsReauthentication:
                ProgressView()
            }
        }
        .navigationTitle("Firefox account")
        .task { await app.beginSignIn() }
        .onDisappear {
            if case .signingIn = app.account {
                Task { await app.cancelSignIn() }
            }
        }
    }
}

/// The sign-in page, in a page of its own for as long as the view is up.
struct SignInWebView: View {
    @State var page: WebPage

    init(url: URL, shouldCancel: @escaping (URL) -> Bool) {
        _page = State(initialValue: WebPage(url: url, shouldCancel: shouldCancel))
    }

    var body: some View {
        ZenWebView(page: page)
            .onDisappear { page.close() }
    }
}

struct AccountView: View {
    @Environment(AppModel.self) var app
    @AppStorage(ContentBlocking.trackersKey) var blockTrackers = true
    @AppStorage(ContentBlocking.adsKey) var blockAds = false
    @AppStorage(SearchEngine.settingKey) var searchEngine = SearchEngine.duckDuckGo.rawValue

    var body: some View {
        Form {
            Section {
                switch app.account {
                case let .signedIn(email):
                    Text(email ?? "Signed in")
                    Button("Sync now") { Task { await app.sync(reason: .user) } }
                        .disabled(app.isSyncing)
                    Button("Sign out", role: .destructive) { Task { await app.signOut() } }
                case .needsReauthentication:
                    NavigationLink("Sign in again") { SignInView() }
                case .signedOut, .signingIn:
                    NavigationLink("Sign in") { SignInView() }
                        .accessibilityIdentifier("settingsSignIn")
                }
            } header: {
                Text("Firefox account")
            } footer: {
                Text("Optional. Signing in syncs your open tabs, Zen Spaces, history, bookmarks and passwords with Zen desktop and Firefox; everything else works without it.")
            }
            Section {
                NavigationLink("Passwords") { PasswordsView() }
                    .accessibilityIdentifier("passwordsButton")
                Picker("Search engine", selection: $searchEngine) {
                    ForEach(SearchEngine.allCases) { engine in
                        Text(engine.name).tag(engine.rawValue)
                    }
                }
                .accessibilityIdentifier("searchEnginePicker")
            }
            Section {
                Toggle("Block trackers", isOn: $blockTrackers)
                    .accessibilityIdentifier("blockTrackersToggle")
                    .onChange(of: blockTrackers) { _, _ in
                        Task { await ContentBlocking.apply() }
                    }
                Toggle("Block ads", isOn: $blockAds)
                    .accessibilityIdentifier("blockAdsToggle")
                    .onChange(of: blockAds) { _, _ in
                        Task { await ContentBlocking.apply() }
                    }
            } header: {
                Text("Privacy")
            } footer: {
                Text(Self.privacyFooter)
            }
            if let error = app.lastSyncError {
                Section("Last sync") {
                    Text(error).foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Settings")
    }

    private static var privacyFooter: String {
        #if os(Android)
        let ads = "Ad blocking installs uBlock Origin from addons.mozilla.org."
        #else
        let ads = "Ad blocking uses EasyList, updated every few days."
        #endif
        return "Stops known trackers from following you across websites. \(ads) Turn either off if a site doesn't work."
    }
}
