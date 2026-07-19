package com.kabanchiki.app.core.push

import android.content.Context
import android.net.Uri
import com.kabanchiki.app.R

/**
 * The catalog of notification sounds the assignee can choose from.
 *
 * Single source of truth: to add another sound later, drop an `.ogg` into
 * res/raw, add one entry here and one label string. Everything else — the
 * settings list, the preview, the channels — picks it up automatically.
 *
 * [key] is the stable identifier persisted in preferences and baked into the
 * channel id; never rename a key once shipped, or a user's saved choice is lost.
 */
enum class NotificationSound(
    val key: String,
    val rawResId: Int,
    val labelRes: Int,
) {
    CLASSIC("classic", R.raw.notif_classic, R.string.sound_classic),
    AURORA("aurora", R.raw.notif_aurora, R.string.sound_aurora),
    CHIME("chime", R.raw.notif_chime, R.string.sound_chime),
    RIPPLE("ripple", R.raw.notif_ripple, R.string.sound_ripple),
    BEACON("beacon", R.raw.notif_beacon, R.string.sound_beacon),
    ;

    fun uri(context: Context): Uri =
        Uri.parse("android.resource://${context.packageName}/$rawResId")

    companion object {
        /** Resolve a persisted key back to a sound, falling back to [CLASSIC]. */
        fun byKey(key: String?): NotificationSound =
            entries.firstOrNull { it.key == key } ?: CLASSIC
    }
}
