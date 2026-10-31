import Foundation
#if canImport(WebKit)
import WebKit
#endif

/// Blocks trackers, on by default (Settings → Block trackers).
///
/// Android: GeckoView's Enhanced Tracking Protection, Firefox's own, at its
/// standard level. iOS: WebKit has no tracker list of its own, so the app
/// builds a content rule list from EasyPrivacy (the tracker list behind
/// uBlock Origin and Adblock Plus; GPLv3 / CC BY-SA, fetched rather than
/// bundled) and refreshes it every few days.
@MainActor enum TrackerBlocking {
    static let settingKey = "blockTrackers"

    static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: settingKey) as? Bool ?? true
    }

    /// Applies the setting; call at launch and when it changes.
    static func apply() async {
        let enabled = isEnabled
        #if os(Android)
        GeckoTrackingProtection.setEnabled(enabled: enabled)
        #elseif canImport(UIKit)
        await ContentBlocker.shared.setEnabled(enabled)
        #endif
    }
}

#if !os(Android) && canImport(UIKit)

/// The iOS tracker rule list, shared by every web view.
@MainActor final class ContentBlocker {
    static let shared = ContentBlocker()
    /// Posted when `ruleList` changes; web views swap their rules.
    static let didChange = Notification.Name("ZenContentBlockerDidChange")

    private static let identifier = "zen-easyprivacy"
    private static let listURL = URL(string: "https://easylist.to/easylist/easyprivacy.txt")!
    private static let updatedKey = "trackerListUpdated"
    /// EasyPrivacy says it expires after 4 days.
    private static let maxAge: TimeInterval = 4 * 24 * 60 * 60

    private(set) var ruleList: WKContentRuleList?

    func setEnabled(_ enabled: Bool) async {
        guard enabled else {
            update(nil)
            return
        }
        guard let store = WKContentRuleListStore.default() else { return }
        let stored = (try? await store.lookUpContentRuleList(forIdentifier: Self.identifier)) ?? nil
        let updated = UserDefaults.standard.object(forKey: Self.updatedKey) as? Date ?? .distantPast
        if let stored, Date().timeIntervalSince(updated) < Self.maxAge {
            update(stored)
            return
        }
        // Use what's there while fetching a fresh list.
        if let stored {
            update(stored)
        }
        do {
            let (data, _) = try await URLSession.shared.data(from: Self.listURL)
            let rules = await Task.detached { Self.rules(fromEasyList: String(decoding: data, as: UTF8.self)) }.value
            guard let compiled = try await store.compileContentRuleList(forIdentifier: Self.identifier, encodedContentRuleList: rules) else {
                return
            }
            UserDefaults.standard.set(Date(), forKey: Self.updatedKey)
            // The setting may have been turned off meanwhile.
            if TrackerBlocking.isEnabled {
                update(compiled)
            }
        } catch {
            logger.error("Updating the tracker list failed: \(error)")
        }
    }

    private func update(_ list: WKContentRuleList?) {
        ruleList = list
        NotificationCenter.default.post(name: Self.didChange, object: nil)
    }

    /// WebKit content rules from an Adblock Plus-format list. Only its plain
    /// domain rules (`||tracker.example^`, optionally `$third-party`), which
    /// are nearly all of EasyPrivacy; the rest need a full filter engine.
    nonisolated static func rules(fromEasyList list: String) -> String {
        var rules: [String] = []
        for line in list.split(whereSeparator: \.isNewline) {
            guard line.hasPrefix("||") else { continue }
            var rule = line.dropFirst(2)
            var thirdPartyOnly = false
            if rule.hasSuffix("^$third-party") {
                rule = rule.dropLast("$third-party".count)
                thirdPartyOnly = true
            }
            guard rule.hasSuffix("^") else { continue }
            let domain = rule.dropLast()
            guard !domain.isEmpty, domain.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "." || $0 == "-" }) else { continue }
            let escaped = domain.replacingOccurrences(of: ".", with: "\\\\.")
            let loadType = thirdPartyOnly ? #","load-type":["third-party"]"# : ""
            rules.append(#"{"trigger":{"url-filter":"^https?://([^/]*\\.)?\#(escaped)[/:]"\#(loadType)},"action":{"type":"block"}}"#)
        }
        return "[" + rules.joined(separator: ",") + "]"
    }
}

#endif

#if SKIP
// Kotlin side (transpiled by Skip). Public so Kotlin doesn't rename it on
// the JVM, where Skip's bridge looks it up.

/// Gecko's Enhanced Tracking Protection for every tab.
struct GeckoTrackingProtection {
    /// Read when the runtime is created, and applied to it if it already is.
    // SKIP @nobridge
    static var enabled = true

    public static func setEnabled(enabled: Bool) {
        GeckoTrackingProtection.enabled = enabled
        ZenGeckoRuntime.applyTrackingProtection()
    }
}
#endif
