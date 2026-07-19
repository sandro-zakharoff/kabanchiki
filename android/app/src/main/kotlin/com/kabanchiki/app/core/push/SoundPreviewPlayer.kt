package com.kabanchiki.app.core.push

import android.content.Context
import android.media.AudioAttributes
import android.media.MediaPlayer

/**
 * Plays a single notification sound for previewing in Settings. Uses the
 * notification audio stream, so the preview is exactly as loud as the real
 * notification will be. Only one preview plays at a time; [release] frees the
 * player and must be called when the picker closes.
 */
class SoundPreviewPlayer(private val context: Context) {

    private var player: MediaPlayer? = null

    fun play(sound: NotificationSound) {
        release()
        player = MediaPlayer().apply {
            setAudioAttributes(
                AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_NOTIFICATION)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                    .build(),
            )
            setOnCompletionListener { release() }
            setOnErrorListener { _, _, _ -> release(); true }
            runCatching {
                setDataSource(context, sound.uri(context))
                prepare()
                start()
            }.onFailure { release() }
        }
    }

    fun release() {
        player?.runCatching { stop() }
        player?.release()
        player = null
    }
}
