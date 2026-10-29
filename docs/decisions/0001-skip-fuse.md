# 0001 — One SwiftUI codebase via Skip Fuse

**Status:** accepted, pending prototype (Roadmap milestone 0)

## Context

We want one UI codebase in Swift for iOS and Android. Options considered:

1. **SwiftUI + Skip Fuse.** Swift compiled natively for Android with the official Swift
   Android SDK; Skip bridges SwiftUI to Jetpack Compose.
2. **SwiftUI + Jetpack Compose.** Two native UIs over the shared Rust core. This is
   Mozilla's approach for Firefox.
3. **Swift logic on both, hand-written Compose UI.**

## Decision

Option 1, gated on a prototype that proves:

- Swift on Android can call `libzen_core` through the same generated UniFFI Swift we
  use on iOS.
- A GeckoView can be embedded in a Skip view and driven from Swift (load URL, observe
  navigation, intercept the OAuth redirect).
- The Android app builds in CI.

If any of these fail, fall back to option 2. The Rust core and its bindings are
unaffected (UniFFI also emits Kotlin), so only UI code is at risk.

## Consequences

- App builds for both platforms happen on a Mac (CI: `macos-latest`), as Skip intends.
- The browser surface (web view, gestures, toolbar animation) is platform-specific
  regardless, behind a small `BrowserEngine` protocol.
- App size grows by the Swift runtime on Android, on top of GeckoView.
