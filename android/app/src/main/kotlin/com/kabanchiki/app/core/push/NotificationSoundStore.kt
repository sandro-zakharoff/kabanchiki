package com.kabanchiki.app.core.push

import android.content.Context

/**
 * Persists the chosen sound per notification category.
 *
 * Backed by SharedPreferences on purpose: the channel builder needs the choice
 * *synchronously*, and it can run from a process just spawned by FCM to deliver
 * a push (no coroutine scope, no time to await a DataStore flow). A tiny,
 * synchronous key-value store is exactly the right tool here.
 */
class NotificationSoundStore(context: Context) {

    private val prefs = context.applicationContext
        .getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    fun soundFor(category: NotificationCategory): NotificationSound {
        val stored = prefs.getString(category.key, null)
        return if (stored == null) category.default else NotificationSound.byKey(stored)
    }

    fun setSound(category: NotificationCategory, sound: NotificationSound) {
        prefs.edit().putString(category.key, sound.key).apply()
    }

    private companion object {
        const val PREFS = "notification_sounds"
    }
}
