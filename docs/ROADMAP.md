# Zen Mobile — Roadmap

Each milestone ends with something usable on a phone. Status as of this writing:
**M0 in progress.**

## M0 — Prove the stack *(in progress)*

Goal: retire the risks in [decision 0001](decisions/0001-skip-fuse.md) before writing
real UI.

- [x] Rust core links application-services (fxa-client, sync15, tabs) plus our
      `zen-spaces` crate into one library; 17 Rust tests.
- [x] Read-only `spaces` engine + resolver for Zen's Spaces, Essentials, folders,
      splits and containers, tested against fixtures modelled on desktop's projections.
- [x] UniFFI Swift bindings generated from the library and compiled as a SwiftPM
      package; 6 Swift tests run against the real Rust library, including
      a live OAuth flow start against accounts.firefox.com.
- [x] Rust core, the ZenCore Swift package and the whole Skip Fuse app (SwiftUI
      views included) built for Android arm64 with the Swift Android SDK.
- [x] NSS built for iOS and Android (`scripts/build-nss.sh`), and
      `scripts/build-core-{apple,android}.sh` producing the xcframework and `.so` files.
- [x] App generated with `skip init` (Skip 1.9.20); first cut of the browser, Space
      sheet, tab switcher, desktop tabs and sign-in views.
- [x] The Android APK launches and renders natively on arm64 Android (Redroid in CI).
- [x] End-to-end browsing test green on iOS (simulator) and Android (Redroid).
- [ ] Sign in and see desktop tabs on a device.
- [x] GeckoView embedded in a Skip view: loads a URL and reports the page title
      (checked by the Android end-to-end test).
- [ ] GeckoView intercepts the OAuth redirect (needs a real sign-in).
- [x] CI on macos-latest (arm64 only): Rust + Swift tests, the iOS app, and the
      Android APK (Gradle + GeckoView, Kotlin from Skip).

## M1 — Desktop tabs on the phone

- [ ] Sign in (OAuth in our web view, or scan desktop's "Connect another device" QR code).
- [x] Account state in Keychain (iOS) / encrypted preferences (Android), via
      skip-keychain.
- [ ] Sync on launch, on foreground and on pull-to-refresh.
- [ ] **Desktop tabs list** grouped by device → tap to open.
- [x] Minimal browser: address bar, back/forward/reload (and the Android back
      button), the Arc-style bottom bar.
- [x] Each tab keeps its page (WKWebView / GeckoSession) while other tabs are
      shown, and tabs survive a restart.

## M2 — Zen Spaces

- **Space sheet** (see [UX.md](UX.md)): gradient, Essentials grid, folder outline,
  Spaces bar, swipe between Spaces.
- One phone tab per desktop pin or Essential.
- Empty state when desktop hasn't enabled Spaces sync.
- Upload this phone's tabs so desktop's "Synced tabs" shows them.

## M3 — A browser people keep using

- Tab carousel, tabs grouped by Space.
- History and bookmarks (application-services `places`), with URL bar suggestions.
- Send tab both ways and close tabs remotely (FxA device commands, push via APNs/FCM).
- Content blocking: WKContentRuleList on iOS; uBlock Origin as a built-in extension
  in GeckoView.
- Logins (application-services `logins`) with platform autofill.

## M4 — Write-back (risky; needs a test harness first)

- Pin, unpin and reorder on mobile, uploaded to the `spaces` collection.
- Prerequisite: an integration harness that runs Zen desktop (Twilight) against a
  test account, so round-trips are tested before any mobile write reaches a real
  sidebar.

## Not planned

- Cookie sync ([decision 0004](decisions/0004-no-cookie-sync.md)).
- Split view on phones.
