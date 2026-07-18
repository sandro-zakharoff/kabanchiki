package com.kabanchiki.app.core.data

import com.kabanchiki.app.core.model.ProfileDto
import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.auth.auth
import io.github.jan.supabase.auth.providers.builtin.Email
import io.github.jan.supabase.auth.status.SessionStatus
import io.github.jan.supabase.postgrest.from
import io.github.jan.supabase.postgrest.postgrest
import kotlinx.coroutines.flow.StateFlow
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import javax.inject.Inject
import javax.inject.Singleton

const val EMAIL_DOMAIN = "kabanchiki.local"

@Singleton
class AuthRepository @Inject constructor(
    private val client: SupabaseClient,
) {
    val sessionStatus: StateFlow<SessionStatus> get() = client.auth.sessionStatus

    val currentUserId: String?
        get() = client.auth.currentUserOrNull()?.id

    suspend fun login(username: String, password: String) {
        val email = "${username.trim().lowercase()}@$EMAIL_DOMAIN"
        client.auth.signInWith(Email) {
            this.email = email
            this.password = password
        }
    }

    suspend fun logout() {
        client.auth.signOut()
    }

    suspend fun loadProfile(): ProfileDto? {
        val uid = currentUserId ?: return null
        return client.from("profiles").select {
            filter { eq("id", uid) }
        }.decodeSingleOrNull<ProfileDto>()
    }

    /** Point the child's own profile at a freshly uploaded avatar (or clear it). */
    suspend fun setOwnAvatar(storage: String?, path: String?) {
        client.postgrest.rpc(
            "profile_set_avatar",
            buildJsonObject {
                if (storage == null) put("p_storage", JsonNull) else put("p_storage", storage)
                if (path == null) put("p_path", JsonNull) else put("p_path", path)
            },
        )
    }
}
