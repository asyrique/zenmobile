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
                ZenWebView(url: url, shouldCancel: { app.interceptSignInNavigation($0) })
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

struct AccountView: View {
    @Environment(AppModel.self) var app

    var body: some View {
        Form {
            Section("Firefox account") {
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
                }
            }
            if let error = app.lastSyncError {
                Section("Last sync") {
                    Text(error).foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Settings")
    }
}
