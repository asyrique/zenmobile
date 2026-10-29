# 0006 — Signing in to Firefox is optional

**Status:** accepted (2026-10-29)

## Context

Zen Mobile's headline features (tabs open on desktop, Zen Spaces, Essentials) need a
Firefox account, because they come from Firefox Sync. The first version of the app led
with that: a signed-out start page offered only "Sign in", so the account looked like the
price of entry.

That's the wrong default for a browser:

- Browsing itself needs nothing from the account.
- Not everyone uses Firefox Sync, and some people want to try the app before connecting
  an account that holds their passwords and history.
- Sign-in runs as Firefox for Android (decision [0003](0003-firefox-oauth-client.md)),
  which some people will reasonably want to think about before agreeing.

## Decision

The account is an optional extra. Nothing in the app requires it, and the app asks once.

- **Start page:** leads with "Search or enter address". When signed out it shows a
  "Sync with Firefox" card explaining what signing in adds, with **Sign in** and
  **Not now**. "Not now" is remembered (`@AppStorage("syncPromptDismissed")`), so the card
  doesn't come back.
- **Settings is the permanent home of sign-in.** The Firefox account section says signing
  in is optional and what it syncs. Sign out lives there too.
- **Screens that depend on sync explain instead of dead-ending.** Signed out, the desktop
  tabs list explains what it would show and links to sign-in. The Space sheet explains
  that Spaces come from Zen desktop and points to Settings.
- **Re-authentication is the one exception.** If a signed-in account needs the user to
  sign in again (expired session, changed password), the card returns, without "Not now".
  Sync is already on in that case and silently broken otherwise. Browsing still isn't
  blocked.
- **No sync work runs without an account.** `ZenSyncManager.sync` only runs when signed
  in. Signed out, the stores stay empty and nothing contacts Mozilla's servers.

## Consequences

- The app is useful from first launch, and the end-to-end tests exercise this path: they
  browse without signing in.
- Fewer people will sign in than with a gate, so desktop tabs and Spaces will be less
  visible. The empty states carry that discovery instead.
- "Not now" lives on the device. Reinstalling the app or clearing its data brings the card
  back once, which is acceptable.
- Future features that need the account (send tab, history and bookmarks sync, logins)
  must follow the same rule: offer it where it's relevant, never require it to browse.
