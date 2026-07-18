package com.kabanchiki.app.core.location

import android.Manifest
import android.app.AlarmManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.location.Geocoder
import android.os.Build
import android.util.Log
import androidx.core.content.ContextCompat
import androidx.datastore.preferences.core.booleanPreferencesKey
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.longPreferencesKey
import androidx.datastore.preferences.core.stringPreferencesKey
import androidx.datastore.preferences.preferencesDataStore
import androidx.hilt.work.HiltWorker
import androidx.work.CoroutineWorker
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.ExistingWorkPolicy
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.WorkerParameters
import com.google.android.gms.location.LocationServices
import com.google.android.gms.location.Priority
import com.google.android.gms.tasks.CancellationTokenSource
import dagger.assisted.Assisted
import dagger.assisted.AssistedInject
import dagger.hilt.android.AndroidEntryPoint
import dagger.hilt.android.qualifiers.ApplicationContext
import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.auth.auth
import io.github.jan.supabase.postgrest.postgrest
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.tasks.await
import kotlinx.coroutines.withTimeout
import kotlinx.datetime.Instant
import kotlinx.serialization.Serializable
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import java.util.Locale
import java.util.concurrent.TimeUnit
import javax.inject.Inject
import javax.inject.Singleton

private const val TAG = "LocationReporter"
private const val WORK_NAME = "location-report"
private const val ALARM_REQUEST = 1917
private const val INTERVAL_MS = 15L * 60 * 1000
private const val QUEUE_CAP = 200

private val Context.locationPrefs by preferencesDataStore("location_prefs")
private val KEY_ENABLED = booleanPreferencesKey("enabled")
private val KEY_LAST_SENT = longPreferencesKey("last_sent_ms")
private val KEY_QUEUE = stringPreferencesKey("queue_json")

@Serializable
data class QueuedPoint(
    val lat: Double,
    val lng: Double,
    val accuracy: Float,
    val locality: String,
    val atMs: Long,
)

/** Opt-in flag, last delivery time and the offline point queue. */
@Singleton
class LocationPrefs @Inject constructor(@ApplicationContext private val context: Context) {
    private val json = Json { ignoreUnknownKeys = true }

    val enabled: Flow<Boolean> = context.locationPrefs.data.map { it[KEY_ENABLED] == true }
    val lastSentMs: Flow<Long> = context.locationPrefs.data.map { it[KEY_LAST_SENT] ?: 0L }

    suspend fun setEnabled(value: Boolean) {
        context.locationPrefs.edit { it[KEY_ENABLED] = value }
    }

    suspend fun markSent(now: Long = System.currentTimeMillis()) {
        context.locationPrefs.edit { it[KEY_LAST_SENT] = now }
    }

    suspend fun queue(): List<QueuedPoint> =
        runCatching {
            json.decodeFromString<List<QueuedPoint>>(
                context.locationPrefs.data.first()[KEY_QUEUE] ?: "[]",
            )
        }.getOrDefault(emptyList())

    suspend fun saveQueue(points: List<QueuedPoint>) {
        context.locationPrefs.edit {
            it[KEY_QUEUE] = json.encodeToString(points.takeLast(QUEUE_CAP))
        }
    }
}

/**
 * Captures one point and delivers the whole queue.
 *
 * The point is queued first and the queue is flushed oldest-first, so a dead
 * network never loses points — they go out in a batch when connectivity is
 * back, each with its true capture time (location_report p_at).
 */
@Singleton
class LocationCore @Inject constructor(
    @ApplicationContext private val context: Context,
    private val client: SupabaseClient,
    private val prefs: LocationPrefs,
) {
    suspend fun reportOnce(): Boolean {
        if (!prefs.enabled.first()) return true
        if (client.auth.currentSessionOrNull() == null) return true
        if (!LocationPermissions.hasForeground(context)) return true

        // 1. capture (failures don't lose the already-queued points)
        val captured = runCatching {
            @Suppress("MissingPermission")
            val location = LocationServices.getFusedLocationProviderClient(context)
                .getCurrentLocation(
                    Priority.PRIORITY_BALANCED_POWER_ACCURACY,
                    CancellationTokenSource().token,
                ).await()
            location?.let {
                QueuedPoint(
                    lat = it.latitude, lng = it.longitude, accuracy = it.accuracy,
                    locality = geocode(it.latitude, it.longitude), atMs = System.currentTimeMillis(),
                )
            }
        }.onFailure { Log.w(TAG, "capture failed", it) }.getOrNull()

        val pending = (prefs.queue() + listOfNotNull(captured)).takeLast(QUEUE_CAP)
        if (pending.isEmpty()) return true
        prefs.saveQueue(pending)

        // 2. flush oldest-first; stop at the first network failure
        var delivered = 0
        for (p in pending) {
            val ok = runCatching {
                client.postgrest.rpc(
                    "location_report",
                    buildJsonObject {
                        put("p_lat", p.lat)
                        put("p_lng", p.lng)
                        put("p_accuracy", p.accuracy)
                        put("p_locality", p.locality)
                        put("p_at", Instant.fromEpochMilliseconds(p.atMs).toString())
                    },
                )
            }.onFailure { Log.w(TAG, "send failed (${pending.size - delivered} queued)", it) }.isSuccess
            if (!ok) break
            delivered++
        }
        prefs.saveQueue(pending.drop(delivered))
        if (delivered > 0) prefs.markSent()
        return delivered == pending.size
    }

    private fun geocode(lat: Double, lng: Double): String = runCatching {
        @Suppress("DEPRECATION")
        Geocoder(context, Locale("uk"))
            .getFromLocation(lat, lng, 1)
            ?.firstOrNull()
            ?.let { it.locality ?: it.subAdminArea ?: it.adminArea }
    }.getOrNull().orEmpty()
}

object LocationPermissions {
    fun hasForeground(context: Context): Boolean =
        ContextCompat.checkSelfPermission(context, Manifest.permission.ACCESS_FINE_LOCATION) ==
            PackageManager.PERMISSION_GRANTED ||
            ContextCompat.checkSelfPermission(context, Manifest.permission.ACCESS_COARSE_LOCATION) ==
            PackageManager.PERMISSION_GRANTED

    fun hasBackground(context: Context): Boolean =
        Build.VERSION.SDK_INT < Build.VERSION_CODES.Q ||
            ContextCompat.checkSelfPermission(context, Manifest.permission.ACCESS_BACKGROUND_LOCATION) ==
            PackageManager.PERMISSION_GRANTED
}

/**
 * Scheduling. Primary: an AlarmManager chain with setAndAllowWhileIdle — Doze
 * grants such alarms a window roughly every 15 minutes, exactly our cadence,
 * and (unlike WorkManager periodic jobs) they are not deferred for hours.
 * Backup: the 15-minute WorkManager periodic request stays armed in case the
 * alarm chain is ever broken by the system.
 */
@Singleton
class LocationScheduler @Inject constructor(
    @ApplicationContext private val context: Context,
    private val prefs: LocationPrefs,
) {
    fun start() {
        val periodic = PeriodicWorkRequestBuilder<LocationWorker>(15, TimeUnit.MINUTES).build()
        WorkManager.getInstance(context)
            .enqueueUniquePeriodicWork(WORK_NAME, ExistingPeriodicWorkPolicy.KEEP, periodic)
        armAlarm()
        reportNow() // first point right away, not in 15 minutes
    }

    fun stop() {
        WorkManager.getInstance(context).cancelUniqueWork(WORK_NAME)
        WorkManager.getInstance(context).cancelUniqueWork("$WORK_NAME-now")
        alarmManager().cancel(alarmIntent())
    }

    fun reportNow() {
        WorkManager.getInstance(context).enqueueUniqueWork(
            "$WORK_NAME-now", ExistingWorkPolicy.REPLACE,
            OneTimeWorkRequestBuilder<LocationWorker>().build(),
        )
    }

    /** Arms the next link of the alarm chain (called after every fire). */
    fun armAlarm() {
        alarmManager().setAndAllowWhileIdle(
            AlarmManager.RTC_WAKEUP,
            System.currentTimeMillis() + INTERVAL_MS,
            alarmIntent(),
        )
    }

    /** App start / device boot: re-arm everything if the switch is on. */
    fun ensureScheduled() {
        val enabled = runBlocking { runCatching { prefs.enabled.first() }.getOrDefault(false) }
        if (enabled) start()
    }

    private fun alarmManager() =
        context.getSystemService(Context.ALARM_SERVICE) as AlarmManager

    private fun alarmIntent(): PendingIntent =
        PendingIntent.getBroadcast(
            context, ALARM_REQUEST,
            Intent(context, LocationAlarmReceiver::class.java),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
}

/** WorkManager entry (backup path + on-demand "report now"). */
@HiltWorker
class LocationWorker @AssistedInject constructor(
    @Assisted context: Context,
    @Assisted params: WorkerParameters,
    private val core: LocationCore,
) : CoroutineWorker(context, params) {
    override suspend fun doWork(): Result =
        // Never retry-with-backoff: the next tick handles it, and the queue
        // preserves the points anyway. Backoff only starves the schedule.
        runCatching { core.reportOnce() }.let { Result.success() }
}

/** Alarm chain entry: re-arm first, then report within the broadcast window. */
@AndroidEntryPoint
class LocationAlarmReceiver : BroadcastReceiver() {
    @Inject lateinit var core: LocationCore
    @Inject lateinit var scheduler: LocationScheduler
    @Inject lateinit var prefs: LocationPrefs

    override fun onReceive(context: Context, intent: Intent) {
        val enabled = runBlocking { runCatching { prefs.enabled.first() }.getOrDefault(false) }
        if (!enabled) return
        scheduler.armAlarm()
        val result = goAsync()
        CoroutineScope(SupervisorJob() + Dispatchers.IO).launch {
            try {
                withTimeout(50_000) { core.reportOnce() } // broadcast budget ~60s
            } catch (e: Exception) {
                Log.w(TAG, "alarm report failed", e)
            } finally {
                result.finish()
            }
        }
    }
}

/** Re-arm after reboot (alarms and work requests don't survive it by default). */
@AndroidEntryPoint
class LocationBootReceiver : BroadcastReceiver() {
    @Inject lateinit var scheduler: LocationScheduler

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == Intent.ACTION_BOOT_COMPLETED) {
            scheduler.ensureScheduled()
        }
    }
}
