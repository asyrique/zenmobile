# 0003 — Sign in as Firefox for Android

**Status:** accepted (for personal and experimental use)

## Context

Sync data is end-to-end encrypted with `kSync`, which Mozilla's accounts server only
releases (as a scoped key) to OAuth clients it has registered for the `oldsync` scope.
Mozilla does not register third-party Sync clients.

Alternatives considered:

- **Apply to Mozilla for a client id.** Legitimate, but Sync is excluded for third
  parties, so this would likely be refused and would block the project meanwhile.
- **Self-host.** Pointing Zen at a self-hosted *storage* server
  (`identity.sync.tokenserver.uri`) is easy, but doesn't help: the key still comes from
  Mozilla's FxA. Self-hosting *FxA itself* (auth, content, profile servers, MySQL,
  Redis, email) and setting `identity.fxaccounts.autoconfig.uri` on desktop does work,
  but it's heavy and needs a fresh account.

## Decision

Use Firefox for Android's public client id `a2270f727f45f648` with redirect
`https://accounts.firefox.com/oauth/success/a2270f727f45f648`. Forks of Firefox do the
same, and application-services' own example uses it.

## Consequences

- Works today with the user's existing Mozilla account and Zen desktop.
- Grey area: Mozilla can block it at any time. Fine for personal use; **not** for a
  store release under the Zen name without talking to Mozilla first.
- The FxA sign-in pages and the device list will say "Firefox", not "Zen".
- Only `core/zen-core/src/config.rs` knows any of this. `FxaServer::Custom` and
  `token_server_url_override` already support a self-hosted stack.
