import Foundation
import ZenCore

/// Saved passwords for Android's AutoFill service (ZenAutofill.kt), which
/// fills sign-in forms in other browsers and apps. The service runs in the
/// app's process, sometimes without the browser's UI. Call on the main
/// thread.
/* SKIP @bridge */public final class AutofillLogins {
    /// The logins for a site, as a JSON array of objects with id, origin,
    /// username and password: those saved for `host`'s site (its base
    /// domain) whose own host is `host` or a domain `host` is under.
    /* SKIP @bridge */public static func logins(host: String) -> String {
        let host = host.lowercased()
        let logins = MainActor.assumeIsolated { Logins.shared }
        let matching = logins.logins(forBaseDomain: baseDomain(of: host)).filter { login in
            guard let saved = URL(string: login.origin)?.host?.lowercased() else { return false }
            return host == saved || host.hasSuffix("." + saved)
        }
        let objects = matching.map { ["id": $0.id, "origin": $0.origin, "username": $0.username, "password": $0.password] }
        guard let data = try? JSONSerialization.data(withJSONObject: objects) else { return "[]" }
        return String(decoding: data, as: UTF8.self)
    }

    /// Saves (or updates) a login another app or browser signed in with.
    /* SKIP @bridge */public static func save(origin: String, username: String, password: String) {
        guard !password.isEmpty else { return }
        let logins = MainActor.assumeIsolated { Logins.shared }
        logins.save(LoginEntry(
            origin: origin, httpRealm: nil, formActionOrigin: origin,
            usernameField: "", passwordField: "", password: password, username: username))
    }

    /// The registrable part of a host: the last two labels, or three under
    /// a short second-level label of a country domain (example.co.uk). An
    /// approximation of the public suffix list, used only to narrow the
    /// search; matching itself is by host. IP addresses stay whole.
    static func baseDomain(of host: String) -> String {
        let labels = host.split(separator: ".").map(String.init)
        if labels.count <= 2 || labels.allSatisfy({ Int($0) != nil }) || host.contains(":") {
            return host
        }
        let last = labels[labels.count - 1], second = labels[labels.count - 2]
        let keep = (last.count == 2 && second.count <= 3) ? 3 : 2
        return labels.suffix(keep).joined(separator: ".")
    }
}
