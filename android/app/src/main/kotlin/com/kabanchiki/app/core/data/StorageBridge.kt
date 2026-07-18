package com.kabanchiki.app.core.data

import android.util.Base64
import android.util.Log
import com.kabanchiki.app.core.images.ImageOptimizer
import com.kabanchiki.app.core.model.AttachmentDto
import com.kabanchiki.app.core.model.ProfileDto
import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.functions.functions
import io.github.jan.supabase.postgrest.from
import io.github.jan.supabase.storage.storage
import io.ktor.client.call.body
import io.ktor.client.request.setBody
import io.ktor.http.ContentType
import io.ktor.http.contentType
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.put
import java.util.UUID
import javax.inject.Inject
import javax.inject.Singleton
import kotlin.time.Duration.Companion.hours

const val AVATARS_BUCKET = "avatars"

/**
 * Storage facade, mirroring the desktop: every attachment/avatar records where
 * its file lives ('supabase' | 'drive'), so reads work for both backends.
 * Writes follow app_config.storage_backend; when the Drive Edge Function is
 * unavailable the upload falls back to Supabase Storage.
 */
@Singleton
class StorageBridge @Inject constructor(
    private val client: SupabaseClient,
) {
    @Volatile
    var backend: String = "supabase"
        private set

    @Serializable
    private data class ConfigRow(val storage_backend: String = "supabase")

    suspend fun refreshBackend() {
        backend = runCatching {
            client.from("app_config").select().decodeSingleOrNull<ConfigRow>()
                ?.storage_backend ?: "supabase"
        }.getOrDefault("supabase")
    }

    data class StoredFile(val storage: String, val path: String, val thumbPath: String? = null)

    private suspend fun driveUpload(kind: String, encoded: ImageOptimizer.Encoded): String {
        val response = client.functions.invoke("drive") {
            contentType(ContentType.Application.Json)
            setBody(
                buildJsonObject {
                    put("action", "upload")
                    put("kind", kind)
                    put("filename", "${UUID.randomUUID()}.${encoded.ext}")
                    put("mime", encoded.mime)
                    put("data_base64", Base64.encodeToString(encoded.bytes, Base64.NO_WRAP))
                },
            )
        }
        val body = response.body<JsonObject>()
        return body["id"]?.jsonPrimitive?.content ?: error(
            body["error"]?.jsonPrimitive?.content ?: "drive upload failed",
        )
    }

    /** Proof photo (full + thumb). Folder = uid: the bucket policy is folder-scoped. */
    suspend fun uploadProof(uid: String, photo: ImageOptimizer.Optimized): StoredFile {
        if (backend == "drive") {
            runCatching {
                val id = driveUpload("proof", photo.full)
                val thumbId = driveUpload("proof", photo.thumb)
                return StoredFile("drive", id, thumbId)
            }.onFailure { Log.w("StorageBridge", "drive upload failed, fallback to supabase", it) }
        }
        val base = "$uid/${UUID.randomUUID()}"
        val path = "$base.${photo.full.ext}"
        val thumb = "${base}_t.${photo.thumb.ext}"
        client.storage.from(PROOF_BUCKET).upload(path, photo.full.bytes)
        client.storage.from(PROOF_BUCKET).upload(thumb, photo.thumb.bytes)
        return StoredFile("supabase", path, thumb)
    }

    /** The child's own avatar; returns (storage, path). */
    suspend fun uploadAvatar(uid: String, encoded: ImageOptimizer.Encoded): StoredFile {
        if (backend == "drive") {
            runCatching {
                return StoredFile("drive", driveUpload("avatar", encoded))
            }.onFailure { Log.w("StorageBridge", "drive avatar failed, fallback", it) }
        }
        val path = "$uid/${UUID.randomUUID()}.${encoded.ext}"
        client.storage.from(AVATARS_BUCKET).upload(path, encoded.bytes)
        return StoredFile("supabase", path)
    }

    // ---------------------------------------------------------------- display URLs

    private fun cdnUrl(fileId: String, width: Int) =
        "https://drive.google.com/thumbnail?id=$fileId&sz=w$width"

    private val signedCache = HashMap<String, String>()

    suspend fun attachmentUrl(att: AttachmentDto, thumb: Boolean = false): String? {
        if (att.storage == "drive") {
            val id = if (thumb && att.thumbPath != null) att.thumbPath else att.path
            return cdnUrl(id, if (thumb) 480 else 1920)
        }
        val bucket = if (att.role == "task") TASK_PHOTOS_BUCKET else PROOF_BUCKET
        val path = if (thumb && att.thumbPath != null) att.thumbPath else att.path
        val key = "$bucket/$path"
        signedCache[key]?.let { return it }
        return runCatching {
            client.storage.from(bucket).createSignedUrl(path, 1.hours)
        }.getOrNull()?.also { signedCache[key] = it }
    }

    fun avatarUrl(profile: ProfileDto?, width: Int = 320): String? {
        val path = profile?.avatarPath ?: return null
        return if (profile.avatarStorage == "drive") cdnUrl(path, width)
        else client.storage.from(AVATARS_BUCKET).publicUrl(path)
    }
}
