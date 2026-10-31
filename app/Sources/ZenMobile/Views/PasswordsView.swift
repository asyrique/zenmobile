import SwiftUI
import ZenCore
#if canImport(LocalAuthentication)
import LocalAuthentication
#endif

/// Settings → Passwords: the saved logins, behind the device's passcode (or
/// biometrics) as Firefox keeps them, when the device has one.
struct PasswordsView: View {
    @Environment(Logins.self) var logins
    @State var unlocked = false
    /// Bumped to ask for the passcode again.
    @State var attempt = 0
    @State var search = ""

    var body: some View {
        Group {
            if unlocked {
                VStack(spacing: 0) {
                    TextField("Search passwords", text: $search)
                        .textFieldStyle(.roundedBorder)
                        .autocorrectionDisabled()
                        .padding()
                    SavedLoginsList(query: search)
                }
            } else {
                VStack(spacing: 16) {
                    Spacer()
                    Image(systemName: "lock")
                        .font(.largeTitle)
                    Text("Unlock to see saved passwords")
                    Button("Unlock") { attempt += 1 }
                        .accessibilityIdentifier("unlockPasswords")
                    Spacer()
                    #if os(Android)
                    ComposeView {
                        DeviceAuthComposer(attempt: attempt) { ok in unlocked = ok }
                    }
                    .frame(width: 1, height: 1)
                    #endif
                }
            }
        }
        .navigationTitle("Passwords")
        #if !os(Android)
        .task(id: attempt) {
            unlocked = await Self.authenticate()
        }
        #endif
        .task(id: unlocked) {
            if unlocked {
                await logins.reload()
            }
        }
    }

    #if !os(Android) && canImport(LocalAuthentication)
    /// Asks for Face ID, Touch ID or the passcode; a device with no passcode
    /// has nothing to ask for.
    private static func authenticate() async -> Bool {
        let context = LAContext()
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: nil) else {
            return true
        }
        return (try? await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Show your saved passwords")) ?? false
    }
    #endif
}

/// The list, apart from the search field so typing doesn't re-render the
/// field (which drops the keyboard on Android).
struct SavedLoginsList: View {
    @Environment(Logins.self) var logins
    let query: String

    var body: some View {
        let shown = logins.saved.filter { login in
            query.isEmpty || login.origin.localizedCaseInsensitiveContains(query) || login.username.localizedCaseInsensitiveContains(query)
        }
        if logins.saved.isEmpty {
            VStack {
                Spacer()
                Text("No saved passwords").foregroundStyle(.secondary)
                Text("Passwords you save while browsing, and those synced from Firefox or Zen, appear here.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding()
                Spacer()
            }
        } else {
            List {
                ForEach(shown, id: \.id) { login in
                    NavigationLink {
                        SavedLoginView(login: login)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(SavedLoginView.site(login))
                            Text(login.username.isEmpty ? "(no username)" : login.username)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .accessibilityIdentifier("savedLogin")
                }
            }
        }
    }
}

struct SavedLoginView: View {
    @Environment(Logins.self) var logins
    @Environment(\.dismiss) var dismiss
    let login: Login
    @State var showsPassword = false
    @State var confirmingDelete = false

    var body: some View {
        Form {
            Section("Site") {
                Text(login.origin)
            }
            Section("Username") {
                HStack {
                    Text(login.username.isEmpty ? "(no username)" : login.username)
                        .accessibilityIdentifier("savedUsername")
                    Spacer()
                    Button("Copy") { Clipboard.copy(login.username) }
                }
            }
            Section("Password") {
                HStack {
                    Text(showsPassword ? login.password : String(repeating: "•", count: 10))
                        .accessibilityIdentifier("savedPassword")
                    Spacer()
                    Button(showsPassword ? "Hide" : "Show") { showsPassword.toggle() }
                        .accessibilityIdentifier("showPassword")
                    Button("Copy") { Clipboard.copy(login.password) }
                }
            }
            Section {
                Button("Delete", role: .destructive) { confirmingDelete = true }
                    .accessibilityIdentifier("deleteLogin")
            }
        }
        .navigationTitle(Self.site(login))
        .alert("Delete this password?", isPresented: $confirmingDelete) {
            Button("Delete", role: .destructive) {
                Task {
                    await logins.delete(login.id)
                    dismiss()
                }
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    static func site(_ login: Login) -> String {
        URL(string: login.origin)?.host ?? login.origin
    }
}

#if SKIP
import androidx.compose.runtime.Composable

/// Asks for the device's screen lock (AndroidSystem.kt) each time `attempt`
/// changes, including when first shown.
struct DeviceAuthComposer : ContentComposer {
    let attempt: Int
    let onResult: (Bool) -> Void

    init(attempt: Int, onResult: @escaping (Bool) -> Void) {
        self.attempt = attempt
        self.onResult = onResult
    }

    @Composable func Compose(context: ComposeContext) {
        DeviceAuthEffect(attempt, onResult)
    }
}
#endif
