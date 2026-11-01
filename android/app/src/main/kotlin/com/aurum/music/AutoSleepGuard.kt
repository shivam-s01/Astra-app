// ─────────────────────────────────────────────────────────────────
// Astra Music (Aurum) — Proprietary Software
// Copyright (c) 2026 Shivam Sharma. All rights reserved.
// Unauthorized copying, modification, distribution, or use of this
// file, via any medium, is strictly prohibited. See LICENSE.
// ─────────────────────────────────────────────────────────────────

package com.aurum.music

import android.app.AlarmManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.os.Build
import android.os.SystemClock
import android.util.Log

object AutoSleepGuard {
    private const val TAG = "AutoSleepGuard"
    private const val PREFS_NAME = "FlutterSharedPreferences"
    private const val KEY_DURATION_HOURS = "flutter.auto_sleep_guard_hours"
    private const val KEY_LAST_AUTO_PAUSE_AT = "flutter.auto_sleep_guard_last_pause_at"
    private const val KEY_LAST_AUTO_PAUSE_CONSUMED = "flutter.auto_sleep_guard_last_pause_consumed"
    private const val KEY_ENABLED = "flutter.auto_sleep_guard_enabled"

    private const val ACTION_CHECK = "com.aurum.music.action.AUTO_SLEEP_GUARD_CHECK"
    private const val REQUEST_CODE = 7742

    private const val NOTIFICATION_CHANNEL_ID = "aurum_auto_sleep_guard"
    private const val NOTIFICATION_ID = 1002

    private const val DEFAULT_GUARD_HOURS = 3

    enum class DurationHours(val hours: Int) { THREE(3), FIVE(5) }

    @Volatile
    private var sleepTimerActive: Boolean = false

    @Volatile
    private var lastActivityAtMs: Long = System.currentTimeMillis()

    fun setSleepTimerActive(active: Boolean) {
        sleepTimerActive = active
    }

    fun recordActivity(context: Context) {
        lastActivityAtMs = System.currentTimeMillis()
        if (awaitingConfirmation) {
            awaitingConfirmation = false
            dismissConfirmationPrompt(context)
        }
        scheduleNextCheck(context)
    }

    fun onPlaybackStateChanged(context: Context, isPlaying: Boolean) {
        if (isPlaying) {
            recordActivity(context)
        } else {
            cancelScheduledCheck(context)
        }
    }

    private fun prefs(context: Context): SharedPreferences =
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    fun durationHours(context: Context, isSignedIn: Boolean): Int {
        if (!isSignedIn) return DEFAULT_GUARD_HOURS
        val stored = prefs(context).getInt(KEY_DURATION_HOURS, DEFAULT_GUARD_HOURS)
        return if (stored == DurationHours.FIVE.hours) DurationHours.FIVE.hours else DurationHours.THREE.hours
    }

    fun setDurationHours(context: Context, hours: Int) {
        val clamped = if (hours == DurationHours.FIVE.hours) DurationHours.FIVE.hours else DurationHours.THREE.hours
        prefs(context).edit().putInt(KEY_DURATION_HOURS, clamped).apply()
    }

    fun isEnabled(context: Context): Boolean =
        prefs(context).getBoolean(KEY_ENABLED, true)

    fun setEnabled(context: Context, enabled: Boolean) {
        prefs(context).edit().putBoolean(KEY_ENABLED, enabled).apply()
        if (!enabled) {
            awaitingConfirmation = false
            dismissConfirmationPrompt(context)
            dismissPauseNotification(context)
            cancelScheduledCheck(context)
        } else {
            recordActivity(context)
        }
    }

    fun peekLastAutoPause(context: Context): Long? {
        val p = prefs(context)
        if (p.getBoolean(KEY_LAST_AUTO_PAUSE_CONSUMED, true)) return null
        val at = p.getLong(KEY_LAST_AUTO_PAUSE_AT, -1L)
        return if (at > 0) at else null
    }

    fun consumeLastAutoPause(context: Context) {
        prefs(context).edit().putBoolean(KEY_LAST_AUTO_PAUSE_CONSUMED, true).apply()
    }

    private fun alarmManager(context: Context) =
        context.getSystemService(Context.ALARM_SERVICE) as AlarmManager

    private fun pendingIntent(context: Context): PendingIntent {
        val intent = Intent(context, AutoSleepGuardReceiver::class.java).apply {
            action = ACTION_CHECK
        }
        val flags = PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        return PendingIntent.getBroadcast(context, REQUEST_CODE, intent, flags)
    }

    private fun scheduleNextCheck(context: Context) {
        if (!isEnabled(context)) return
        if (sleepTimerActive) {
            cancelScheduledCheck(context)
            return
        }
        val isSignedIn = try {
            AuthStateBridge.isSignedIn
        } catch (e: Exception) {
            false
        }
        if (!isSignedIn) {
            cancelScheduledCheck(context)
            return
        }

        val hours = durationHours(context, isSignedIn)
        val triggerAtElapsed = SystemClock.elapsedRealtime() + hours * 60L * 60L * 1000L

        try {
            alarmManager(context).setAndAllowWhileIdle(
                AlarmManager.ELAPSED_REALTIME_WAKEUP,
                triggerAtElapsed,
                pendingIntent(context),
            )
        } catch (e: Exception) {
            Log.e(TAG, "Failed to schedule Auto Sleep Guard alarm: ${e.message}", e)
        }
    }

    private fun cancelScheduledCheck(context: Context) {
        try {
            alarmManager(context).cancel(pendingIntent(context))
        } catch (e: Exception) {
            Log.e(TAG, "Failed to cancel Auto Sleep Guard alarm: ${e.message}", e)
        }
    }

    internal fun onAlarmFired(context: Context) {
        if (!isEnabled(context) || sleepTimerActive) return

        val engine = AurumMediaSessionService.sharedEngine ?: return
        val player = engine.player
        val isActivelyPlaying = player.playWhenReady && player.mediaItemCount > 0
        if (!isActivelyPlaying) return

        val isSignedIn = try { AuthStateBridge.isSignedIn } catch (e: Exception) { false }
        if (!isSignedIn) return

        val hoursMs = durationHours(context, isSignedIn) * 60L * 60L * 1000L
        val elapsedSinceActivity = System.currentTimeMillis() - lastActivityAtMs

        if (elapsedSinceActivity < hoursMs) {
            scheduleNextCheck(context)
            return
        }

        if (awaitingConfirmation) {
            pauseNow(context)
            return
        }

        postConfirmationPrompt(context)
        awaitingConfirmation = true
        scheduleGraceTimeout(context)
    }

    @Volatile
    private var awaitingConfirmation: Boolean = false

    private const val GRACE_WINDOW_MS = 8L * 60L * 1000L

    private fun scheduleGraceTimeout(context: Context) {
        val triggerAtElapsed = SystemClock.elapsedRealtime() + GRACE_WINDOW_MS
        try {
            alarmManager(context).setAndAllowWhileIdle(
                AlarmManager.ELAPSED_REALTIME_WAKEUP,
                triggerAtElapsed,
                pendingIntent(context),
            )
        } catch (e: Exception) {
            Log.e(TAG, "Failed to schedule Auto Sleep Guard grace timeout: ${e.message}", e)
        }
    }

    internal fun onConfirmedAwake(context: Context) {
        awaitingConfirmation = false
        dismissConfirmationPrompt(context)
        recordActivity(context)
    }

    internal fun onConfirmedAsleep(context: Context) {
        pauseNow(context)
    }

    private fun pauseNow(context: Context) {
        awaitingConfirmation = false
        dismissConfirmationPrompt(context)

        val engine = AurumMediaSessionService.sharedEngine ?: return
        try {
            engine.sleepFadeOutAndPause(fadeMs = 8000)
        } catch (e: Exception) {
            Log.e(TAG, "Auto Sleep Guard pause failed: ${e.message}", e)
            return
        }

        val now = System.currentTimeMillis()
        prefs(context).edit()
            .putLong(KEY_LAST_AUTO_PAUSE_AT, now)
            .putBoolean(KEY_LAST_AUTO_PAUSE_CONSUMED, false)
            .apply()

        postPauseNotification(context)
    }

    private fun postPauseNotification(context: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            val granted = context.checkSelfPermission(android.Manifest.permission.POST_NOTIFICATIONS) ==
                android.content.pm.PackageManager.PERMISSION_GRANTED
            if (!granted) return
        }
        createNotificationChannelIfNeeded(context)

        val launchIntent = context.packageManager.getLaunchIntentForPackage(context.packageName)
        val contentIntent = launchIntent?.let {
            PendingIntent.getActivity(
                context, 0, it,
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
            )
        }

        val hours = durationHours(context, true)
        val notification = Notification.Builder(context, NOTIFICATION_CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_widget_pause)
            .setContentTitle("Playback paused")
            .setContentText("Inactive for $hours hours — tap to resume")
            .setAutoCancel(true)
            .setContentIntent(contentIntent)
            .build()

        try {
            val manager = context.getSystemService(NotificationManager::class.java) ?: return
            manager.notify(NOTIFICATION_ID, notification)
        } catch (e: Exception) {
            Log.e(TAG, "Failed to post Auto Sleep Guard notification: ${e.message}", e)
        }
    }

    private const val CONFIRM_NOTIFICATION_ID = 1003
    private const val ACTION_CONFIRM_AWAKE = "com.aurum.music.action.AUTO_SLEEP_GUARD_YES"
    private const val ACTION_CONFIRM_ASLEEP = "com.aurum.music.action.AUTO_SLEEP_GUARD_NO"

    private fun postConfirmationPrompt(context: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            pauseNow(context)
            return
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            val granted = context.checkSelfPermission(android.Manifest.permission.POST_NOTIFICATIONS) ==
                android.content.pm.PackageManager.PERMISSION_GRANTED
            if (!granted) {
                pauseNow(context)
                return
            }
        }
        createNotificationChannelIfNeeded(context)

        val bodyTapIntent = context.packageManager.getLaunchIntentForPackage(context.packageName)
            ?.let {
                it.putExtra("auto_sleep_guard_confirm", true)
                PendingIntent.getActivity(
                    context, 1, it,
                    PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
                )
            }

        val yesIntent = Intent(context, AutoSleepGuardActionReceiver::class.java).apply {
            action = ACTION_CONFIRM_AWAKE
        }
        val yesPendingIntent = PendingIntent.getBroadcast(
            context, 2, yesIntent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

        val noIntent = Intent(context, AutoSleepGuardActionReceiver::class.java).apply {
            action = ACTION_CONFIRM_ASLEEP
        }
        val noPendingIntent = PendingIntent.getBroadcast(
            context, 3, noIntent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

        val notification = Notification.Builder(context, NOTIFICATION_CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_widget_pause)
            .setContentTitle("Still there?")
            .setContentText("No activity for a while — pausing soon to save battery")
            .setOngoing(true)
            .setContentIntent(bodyTapIntent)
            .addAction(Notification.Action.Builder(0, "Yes, I'm here", yesPendingIntent).build())
            .addAction(Notification.Action.Builder(0, "No, pause", noPendingIntent).build())
            .build()

        try {
            val manager = context.getSystemService(NotificationManager::class.java) ?: return
            manager.notify(CONFIRM_NOTIFICATION_ID, notification)
        } catch (e: Exception) {
            Log.e(TAG, "Failed to post Auto Sleep Guard confirmation prompt: ${e.message}", e)
        }
    }

    private fun dismissConfirmationPrompt(context: Context) {
        try {
            val manager = context.getSystemService(NotificationManager::class.java) ?: return
            manager.cancel(CONFIRM_NOTIFICATION_ID)
        } catch (e: Exception) {
            Log.e(TAG, "Failed to dismiss Auto Sleep Guard confirmation prompt: ${e.message}", e)
        }
    }

    private fun dismissPauseNotification(context: Context) {
        try {
            val manager = context.getSystemService(NotificationManager::class.java) ?: return
            manager.cancel(NOTIFICATION_ID)
        } catch (e: Exception) {
            Log.e(TAG, "Failed to dismiss Auto Sleep Guard pause notification: ${e.message}", e)
        }
    }

    private fun createNotificationChannelIfNeeded(context: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = context.getSystemService(NotificationManager::class.java) ?: return
        if (manager.getNotificationChannel(NOTIFICATION_CHANNEL_ID) != null) return
        val channel = NotificationChannel(
            NOTIFICATION_CHANNEL_ID,
            "Auto Sleep Guard",
            NotificationManager.IMPORTANCE_LOW,
        )
        manager.createNotificationChannel(channel)
    }
}

object AuthStateBridge {
    @Volatile
    var isSignedIn: Boolean = false
}

class AutoSleepGuardReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        AutoSleepGuard.onAlarmFired(context.applicationContext)
    }
}

class AutoSleepGuardActionReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val appContext = context.applicationContext
        when (intent.action) {
            "com.aurum.music.action.AUTO_SLEEP_GUARD_YES" -> AutoSleepGuard.onConfirmedAwake(appContext)
            "com.aurum.music.action.AUTO_SLEEP_GUARD_NO" -> AutoSleepGuard.onConfirmedAsleep(appContext)
        }
    }
}
