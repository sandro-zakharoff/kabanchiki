package com.kabanchiki.app.core.tracking

import android.app.Notification
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.os.IBinder
import android.os.SystemClock
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import com.kabanchiki.app.MainActivity
import com.kabanchiki.app.R
import com.kabanchiki.app.core.data.TasksRepository
import com.kabanchiki.app.core.data.TimeSync
import com.kabanchiki.app.core.model.parseInstant
import com.kabanchiki.app.core.push.NotificationCategory
import com.kabanchiki.app.core.push.NotificationChannels
import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.postgrest.postgrest
import dagger.hilt.android.AndroidEntryPoint
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import javax.inject.Inject

/**
 * Foreground service that runs while a regular task is in progress:
 *  - keeps a live chronometer notification;
 *  - watches connectivity and enforces the offline rule via [OfflineGuard]:
 *    a local sound notification the moment the network drops, auto-resume if
 *    it returns within 10 minutes, auto-pause otherwise.
 *
 * It is started only from the UI (the app is in the foreground then), so the
 * FGS-from-background restriction never applies.
 */
@AndroidEntryPoint
class TaskTrackingService : Service() {

    @Inject lateinit var tasksRepository: TasksRepository
    @Inject lateinit var timeSync: TimeSync
    @Inject lateinit var offlineGuard: OfflineGuard
    @Inject lateinit var client: SupabaseClient

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)
    private var watchJob: Job? = null
    private var heartbeatJob: Job? = null
    private var offlineDeadlineJob: Job? = null
    private var connectivity: ConnectivityManager? = null
    private var callback: ConnectivityManager.NetworkCallback? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val taskId = intent?.getStringExtra(EXTRA_TASK_ID) ?: run {
            stopSelf()
            return START_NOT_STICKY
        }
        NotificationChannels.ensure(this)
        startForeground(NOTIFICATION_ID, buildChronometer(taskId))
        watchTask(taskId)
        watchConnectivity(taskId)
        startHeartbeat(taskId)
        return START_REDELIVER_INTENT
    }

    /** Keeps the child "online" for the parent app while a task is running
     *  (even if the app UI was swiped away) and refreshes the live earnings
     *  line in the notification. */
    private fun startHeartbeat(taskId: String) {
        if (heartbeatJob?.isActive == true) return
        heartbeatJob = scope.launch {
            while (true) {
                if (hasInternet()) {
                    runCatching { client.postgrest.rpc("touch_presence") }
                }
                runCatching {
                    NotificationManagerCompat.from(this@TaskTrackingService)
                        .notify(NOTIFICATION_ID, buildChronometer(taskId))
                }
                delay(20_000)
            }
        }
    }

    // ------------------------------------------------------------ task state

    private fun watchTask(taskId: String) {
        watchJob?.cancel()
        watchJob = scope.launch {
            tasksRepository.tasks.collect { tasks ->
                val task = tasks.firstOrNull { it.id == taskId }
                if (task == null || task.status != "in_progress") {
                    stopSelf()
                } else {
                    runCatching {
                        NotificationManagerCompat.from(this@TaskTrackingService)
                            .notify(NOTIFICATION_ID, buildChronometer(taskId))
                    }
                }
            }
        }
    }

    private fun buildChronometer(taskId: String): Notification {
        val task = tasksRepository.tasks.value.firstOrNull { it.id == taskId }
        val open = tasksRepository.openIntervals.value[taskId]
        val startedAt = parseInstant(open?.startedAt)
        val elapsedMs = if (startedAt != null) {
            (timeSync.nowServer() - startedAt).inWholeMilliseconds.coerceAtLeast(0) +
                (task?.totalSeconds ?: 0) * 1000L
        } else (task?.totalSeconds ?: 0) * 1000L

        val intent = PendingIntent.getActivity(
            this, 0,
            Intent(this, MainActivity::class.java),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        // For hourly-paid tasks show live earnings; otherwise the fixed reward.
        val contentText = if (task != null && task.rewardType == "hourly") {
            val earned = kotlin.math.floor(elapsedMs / 3600000.0 * task.rewardAmount * 100) / 100.0
            getString(R.string.task_earned) + ": " + com.kabanchiki.app.core.model.formatMoney(earned)
        } else {
            getString(R.string.tracking_in_progress)
        }
        return NotificationCompat.Builder(this, NotificationChannels.TRACKING)
            .setSmallIcon(R.drawable.ic_notification)
            .setContentTitle(task?.title ?: getString(R.string.app_name))
            .setContentText(contentText)
            .setUsesChronometer(true)
            .setWhen(System.currentTimeMillis() - elapsedMs)
            .setOngoing(true)
            .setSilent(true)
            .setContentIntent(intent)
            .build()
    }

    // ------------------------------------------------------------ connectivity

    private fun watchConnectivity(taskId: String) {
        connectivity = getSystemService(ConnectivityManager::class.java)
        callback = object : ConnectivityManager.NetworkCallback() {
            override fun onAvailable(network: Network) {
                scope.launch { onNetworkBack() }
            }

            override fun onLost(network: Network) {
                if (!hasInternet()) {
                    onNetworkLost(taskId)
                }
            }
        }
        connectivity?.registerDefaultNetworkCallback(callback!!)
        if (!hasInternet()) onNetworkLost(taskId)
    }

    private fun hasInternet(): Boolean {
        val cm = connectivity ?: return true
        val caps = cm.getNetworkCapabilities(cm.activeNetwork) ?: return false
        return caps.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
    }

    private fun onNetworkLost(taskId: String) {
        if (offlineGuard.pendingGap() != null) return
        offlineGuard.recordOffline(taskId, System.currentTimeMillis())
        notifyEvent(
            getString(R.string.offline_lost_title),
            getString(R.string.offline_lost_body),
        )
        offlineDeadlineJob?.cancel()
        offlineDeadlineJob = scope.launch {
            delay(OfflineGuard.RESUME_LIMIT_MS)
            // Still offline after the limit: the task will be paused as soon
            // as the network allows us to tell the server.
            if (offlineGuard.pendingGap() != null) {
                notifyEvent(
                    getString(R.string.offline_paused_title),
                    getString(R.string.offline_paused_body),
                )
            }
        }
    }

    private suspend fun onNetworkBack() {
        if (offlineGuard.pendingGap() == null) return
        offlineDeadlineJob?.cancel()
        val resumed = offlineGuard.applyPendingGap()
        if (resumed) {
            notifyEvent(
                getString(R.string.offline_back_title),
                getString(R.string.offline_back_body),
            )
        } else {
            notifyEvent(
                getString(R.string.offline_paused_title),
                getString(R.string.offline_paused_body),
            )
        }
    }

    private fun notifyEvent(title: String, body: String) {
        runCatching {
            val channel = NotificationChannels.channelId(this, NotificationCategory.SYSTEM)
            val notification = NotificationCompat.Builder(this, channel)
                .setSmallIcon(R.drawable.ic_notification)
                .setContentTitle(title)
                .setContentText(body)
                .setStyle(NotificationCompat.BigTextStyle().bigText(body))
                .setAutoCancel(true)
                .setPriority(NotificationCompat.PRIORITY_HIGH)
                .build()
            NotificationManagerCompat.from(this).notify(System.currentTimeMillis().toInt(), notification)
        }
    }

    override fun onDestroy() {
        callback?.let { runCatching { connectivity?.unregisterNetworkCallback(it) } }
        watchJob?.cancel()
        heartbeatJob?.cancel()
        offlineDeadlineJob?.cancel()
        super.onDestroy()
    }

    companion object {
        private const val NOTIFICATION_ID = 1001
        private const val EXTRA_TASK_ID = "task_id"

        fun start(context: Context, taskId: String) {
            val intent = Intent(context, TaskTrackingService::class.java)
                .putExtra(EXTRA_TASK_ID, taskId)
            runCatching { context.startForegroundService(intent) }
        }

        fun stop(context: Context) {
            context.stopService(Intent(context, TaskTrackingService::class.java))
        }
    }
}
