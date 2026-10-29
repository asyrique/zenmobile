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
      package; 6 Swift tests run against the real Rust library on Linux, including
      a live OAuth flow start against accounts.firefox.com.
- [x] Rust core, the ZenCore Swift package and the whole Skip Fuse app (SwiftUI
      views included) cross-compiled and linked for Android arm64 on Linux with the
      Swift 6.3 Android SDK. The local link used placeholder NSS libraries; CI links
      the real ones.
- [ ] NSS built for iOS and Android (`application-services/libs/build-all.sh`), and
      `scripts/build-core-{ios,android}.sh` producing the xcframework and `.so` files.
- [x] App generated with `skip init` (Skip 1.9.20); first cut of the browser, Space
      sheet, tab switcher, desktop tabs and sign-in views.
- [ ] Run it: iOS simulator and an Android emulator/device, sign in, see desktop tabs.
- [ ] GeckoView embedded in a Skip view: load a URL, observe navigations, intercept
      the OAuth redirect. The code compiles into the APK; not yet run on a device.
- [x] CI green. Linux: Rust + Swift tests, NSS + core for Android, and the Android
      debug APK (Gradle + GeckoView, Kotlin from Skip). macOS (main, PRs, manual
      runs only): NSS + core for iOS and the iOS simulator app.

## M1 — Desktop tabs on the phone

- Sign in (OAuth in our web view, or scan desktop's "Connect another device" QR code).
- Account state in Keychain / Keystore.
- Sync on launch, on foreground and on pull-to-refresh.
- **Desktop tabs list** grouped by device → tap to open.
- Minimal browser: one web view, address bar, back/forward, the Arc-style bottom bar.

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
