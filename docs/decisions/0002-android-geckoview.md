# 0002 — GeckoView on Android

**Status:** accepted

iOS is required to use WebKit. On Android we use **GeckoView**, the engine of Firefox for
Android and the same Gecko as Zen desktop:

- Same rendering and compatibility as desktop Zen.
- WebExtension support (uBlock Origin) and built-in extensions for app↔page messaging.
- Costs: roughly 60–80 MB of app size, and a heavier build (Mozilla Maven, ABI splits).

The Android System WebView was rejected: it's Chromium, has no extension support, and
would make Zen Mobile on Android a different browser from Zen.
