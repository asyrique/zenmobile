// Plain Kotlin, copied into the Android build as is (see GeckoPrompts.kt).
package zen.mobile

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.job.JobInfo
import android.app.job.JobParameters
import android.app.job.JobScheduler
import android.app.job.JobService
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.ui.platform.LocalContext

/**
 * Checks for tabs other devices sent, about every 15 minutes while signed
 * in (Android's shortest period), and notifies about them
 * (BackgroundChecks.swift). Firefox Accounts only pushes to Mozilla's own
 * apps, so this is the background path.
 */
class SentTabsJob : JobService() {
    override fun onStartJob(params: JobParameters): Boolean {
        BackgroundSentTabs.check { jobFinished(params, false) }
        return true
    }

    // Stopped early: try again later.
    override fun onStopJob(params: JobParameters): Boolean = true

    companion object {
        private const val JOB_ID = 4201
        private const val CHANNEL = "sent_tabs"
        private var nextNotification = 0

        fun schedule(context: Context) {
            val scheduler = context.getSystemService(JobScheduler::class.java) ?: return
            if (scheduler.getPendingJob(JOB_ID) != null) return
            val job = JobInfo.Builder(JOB_ID, ComponentName(context, SentTabsJob::class.java))
                .setPeriodic(15 * 60 * 1000L)
                .setRequiredNetworkType(JobInfo.NETWORK_TYPE_ANY)
                .setPersisted(true)
                .build()
            scheduler.schedule(job)
        }

        fun cancel(context: Context) {
            context.getSystemService(JobScheduler::class.java)?.cancel(JOB_ID)
        }

        /** A notification that opens the app, where the tab is waiting. */
        fun notify(context: Context, title: String, body: String) {
            if (Build.VERSION.SDK_INT >= 33 &&
                context.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) return
            val manager = context.getSystemService(NotificationManager::class.java) ?: return
            manager.createNotificationChannel(
                NotificationChannel(CHANNEL, "Tabs from other devices", NotificationManager.IMPORTANCE_DEFAULT))
            val open = context.packageManager.getLaunchIntentForPackage(context.packageName)
                ?.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP)
            val tap = open?.let { PendingIntent.getActivity(context, 0, it, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT) }
            val notification = Notification.Builder(context, CHANNEL)
                .setSmallIcon(context.applicationInfo.icon)
                .setContentTitle(title)
                .setContentText(body)
                .setAutoCancel(true)
                .apply { tap?.let { setContentIntent(it) } }
                .build()
            manager.notify(nextNotification++, notification)
        }
    }
}

/** Asks for Android 13's notification permission, if not granted yet. */
@Composable
internal fun NotificationPermissionEffect() {
    if (Build.VERSION.SDK_INT < 33) return
    val context = LocalContext.current
    val request = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { }
    LaunchedEffect(Unit) {
        if (context.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {
            request.launch(Manifest.permission.POST_NOTIFICATIONS)
        }
    }
}
