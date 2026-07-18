package com.kabanchiki.app.core.tracking

import android.app.Notification
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.IBinder
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import com.kabanchiki.app.MainActivity
import com.kabanchiki.app.R
import com.kabanchiki.app.core.data.JobsRepository
import com.kabanchiki.app.core.data.TimeSync
import com.kabanchiki.app.core.model.JobStatsDto
import com.kabanchiki.app.core.model.formatMoney
import com.kabanchiki.app.core.model.parseInstant
import com.kabanchiki.app.core.push.NotificationChannels
import dagger.hilt.android.AndroidEntryPoint
import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.postgrest.postgrest
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import javax.inject.Inject
import kotlin.math.floor

/**
 * Ongoing notification while an hourly job is RUNNING: a live chronometer
 * plus the current earnings, refreshed every 20 s. The child cannot lose
 * track of a running job even with the app closed.
 */
@AndroidEntryPoint
class JobTrackingService : Service() {

    @Inject lateinit var jobsRepository: JobsRepository
    @Inject lateinit var timeSync: TimeSync
    @Inject lateinit var client: SupabaseClient

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)
    private var loopJob: Job? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val jobId = intent?.getStringExtra(EXTRA_JOB_ID) ?: run {
            stopSelf()
            return START_NOT_STICKY
        }
        NotificationChannels.ensure(this)
        val stat = jobsRepository.stats.value.firstOrNull { it.jobId == jobId }
        startForeground(NOTIFICATION_ID, buildNotification(stat))
        startLoop(jobId)
        return START_REDELIVER_INTENT
    }

    private fun startLoop(jobId: String) {
        loopJob?.cancel()
        loopJob = scope.launch {
            while (true) {
                val stat = jobsRepository.stats.value.firstOrNull { it.jobId == jobId }
                if (stat == null || stat.runningSince == null) {
                    stopSelf()
                    return@launch
                }
                runCatching {
                    NotificationManagerCompat.from(this@JobTrackingService)
                        .notify(NOTIFICATION_ID, buildNotification(stat))
                }
                // Presence: the child counts as online while the job runs.
                runCatching { client.postgrest.rpc("touch_presence") }
                delay(20_000)
            }
        }
    }

    private fun buildNotification(stat: JobStatsDto?): Notification {
        val intent = PendingIntent.getActivity(
            this, 1,
            Intent(this, MainActivity::class.java),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val builder = NotificationCompat.Builder(this, NotificationChannels.TRACKING)
            .setSmallIcon(R.drawable.ic_notification)
            .setContentTitle(stat?.title ?: getString(R.string.job_title))
            .setOngoing(true)
            .setSilent(true)
            .setContentIntent(intent)

        if (stat != null) {
            val snapshot = parseInstant(stat.snapshotAt)
            val extra = if (stat.runningSince != null && snapshot != null) {
                (timeSync.nowServer() - snapshot).inWholeSeconds.coerceAtLeast(0)
            } else 0L
            val totalSeconds = stat.totalSeconds + extra
            val earned = floor((stat.earnedSeconds + extra) / 3600.0 * stat.hourlyRate * 100) / 100.0
            builder
                .setContentText(getString(R.string.job_earned_now) + ": " + formatMoney(earned))
                .setUsesChronometer(true)
                .setWhen(System.currentTimeMillis() - totalSeconds * 1000)
        }
        return builder.build()
    }

    override fun onDestroy() {
        loopJob?.cancel()
        super.onDestroy()
    }

    companion object {
        private const val NOTIFICATION_ID = 1002
        private const val EXTRA_JOB_ID = "job_id"

        fun start(context: Context, jobId: String) {
            val intent = Intent(context, JobTrackingService::class.java)
                .putExtra(EXTRA_JOB_ID, jobId)
            runCatching { context.startForegroundService(intent) }
        }

        fun stop(context: Context) {
            context.stopService(Intent(context, JobTrackingService::class.java))
        }
    }
}
