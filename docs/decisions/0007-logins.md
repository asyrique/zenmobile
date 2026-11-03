# 0007 — Saved passwords: application-services logins, filled in the browser

**Status:** accepted (2026-10-31)

## Context

People expect a browser to remember passwords. Zen desktop and Firefox store theirs in
Firefox Sync's `passwords` collection, and application-services' `logins` component
(Firefox for Android and iOS use it) already reads, writes, merges and syncs that
collection. It encrypts usernames and passwords in its database with a key the app
supplies.

The two engines differ:

- **GeckoView** has Firefox's login manager built in. It finds sign-in forms, fills them,
  and notices submissions. The app provides storage (`Autocomplete.StorageDelegate`) and
  the save and pick prompts (`PromptDelegate.onLoginSave` / `onLoginSelect`), as Firefox
  for Android does.
- **WKWebView** has no login manager. Firefox for iOS injects its own script.

## Decision

1. **One store: application-services `logins`** in the Rust core. It's registered with
   the sync manager, so passwords sync with Firefox and Zen desktop when signed in. Sync
   stays optional (ADR 0006): saving and filling work without an account.
2. **The encryption key** comes from `createKey()`. It's kept in the Keychain on iOS and
   in encrypted preferences on Android (SkipKeychain), in a this-device-only entry. If the
   key is missing when the database already exists (for example after a backup restore,
   which leaves this-device-only keys behind), the app clears the local logins and sync
   downloads them again. A key that can't be *read* (for example before the first unlock)
   is never replaced, since that would make every saved login unreadable.
3. **Android:** Gecko's login manager, with the app's store behind `StorageDelegate`
   (`GeckoLogins.kt`). It runs off the main thread, with JSON across the Swift/Kotlin
   bridge. The save and pick prompts are the app's own (see `GeckoPrompts.kt`). Gecko
   won't fill saved passwords into plain-http pages; we keep that.
4. **iOS:** a small script (`LoginForms.swift`). It finds a visible password field, and
   the text field before it for the username, then:
   - fills a single saved login when the page loads, or offers a choice when a field is
     tapped and there are several;
   - reports submissions, after which the app offers to save the password, or to update it
     if it changed.

   The script runs in its own `WKContentWorld`, in main frames only, so page scripts can't
   reach the message handler or forge its messages. The origin always comes from WebKit,
   never from the script. Logins match by exact origin, as Firefox does by default.
5. **Settings → Passwords** lists, shows, copies and deletes logins. It asks for the
   device's screen lock first, as Firefox does: `LAContext` on iOS, and the keyguard's
   confirm-credential screen on Android. A device without a screen lock has nothing to ask
   for.

## Not yet

- The system AutoFill integrations, so other apps can use these passwords: an AutoFill
  credential provider extension on iOS, and an Android `AutofillService`.
- Generating passwords, and breach alerts.
