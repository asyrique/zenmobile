# 0004 — No cookie sync

**Status:** accepted

We looked at one-way cookie sync from desktop to mobile (a companion WebExtension that
exports allowlisted cookies through `storage.sync`, a Cloudflare relay, or a custom Sync
engine). Neither Firefox nor Zen syncs cookies today.

Dropped:

- Session cookies are bearer credentials. Moving them between devices widens the blast
  radius of any bug or leak.
- Many sites (Google, banks) bind sessions to a device or fingerprint and would log the
  user out, or flag the account.
- Logins already sync through Firefox Sync's `passwords` collection, which we can add
  later (application-services `logins`), and that's the supported path.
