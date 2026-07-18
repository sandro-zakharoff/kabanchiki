package com.kabanchiki.app.core.data

import android.app.DownloadManager
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.net.Uri
import android.os.Build
import android.util.Log
import androidx.core.content.FileProvider
import com.kabanchiki.app.BuildConfig
import com.kabanchiki.app.core.model.AppReleaseDto
import dagger.hilt.android.qualifiers.ApplicationContext
import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.postgrest.from
import io.github.jan.supabase.postgrest.query.Order
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import java.io.File
import javax.inject.Inject
import javax.inject.Singleton

/**
 * Self-hosted updates: read the latest published release, and if it is newer
 * than the installed build, offer to download and install it (no Play Store).
 */
@Singleton
class UpdateRepository @Inject constructor(
    @ApplicationContext private val context: Context,
    private val client: SupabaseClient,
) {
    private val _available = MutableStateFlow<AppReleaseDto?>(null)
    /** Non-null when a newer release than the installed one exists. */
    val available: StateFlow<AppReleaseDto?> = _available.asStateFlow()

    private val _downloading = MutableStateFlow(false)
    val downloading: StateFlow<Boolean> = _downloading.asStateFlow()

    suspend fun check() {
        val latest = runCatching {
            client.from("app_releases").select {
                filter { eq("platform", "android") }
                order("version_code", Order.DESCENDING)
                limit(1)
            }.decodeList<AppReleaseDto>().firstOrNull()
        }.getOrNull() ?: return
        _available.value = if (latest.versionCode > BuildConfig.VERSION_CODE) latest else null
    }

    /** Public Storage URL of the release APK. */
    private fun apkUrl(release: AppReleaseDto): String =
        "${BuildConfig.SUPABASE_URL}/storage/v1/object/public/app-releases/${release.apkPath}"

    fun downloadAndInstall(release: AppReleaseDto) {
        if (_downloading.value) return
        _downloading.value = true
        val dm = context.getSystemService(Context.DOWNLOAD_SERVICE) as DownloadManager
        val fileName = "kabanchiki-${release.versionCode}.apk"
        val target = File(context.getExternalFilesDir(null), fileName)
        if (target.exists()) target.delete()

        val request = DownloadManager.Request(Uri.parse(apkUrl(release)))
            .setTitle("Kabanchiki ${release.versionName}")
            .setDestinationInExternalFilesDir(context, null, fileName)
            .setNotificationVisibility(DownloadManager.Request.VISIBILITY_VISIBLE_NOTIFY_COMPLETED)
        val id = dm.enqueue(request)

        val receiver = object : android.content.BroadcastReceiver() {
            override fun onReceive(ctx: Context, intent: Intent) {
                val done = intent.getLongExtra(DownloadManager.EXTRA_DOWNLOAD_ID, -1)
                if (done != id) return
                context.unregisterReceiver(this)
                _downloading.value = false
                runCatching { install(target) }
                    .onFailure { Log.w("UpdateRepository", "install failed", it) }
            }
        }
        val filter = IntentFilter(DownloadManager.ACTION_DOWNLOAD_COMPLETE)
        if (Build.VERSION.SDK_INT >= 33) {
            context.registerReceiver(receiver, filter, Context.RECEIVER_EXPORTED)
        } else {
            @Suppress("UnspecifiedRegisterReceiverFlag")
            context.registerReceiver(receiver, filter)
        }
    }

    private fun install(apk: File) {
        val uri = FileProvider.getUriForFile(context, "${context.packageName}.fileprovider", apk)
        val intent = Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(uri, "application/vnd.android.package-archive")
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_GRANT_READ_URI_PERMISSION
        }
        context.startActivity(intent)
    }
}
