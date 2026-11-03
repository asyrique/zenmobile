import AuthenticationServices
import LocalAuthentication
import SwiftUI
import ZenCore

/// Zen's iOS AutoFill provider: the passwords saved in Zen, for any app or
/// website. iOS shows Zen's suggestions above the keyboard (the app keeps
/// them in ASCredentialIdentityStore) and lists Zen under Passwords; either
/// way the user unlocks with Face ID, Touch ID or the passcode first.
///
/// It reads the app's logins database in the shared App Group container,
/// with the key from the shared Keychain group (ADR 0007).
final class CredentialProviderViewController: ASCredentialProviderViewController {
    /// The user picked "Zen" for a sign-in: list the logins, the site's
    /// first.
    override func prepareCredentialList(for serviceIdentifiers: [ASCredentialServiceIdentifier]) {
        let hosts = serviceIdentifiers.compactMap(Self.host(of:))
        unlock { [weak self] in
            guard let self else { return }
            guard let store = SharedLogins.open() else {
                return self.show(logins: [], hosts: hosts, store: nil)
            }
            let logins = (try? store.list()) ?? []
            self.show(logins: logins, hosts: hosts, store: store)
        }
    }

    /// A suggestion above the keyboard: always unlock first.
    override func provideCredentialWithoutUserInteraction(for credentialIdentity: ASPasswordCredentialIdentity) {
        cancel(.userInteractionRequired)
    }

    override func prepareInterfaceToProvideCredential(for credentialIdentity: ASPasswordCredentialIdentity) {
        unlock { [weak self] in
            guard let self else { return }
            guard let id = credentialIdentity.recordIdentifier, let store = SharedLogins.open(),
                  let login = try? store.get(id: id) else {
                return self.cancel(.credentialIdentityNotFound)
            }
            self.complete(login, store: store)
        }
    }

    // MARK: Steps

    /// Face ID, Touch ID or the passcode; a device without a passcode has
    /// nothing to ask for.
    private func unlock(then proceed: @escaping @MainActor () -> Void) {
        let context = LAContext()
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: nil) else {
            proceed()
            return
        }
        context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "Fill a password saved in Zen") { ok, _ in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    if ok {
                        proceed()
                    } else {
                        self.cancel(.userCanceled)
                    }
                }
            }
        }
    }

    private func show(logins: [Login], hosts: [String], store: LoginStore?) {
        let list = CredentialList(
            logins: logins,
            hosts: hosts,
            onPick: { [weak self] login in self?.complete(login, store: store) },
            onCancel: { [weak self] in self?.cancel(.userCanceled) })
        let hosting = UIHostingController(rootView: list)
        addChild(hosting)
        hosting.view.frame = view.bounds
        hosting.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(hosting.view)
        hosting.didMove(toParent: self)
    }

    private func complete(_ login: Login, store: LoginStore?) {
        try? store?.touch(id: login.id)
        extensionContext.completeRequest(
            withSelectedCredential: ASPasswordCredential(user: login.username, password: login.password),
            completionHandler: nil)
    }

    private func cancel(_ code: ASExtensionError.Code) {
        extensionContext.cancelRequest(withError: NSError(domain: ASExtensionErrorDomain, code: code.rawValue))
    }

    static func host(of service: ASCredentialServiceIdentifier) -> String? {
        switch service.type {
        case .domain: return service.identifier.lowercased()
        case .URL: return URL(string: service.identifier)?.host?.lowercased()
        @unknown default: return nil
        }
    }
}

/// The app's logins database, from the shared container. Kept in step
/// with Logins.swift in the app: the App Group, file name and key name.
enum SharedLogins {
    static let appGroup = "group.io.github.asyrique.zenmobile"
    static let keyName = "io.github.asyrique.zenmobile.logins.key"

    static func open() -> LoginStore? {
        zenInitialize()
        guard let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup) else {
            return nil
        }
        let path = container.appendingPathComponent("logins.db").path
        guard FileManager.default.fileExists(atPath: path), let key = readKey() else { return nil }
        return try? LoginStore(path: path, encdec: createManagedEncdec(keyManager: createStaticKeyManager(key: key)))
    }

    private static func readKey() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: keyName,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecReturnData as String: true,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }
}

/// The logins to choose from: the site's first, then all, searchable.
struct CredentialList: View {
    let logins: [Login]
    let hosts: [String]
    let onPick: (Login) -> Void
    let onCancel: () -> Void
    @State private var query = ""

    var body: some View {
        NavigationStack {
            List {
                let suggested = logins.filter(matchesSite)
                if !suggested.isEmpty && query.isEmpty {
                    Section("For this site") {
                        rows(suggested)
                    }
                }
                Section("All passwords") {
                    rows(logins.filter(matchesQuery))
                }
            }
            .searchable(text: $query)
            .navigationTitle("Zen passwords")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
            }
            .overlay {
                if logins.isEmpty {
                    ContentUnavailableView(
                        "No saved passwords",
                        systemImage: "key",
                        description: Text("Passwords you save in Zen, or sync from Firefox and Zen desktop, appear here."))
                }
            }
        }
    }

    private func rows(_ logins: [Login]) -> some View {
        ForEach(logins, id: \.id) { login in
            Button { onPick(login) } label: {
                VStack(alignment: .leading) {
                    Text(login.username.isEmpty ? "(no username)" : login.username)
                    Text(Self.site(login)).font(.footnote).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func matchesSite(_ login: Login) -> Bool {
        guard let saved = URL(string: login.origin)?.host?.lowercased() else { return false }
        return hosts.contains { $0 == saved || $0.hasSuffix("." + saved) || saved.hasSuffix("." + $0) }
    }

    private func matchesQuery(_ login: Login) -> Bool {
        query.isEmpty || login.origin.localizedCaseInsensitiveContains(query) || login.username.localizedCaseInsensitiveContains(query)
    }

    static func site(_ login: Login) -> String {
        URL(string: login.origin)?.host ?? login.origin
    }
}
