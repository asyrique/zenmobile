import Foundation
#if canImport(BackgroundTasks) && !os(Android)
import BackgroundTasks
#endif
#if canImport(UserNotifications) && !os(Android)
import UserNotifications
#endif

/// Looks for tabs other devices sent while Zen is in the background, and
/// says so in a notification. Firefox Accounts only pushes to Mozilla's
/// own apps (ADR 0008), so these are periodic checks: iOS background app
/// refresh, when the system grants it, and an Android job about every
/// 15 minutes. While the app is open, AppModel checks every minute.
@MainActor enum BackgroundChecks {
    static let identifier = "io.github.asyrique.zenmobile.sentTabs"

    /// At launch, before it finishes (iOS requires that).
    static func register() {
        #if canImport(BackgroundTasks) && !os(Android)
        BGTaskScheduler.shared.register(forTaskWithIdentifier: identifier, using: nil) { task in
            let handle = UncheckedSendable(value: task)
            let work = Task { @MainActor in
                schedule()
                await checkAndNotify()
                handle.value.setTaskCompleted(success: true)
            }
            handle.value.expirationHandler = { work.cancel() }
        }
        #endif
    }

    /// Signed in or out: start or stop the checks, and ask (once, the
    /// system remembers) to show notifications.
    static func accountChanged(signedIn: Bool) {
        #if os(Android)
        if signedIn {
            AndroidBackgroundChecks.schedule()
        } else {
            AndroidBackgroundChecks.cancel()
        }
        #elseif canImport(BackgroundTasks)
        if signedIn {
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
        } else {
            BGTaskScheduler.shared.cancel(taskRequestWithIdentifier: identifier)
        }
        #endif
    }

    /// When the app goes to the background (iOS; Android's job repeats on
    /// its own).
    static func schedule() {
        #if canImport(BackgroundTasks) && !os(Android)
        let request = BGAppRefreshTaskRequest(identifier: identifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            logger.error("Scheduling the sent-tabs check failed: \(error)")
        }
        #endif
    }

    static func checkAndNotify() async {
        let tabs = await AppModel.shared.checkForSentTabs()
        for tab in tabs {
            let title = tab.sender.map { "Tab from \($0)" } ?? "Tab from another device"
            let body = tab.title.isEmpty ? tab.url.absoluteString : tab.title
            #if os(Android)
            AndroidNotifications.sentTab(title: title, body: body)
            #elseif canImport(UserNotifications)
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
            try? await UNUserNotificationCenter.current().add(request)
            #endif
        }
    }

    /// iOS hands the task over on its own queue; it's only used on the
    /// main actor.
    private struct UncheckedSendable<Value>: @unchecked Sendable {
        let value: Value
    }
}

/// The Android job's way in (SentTabsJob.kt). Call on the main thread.
/* SKIP @bridge */public final class BackgroundSentTabs {
    /// Checks for sent tabs, notifies about them, then calls `done`.
    /* SKIP @bridge */public static func check(done: @escaping () -> Void) {
        nonisolated(unsafe) let finish = done
        Task { @MainActor in
            await BackgroundChecks.checkAndNotify()
            finish()
        }
    }
}

#if SKIP
import androidx.compose.runtime.Composable

// Kotlin side (transpiled by Skip). Public so Kotlin doesn't rename it on
// the JVM, where Skip's bridge looks it up.

/// The periodic job (SentTabsJob.kt).
struct AndroidBackgroundChecks {
    public static func schedule() {
        SentTabsJob.schedule(ProcessInfo.processInfo.androidContext)
    }

    public static func cancel() {
        SentTabsJob.cancel(ProcessInfo.processInfo.androidContext)
    }
}

struct AndroidNotifications {
    public static func sentTab(title: String, body: String) {
        SentTabsJob.notify(ProcessInfo.processInfo.androidContext, title, body)
    }
}

/// Asks for Android 13's notification permission (SentTabsJob.kt).
struct NotificationPermissionComposer : ContentComposer {
    init() {
    }

    @Composable func Compose(context: ComposeContext) {
        NotificationPermissionEffect()
    }
}
#endif
