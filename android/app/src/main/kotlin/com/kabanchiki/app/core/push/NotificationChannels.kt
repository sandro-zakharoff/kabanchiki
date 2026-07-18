package com.kabanchiki.app.core.push

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.media.AudioAttributes
import android.net.Uri
import com.kabanchiki.app.R

/**
 * Notification channels with custom sounds.
 *
 * A channel's sound is frozen at creation time, so when the sound files
 * change, bump SOUND_VERSION: old channels are deleted and new ones created.
 * Sound files (optional) live in res/raw as: notify_task, notify_job,
 * notify_decision. Without them the system default sound is used.
 */
object NotificationChannels {
    private const val SOUND_VERSION = 1

    const val TASKS = "tasks_v$SOUND_VERSION"
    const val JOB = "job_v$SOUND_VERSION"
    const val DECISIONS = "decisions_v$SOUND_VERSION"
    const val SYSTEM = "system_v$SOUND_VERSION"
    const val TRACKING = "tracking_v1"

    fun ensure(context: Context) {
        val manager = context.getSystemService(NotificationManager::class.java) ?: return

        // Drop channels from previous sound versions.
        manager.notificationChannels
            .filter { it.id !in setOf(TASKS, JOB, DECISIONS, SYSTEM, TRACKING) }
            .forEach { manager.deleteNotificationChannel(it.id) }

        createChannel(context, manager, TASKS, R.string.channel_tasks, "notify_task")
        createChannel(context, manager, JOB, R.string.channel_job, "notify_job")
        createChannel(context, manager, DECISIONS, R.string.channel_decisions, "notify_decision")
        createChannel(context, manager, SYSTEM, R.string.channel_system, "notify_system")

        // Silent low-importance channel for the ongoing task timer.
        if (manager.getNotificationChannel(TRACKING) == null) {
            manager.createNotificationChannel(
                NotificationChannel(
                    TRACKING,
                    context.getString(R.string.channel_tracking),
                    NotificationManager.IMPORTANCE_LOW,
                ),
            )
        }
    }

    private fun createChannel(
        context: Context,
        manager: NotificationManager,
        id: String,
        nameRes: Int,
        soundResName: String,
    ) {
        if (manager.getNotificationChannel(id) != null) return
        val channel = NotificationChannel(id, context.getString(nameRes), NotificationManager.IMPORTANCE_HIGH)
        channel.enableVibration(true)
        soundUri(context, soundResName)?.let { uri ->
            channel.setSound(
                uri,
                AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_NOTIFICATION)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                    .build(),
            )
        }
        manager.createNotificationChannel(channel)
    }

    private fun soundUri(context: Context, resName: String): Uri? {
        // Per-event sound if present, otherwise the shared res/raw/notification file.
        var resId = context.resources.getIdentifier(resName, "raw", context.packageName)
        if (resId == 0) resId = context.resources.getIdentifier("notification", "raw", context.packageName)
        if (resId == 0) return null
        return Uri.parse("android.resource://${context.packageName}/$resId")
    }
}
