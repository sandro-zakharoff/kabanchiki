package com.kabanchiki.app.core.tracking

import android.content.Context
import android.util.Log
import com.kabanchiki.app.core.data.TasksRepository
import dagger.hilt.android.qualifiers.ApplicationContext
import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.postgrest.postgrest
import kotlinx.datetime.Instant
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Offline rule for regular tasks: offline time never counts.
 *
 * The moment connectivity drops is persisted immediately. When the network
 * returns (same service session or a later app start) the recorded gap is
 * reported to the server, which retroactively closes the open work interval:
 * a short outage (< 10 min) resumes the timer, a long one pauses the task.
 */
@Singleton
class OfflineGuard @Inject constructor(
    @ApplicationContext context: Context,
    private val client: SupabaseClient,
    private val tasksRepository: TasksRepository,
) {
    private val prefs = context.getSharedPreferences("offline_guard", Context.MODE_PRIVATE)

    companion object {
        const val RESUME_LIMIT_MS = 10 * 60 * 1000L
        private const val KEY_TASK = "task_id"
        private const val KEY_FROM = "offline_from_ms"
        private const val TAG = "OfflineGuard"
    }

    fun recordOffline(taskId: String, offlineFromMs: Long) {
        prefs.edit().putString(KEY_TASK, taskId).putLong(KEY_FROM, offlineFromMs).apply()
    }

    fun pendingGap(): Pair<String, Long>? {
        val task = prefs.getString(KEY_TASK, null) ?: return null
        val from = prefs.getLong(KEY_FROM, 0L)
        if (from <= 0L) return null
        return task to from
    }

    fun clear() {
        prefs.edit().clear().apply()
    }

    /**
     * Report the gap to the server. Returns true if the timer resumed,
     * false if the task was paused (or nothing was pending).
     */
    suspend fun applyPendingGap(): Boolean {
        val (taskId, fromMs) = pendingGap() ?: return false
        val resume = System.currentTimeMillis() - fromMs < RESUME_LIMIT_MS
        return runCatching {
            client.postgrest.rpc(
                "task_apply_offline_gap",
                buildJsonObject {
                    put("p_task_id", taskId)
                    put("p_offline_from", Instant.fromEpochMilliseconds(fromMs).toString())
                    put("p_resume", resume)
                },
            )
            clear()
            tasksRepository.refresh()
            resume
        }.onFailure { Log.w(TAG, "apply gap failed", it) }.getOrDefault(false)
    }
}
