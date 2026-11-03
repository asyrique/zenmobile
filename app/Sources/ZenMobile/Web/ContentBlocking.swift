import Foundation
#if canImport(WebKit)
import WebKit
#endif

/// Blocks trackers (on by default) and ads (off by default), from
/// Settings → Privacy.
///
/// Android: trackers with GeckoView's Enhanced Tracking Protection, Firefox's
/// own, at its standard level; ads with uBlock Origin, installed from
/// addons.mozilla.org as on Firefox for Android (GeckoAdBlocking.kt).
///
/// iOS: WebKit has no lists of its own, so the app builds content rule lists
/// from EasyPrivacy (trackers) and EasyList (ads), the lists behind uBlock
/// Origin and Adblock Plus (GPLv3 / CC BY-SA, fetched rather than bundled),
/// and refreshes them every few days.
@MainActor enum ContentBlocking {
    static let trackersKey = "blockTrackers"
    static let adsKey = "blockAds"

    static var blocksTrackers: Bool {
        UserDefaults.standard.object(forKey: trackersKey) as? Bool ?? true
    }

    static var blocksAds: Bool {
        UserDefaults.standard.object(forKey: adsKey) as? Bool ?? false
    }

    /// Applies the settings; call at launch and when they change.
    static func apply() async {
        #if os(Android)
        GeckoContentBlocking.set(trackers: blocksTrackers, ads: blocksAds)
        #elseif canImport(UIKit)
        await ContentBlocker.shared.update()
        #endif
    }
}

#if !os(Android) && canImport(UIKit)

/// The iOS content rule lists, shared by every web view.
@MainActor final class ContentBlocker {
    static let shared = ContentBlocker()
    /// Posted when `ruleLists` changes; web views swap their rules.
    static let didChange = Notification.Name("ZenContentBlockerDidChange")

    /// An Adblock Plus-format list turned into WebKit rules.
    private struct BlockList {
        let identifier: String
        let url: URL
        /// Whether the setting that enables it is on.
        let isEnabled: @MainActor () -> Bool

        var updatedKey: String { "\(identifier).updated" }
    }

    private static let lists = [
        BlockList(identifier: "zen-easyprivacy", url: URL(string: "https://easylist.to/easylist/easyprivacy.txt")!, isEnabled: { ContentBlocking.blocksTrackers }),
        BlockList(identifier: "zen-easylist", url: URL(string: "https://easylist.to/easylist/easylist.txt")!, isEnabled: { ContentBlocking.blocksAds }),
    ]
    /// The lists say they expire after 4 days.
    private static let maxAge: TimeInterval = 4 * 24 * 60 * 60

    /// The compiled lists that are on, by identifier.
    private var compiled: [String: WKContentRuleList] = [:]

    var ruleLists: [WKContentRuleList] {
        Self.lists.compactMap { compiled[$0.identifier] }
    }

    /// Loads the lists that are on (compiling a fresh copy when the stored
    /// one is old or missing) and drops the ones that are off.
    func update() async {
        for list in Self.lists {
            if list.isEnabled() {
                await load(list)
            } else if compiled.removeValue(forKey: list.identifier) != nil {
                notify()
            }
        }
    }

    private func load(_ list: BlockList) async {
        guard let store = WKContentRuleListStore.default() else { return }
        let stored = await withCheckedContinuation { continuation in
            store.lookUpContentRuleList(forIdentifier: list.identifier) { ruleList, _ in
                continuation.resume(returning: UncheckedSendable(value: ruleList))
            }
        }.value
        // Use what's there, even while fetching a fresh copy.
        if let stored {
            set(stored, for: list)
        }
        let updated = UserDefaults.standard.object(forKey: list.updatedKey) as? Date ?? .distantPast
        if stored != nil, Date().timeIntervalSince(updated) < Self.maxAge {
            return
        }
        do {
            let (data, _) = try await URLSession.shared.data(from: list.url)
            let rules = await Task.detached { Self.rules(fromEasyList: String(decoding: data, as: UTF8.self)) }.value
            guard let fresh = try await store.compileContentRuleList(forIdentifier: list.identifier, encodedContentRuleList: rules) else {
                return
            }
            UserDefaults.standard.set(Date(), forKey: list.updatedKey)
            // The setting may have been turned off meanwhile.
            if list.isEnabled() {
                set(fresh, for: list)
            }
        } catch {
            logger.error("Updating \(list.identifier) failed: \(error)")
        }
    }

    private func set(_ ruleList: WKContentRuleList, for list: BlockList) {
        compiled[list.identifier] = ruleList
        notify()
    }

    private func notify() {
        NotificationCenter.default.post(name: Self.didChange, object: nil)
    }

    /// WebKit hands the stored list to a callback; it's only used on the
    /// main actor.
    private struct UncheckedSendable<Value>: @unchecked Sendable {
        let value: Value
    }

    /// WebKit content rules from an Adblock Plus-format list. Only its plain
    /// domain rules (`||tracker.example^`, optionally `$third-party`), which
    /// are nearly all of EasyPrivacy and most of EasyList's blocking rules;
    /// the rest (paths, element hiding) need a full filter engine.
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

/// Content blocking for every tab: Gecko's Enhanced Tracking Protection and
/// uBlock Origin (GeckoAdBlocking.kt).
struct GeckoContentBlocking {
    /// Read when the runtime is created, and applied to it if it already is.
    // SKIP @nobridge
    static var trackers = true

    public static func set(trackers: Bool, ads: Bool) {
        GeckoContentBlocking.trackers = trackers
        GeckoAdBlocking.enabled = ads
        ZenGeckoRuntime.applyContentBlocking()
    }
}
#endif
