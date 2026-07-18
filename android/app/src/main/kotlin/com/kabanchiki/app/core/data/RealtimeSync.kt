package com.kabanchiki.app.core.data

import android.util.Log
import com.kabanchiki.app.core.supabase.ApplicationScope
import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.postgrest.postgrest
import io.github.jan.supabase.realtime.PostgresAction
import io.github.jan.supabase.realtime.channel
import io.github.jan.supabase.realtime.postgresChangeFlow
import io.github.jan.supabase.realtime.realtime
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.launchIn
import kotlinx.coroutines.flow.onEach
import kotlinx.coroutines.launch
import javax.inject.Inject
import javax.inject.Singleton

/**
 * While the app is on screen: one realtime channel over every table the child
 * can see; any change triggers a repository refresh (RLS filters rows for us).
 * A slow safety-net poll covers missed events after Doze or network drops.
 */
@Singleton
class RealtimeSync @Inject constructor(
    private val client: SupabaseClient,
    private val auth: AuthRepository,
    private val tasksRepository: TasksRepository,
    private val jobsRepository: JobsRepository,
    private val bonusesRepository: BonusesRepository,
    private val balanceRepository: BalanceRepository,
    private val timeSync: TimeSync,
    @ApplicationScope private val scope: CoroutineScope,
) {
    private var job: Job? = null

    fun start() {
        if (job?.isActive == true) return
        job = scope.launch {
            try {
                refreshAll()
                val channel = client.channel("kabanchiki-child")
                listOf("tasks", "job_members", "job_sessions", "jobs", "withdrawals",
                    "bonuses", "ledger_entries").forEach { table ->
                    channel.postgresChangeFlow<PostgresAction>(schema = "public") {
                        this.table = table
                    }.onEach {
                        runCatching { refreshAll() }
                            .onFailure { e -> Log.w(TAG, "refresh after change failed", e) }
                    }.launchIn(this)
                }
                channel.subscribe(blockUntilSubscribed = false)

                // Presence heartbeat every 20 s, full safety-net refresh every 60 s.
                var beat = 0
                while (true) {
                    runCatching { touchPresence() }
                        .onFailure { e -> Log.w(TAG, "presence failed", e) }
                    runCatching { signOutIfBlocked() }
                        .onFailure { e -> Log.w(TAG, "block check failed", e) }
                    delay(20_000)
                    beat++
                    if (beat % 3 == 0) {
                        runCatching { refreshAll() }
                            .onFailure { e -> Log.w(TAG, "periodic refresh failed", e) }
                    }
                }
            } catch (e: Exception) {
                Log.w(TAG, "realtime loop failed, retrying in 10s", e)
                delay(10_000)
                job = null
                start()
            }
        }
    }

    suspend fun refreshAll() {
        timeSync.sync()
        tasksRepository.refresh()
        jobsRepository.refresh()
        bonusesRepository.refresh()
        balanceRepository.refresh()
    }

    private suspend fun touchPresence() {
        client.postgrest.rpc("touch_presence")
    }

    /** If the parent blocked this account, drop the session immediately. */
    private suspend fun signOutIfBlocked() {
        val profile = auth.loadProfile() ?: return
        if (profile.blocked) {
            auth.logout()
        }
    }

    fun stop() {
        job?.cancel()
        job = null
        scope.launch {
            runCatching { client.realtime.removeAllChannels() }
        }
        tasksRepository.clear()
        jobsRepository.clear()
        bonusesRepository.clear()
        balanceRepository.clear()
    }

    private companion object {
        const val TAG = "RealtimeSync"
    }
}
