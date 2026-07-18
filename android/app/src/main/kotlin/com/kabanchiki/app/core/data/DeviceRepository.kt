package com.kabanchiki.app.core.data

import android.content.Context
import android.util.Log
import com.google.firebase.FirebaseApp
import com.google.firebase.messaging.FirebaseMessaging
import com.kabanchiki.app.BuildConfig
import dagger.hilt.android.qualifiers.ApplicationContext
import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.postgrest.postgrest
import kotlinx.coroutines.tasks.await
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class DeviceRepository @Inject constructor(
    @ApplicationContext private val context: Context,
    private val client: SupabaseClient,
    private val auth: AuthRepository,
) {
    /** Upload the current FCM token; safe to call any time after login. */
    suspend fun registerCurrentToken() {
        if (auth.currentUserId == null) return
        if (FirebaseApp.getApps(context).isEmpty()) return
        val token = runCatching { FirebaseMessaging.getInstance().token.await() }.getOrNull() ?: return
        registerToken(token)
    }

    suspend fun registerToken(token: String) {
        if (auth.currentUserId == null) return
        runCatching {
            client.postgrest.rpc(
                "register_device",
                buildJsonObject {
                    put("p_fcm_token", token)
                    put("p_platform", "android")
                    put("p_app_version", BuildConfig.VERSION_NAME)
                    put("p_app_version_code", BuildConfig.VERSION_CODE)
                },
            )
        }.onFailure { Log.w("DeviceRepository", "register_device failed", it) }
    }
}
