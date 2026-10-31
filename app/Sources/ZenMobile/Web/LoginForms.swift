#if !os(Android) && canImport(UIKit)
import Foundation
import WebKit
import ZenCore

/// Password filling and saving for a WKWebView (GeckoView has its own login
/// manager; see GeckoLogins.kt).
///
/// A script finds sign-in forms and reports them, and their submissions,
/// to the app. With one saved login for the page's origin it's filled when
/// the page loads; with several, the user picks one when they tap a field.
/// After a sign-in the app offers to save the password, or to update it if
/// it changed.
///
/// The script runs in its own content world, so the page's scripts can't
/// see the message handler or fake its messages, and only in main frames.
/// The origin comes from WebKit, never from the script.
@MainActor final class LoginForms: NSObject, WKScriptMessageHandler {
    private weak var page: WebPage?
    private let logins: Logins
    /// The saved logins for the page showing now, and its origin.
    private var candidates: [Login] = []
    private var candidatesOrigin = ""
    private var offeredChoice = false

    private static let handlerName = "zenLogins"
    private static let world = WKContentWorld.defaultClient

    init(page: WebPage, logins: Logins, controller: WKUserContentController) {
        self.page = page
        self.logins = logins
        super.init()
        controller.addUserScript(WKUserScript(source: Self.script, injectionTime: .atDocumentEnd, forMainFrameOnly: true, in: Self.world))
        // The controller keeps its handlers; the proxy keeps it from keeping
        // this (and the page) alive.
        controller.add(WeakHandler(self), contentWorld: Self.world, name: Self.handlerName)
    }

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.frameInfo.isMainFrame, let origin = Self.origin(of: message.frameInfo.securityOrigin),
              let body = message.body as? [String: Any], let type = body["type"] as? String,
              let webView = message.webView else { return }
        switch type {
        case "form":
            loadCandidates(origin: origin, webView: webView)
        case "focus":
            offerChoice(origin: origin, webView: webView)
        case "submit":
            offerToSave(body, origin: origin)
        default:
            break
        }
    }

    private func loadCandidates(origin: String, webView: WKWebView) {
        let logins = logins
        Task {
            let found = await Task.detached { logins.logins(forOrigin: origin) }.value
            candidates = found
            candidatesOrigin = origin
            offeredChoice = false
            if found.count == 1 {
                fill(found[0], in: webView)
            }
        }
    }

    private func offerChoice(origin: String, webView: WKWebView) {
        guard origin == candidatesOrigin, candidates.count > 1, !offeredChoice, let page else { return }
        offeredChoice = true
        let choices = candidates
        page.ask(.choice, message: "Fill a saved password", options: choices.map { $0.username.isEmpty ? "(no username)" : $0.username }) { [weak self] accepted, text in
            guard accepted, let index = text.flatMap({ Int($0) }), choices.indices.contains(index) else { return }
            self?.fill(choices[index], in: webView)
        }
    }

    private func fill(_ login: Login, in webView: WKWebView) {
        let logins = logins
        Task {
            let filled = try? await webView.callAsyncJavaScript(
                "return window.__zenFillLogin(username, password)",
                arguments: ["username": login.username, "password": login.password],
                in: nil, contentWorld: Self.world) as? Bool
            if filled == true {
                Task.detached { logins.used(login.id) }
            }
        }
    }

    private func offerToSave(_ body: [String: Any], origin: String) {
        guard let password = body["password"] as? String, !password.isEmpty, let page else { return }
        let username = body["username"] as? String ?? ""
        let formAction = (body["formActionOrigin"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? origin
        let entry = LoginEntry(
            origin: origin, httpRealm: nil, formActionOrigin: formAction,
            usernameField: body["usernameField"] as? String ?? "",
            passwordField: body["passwordField"] as? String ?? "",
            password: password, username: username)
        let logins = logins
        let host = URL(string: origin)?.host ?? origin
        Task {
            let existing = await Task.detached { logins.existing(entry) }.value
            if let existing, existing.password == password {
                return
            }
            let who = username.isEmpty ? "" : " for \(username)"
            let message = existing == nil ? "Save password\(who) on \(host)?" : "Update password\(who) on \(host)?"
            page.ask(.saveLogin, message: message) { accepted, _ in
                guard accepted else { return }
                Task.detached { logins.save(entry) }
            }
        }
    }

    /// `https://example.com`, with the port only when it isn't the default.
    private static func origin(of security: WKSecurityOrigin) -> String? {
        guard security.protocol == "https" || security.protocol == "http", !security.host.isEmpty else { return nil }
        let defaultPort = security.protocol == "https" ? 443 : 80
        let port = security.port == 0 || security.port == defaultPort ? "" : ":\(security.port)"
        return "\(security.protocol)://\(security.host)\(port)"
    }

    @MainActor private final class WeakHandler: NSObject, WKScriptMessageHandler {
        weak var target: LoginForms?

        init(_ target: LoginForms) {
            self.target = target
        }

        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
            target?.userContentController(controller, didReceive: message)
        }
    }

    /// Finds sign-in forms (a visible password field, and the text field
    /// before it for the username), fills them, and reports submissions.
    private static let script = #"""
    (() => {
      const post = (message) => window.webkit.messageHandlers.zenLogins.postMessage(message);
      const visible = (el) => el && !el.disabled && el.getClientRects().length > 0;
      const passwordFields = (root) =>
        [...(root || document).querySelectorAll('input[type=password]')].filter(visible);
      const usernameFor = (password) => {
        const inputs = [...(password.form ? password.form.elements : document.querySelectorAll('input'))]
          .filter((el) => el instanceof HTMLInputElement && visible(el));
        for (let i = inputs.indexOf(password) - 1; i >= 0; i--) {
          if (['text', 'email', 'tel'].includes(inputs[i].type)) return inputs[i];
        }
        return null;
      };
      const name = (el) => (el ? el.name || el.id || '' : '');
      // Pages built with React and the like watch the value setter and these
      // events, not the attribute.
      const setValue = (el, value) => {
        Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value').set.call(el, value);
        el.dispatchEvent(new Event('input', { bubbles: true }));
        el.dispatchEvent(new Event('change', { bubbles: true }));
      };

      let filled = false;
      window.__zenFillLogin = (username, password) => {
        const field = passwordFields()[0];
        if (!field) return false;
        const user = usernameFor(field);
        if (user && username) setValue(user, username);
        setValue(field, password);
        filled = true;
        return true;
      };

      let lastSubmitted = '';
      const capture = (root) => {
        const field = passwordFields(root).find((el) => el.value);
        if (!field) return;
        const user = usernameFor(field);
        const username = user ? user.value : '';
        const key = username + '\n' + field.value;
        if (key === lastSubmitted) return;
        lastSubmitted = key;
        let formActionOrigin = '';
        try {
          formActionOrigin = new URL(field.form && field.form.action ? field.form.action : location.href).origin;
        } catch (e) {}
        post({ type: 'submit', username, password: field.value,
               usernameField: name(user), passwordField: name(field), formActionOrigin });
      };
      document.addEventListener('submit', (event) => capture(event.target), true);
      // Sites that sign in from script instead of submitting the form.
      document.addEventListener('click', (event) => {
        const button = event.target.closest && event.target.closest('button, input[type=submit]');
        if (button) capture(button.form || undefined);
      }, true);
      document.addEventListener('keydown', (event) => {
        if (event.key === 'Enter' && event.target.type === 'password') capture(event.target.form || undefined);
      }, true);

      document.addEventListener('focusin', (event) => {
        const field = passwordFields()[0];
        if (!filled && field && (event.target === field || event.target === usernameFor(field))) {
          post({ type: 'focus' });
        }
      }, true);

      // Report a sign-in form once; pages that build theirs late get a
      // second look.
      let reported = false;
      const scan = () => {
        if (!reported && passwordFields().length) {
          reported = true;
          post({ type: 'form' });
        }
      };
      scan();
      setTimeout(scan, 1000);
      setTimeout(scan, 3000);
    })();
    """#
}
#endif
