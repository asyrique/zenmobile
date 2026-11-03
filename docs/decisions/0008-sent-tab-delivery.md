# 0008 — Sent tabs arrive by checking, not push

**Status:** accepted (2026-11-03)

## Context

Firefox delivers a sent tab instantly with a push message. The device registers a push
subscription with Firefox Accounts, and FxA posts to it when a command is waiting. We
checked whether Zen Mobile can do the same:

- **FxA only accepts Mozilla's push servers.** fxa-auth-server rejects a device's
  `pushCallback` unless it matches `push.allowedServerRegex`, which by default allows only
  `*.services.mozilla.com` and Mozilla's autopush staging and dev hosts
  ([config](https://github.com/mozilla/fxa/blob/72f75c808ced14324969abf6fc40c670bd8939b4/packages/fxa-auth-server/config/index.ts#L1978-L1985),
  [devices.js](https://github.com/mozilla/fxa/blob/72f75c808ced14324969abf6fc40c670bd8939b4/packages/fxa-auth-server/lib/devices.js#L15-L44)).
  A relay of our own is out.
- **Mozilla's push service only reaches Mozilla's apps.** It forwards to APNs and FCM only
  for app IDs configured in its own secrets (Firefox, Focus and so on). Any other app ID is
  refused (autopush-rs `routers/apns`, `routers/fcm`). Our app's device tokens can't be
  reached without Mozilla adding our credentials.
- **A WebSocket isn't enough.** Mozilla's push service also speaks WebSocket, as desktop
  Firefox does, and that gives an endpoint FxA accepts. But iOS won't keep the socket open
  in the background. On Android it would need a permanent foreground service and
  notification, and our own push client. Mozilla's terms for third-party clients are
  unclear.

## Decision

Check for commands instead:

- **App open:** every minute (`AppModel.setInForeground`).
- **Background:**
  - **iOS:** background app refresh (`BGAppRefreshTask`), which the system runs when it
    chooses.
  - **Android:** a periodic `JobScheduler` job, at its shortest period of 15 minutes, that
    survives restarts.

  Each sent tab found in the background gets a notification. If the browser isn't
  running, the tab waits in a small inbox file and opens at the next launch.
- **Unchanged:** sync and coming to the foreground also check, as before.

## Consequences

- A sent tab shows up within a minute while Zen is open. In the background it can take
  15 minutes or more, and on iOS it can take much longer.
- Instant delivery would need Mozilla to register Zen Mobile's APNs and FCM credentials
  with their push service. If they do, the app would register a push subscription and pass
  messages to `FirefoxAccount.handlePushMessage`.
