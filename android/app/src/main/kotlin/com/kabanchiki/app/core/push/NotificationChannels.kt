package com.kabanchiki.app.core.push

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.media.AudioAttributes

/**
 * Notification channels with per-category, user-chosen sounds.
 *
 * A channel's sound is frozen at creation, so the sound choice is baked into
 * the channel id (`<base>_<soundKey>_v<CHANNEL_VERSION>`). Changing a sound
 * therefore means creating a fresh channel and dropping the old one — which is
 * exactly what [ensure] does: it reconciles the live channels to the desired
 * set (one per category, at the currently chosen sound) and deletes the rest.
 * Bump [CHANNEL_VERSION] if a shipped sound file's contents ever change.
 */
object NotificationChannels {
    private const val CHANNEL_VERSION = 2

    /** Silent, low-importance channel for the ongoing task/job timer. */
    const val TRACKING = "tracking_v1"

    /** The channel id a notification for [category] should currently post to. */
    fun channelId(context: Context, category: NotificationCategory): String {
        val sound = NotificationSoundStore(context).soundFor(category)
        return channelId(category, sound)
    }

    private fun channelId(category: NotificationCategory, sound: NotificationSound): String =
        "${category.channelBase}_${sound.key}_v$CHANNEL_VERSION"

    /**
     * Bring the system's channels in line with the current choices. Safe to
     * call often (app start, before every push, before the tracking service).
     */
    fun ensure(context: Context) {
        val manager = context.getSystemService(NotificationManager::class.java) ?: return
        val store = NotificationSoundStore(context)

        val desired = NotificationCategory.entries
            .associate { channelId(it, store.soundFor(it)) to it }

        // Drop stale channels: previous versions and previously chosen sounds.
        // The tracking channel is preserved.
        manager.notificationChannels
            .map { it.id }
            .filter { it != TRACKING && it !in desired }
            .forEach { manager.deleteNotificationChannel(it) }

        desired.forEach { (id, category) ->
            createSoundChannel(context, manager, id, category)
        }

        if (manager.getNotificationChannel(TRACKING) == null) {
            manager.createNotificationChannel(
                NotificationChannel(
                    TRACKING,
                    context.getString(com.kabanchiki.app.R.string.channel_tracking),
                    NotificationManager.IMPORTANCE_LOW,
                ),
            )
        }
    }

    /**
     * Persist a new sound for [category] and recreate its channel so the next
     * notification plays it. Returns immediately; the channel is live at once.
     */
    fun applySound(context: Context, category: NotificationCategory, sound: NotificationSound) {
        NotificationSoundStore(context).setSound(category, sound)
        ensure(context)
    }

    private fun createSoundChannel(
        context: Context,
        manager: NotificationManager,
        id: String,
        category: NotificationCategory,
    ) {
        if (manager.getNotificationChannel(id) != null) return
        val sound = NotificationSoundStore(context).soundFor(category)
        val channel = NotificationChannel(
            id,
            context.getString(category.titleRes),
            NotificationManager.IMPORTANCE_HIGH,
        )
        channel.enableVibration(true)
        channel.setSound(
            sound.uri(context),
            AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_NOTIFICATION)
                .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                .build(),
        )
        manager.createNotificationChannel(channel)
    }
}
