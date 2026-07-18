package com.kabanchiki.app.core.data

import com.kabanchiki.app.core.model.AttachmentDto
import com.kabanchiki.app.core.model.TaskDto
import com.kabanchiki.app.core.model.TaskIntervalDto
import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.postgrest.from
import io.github.jan.supabase.postgrest.postgrest
import io.github.jan.supabase.postgrest.query.Order
import io.github.jan.supabase.storage.storage
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import javax.inject.Inject
import javax.inject.Singleton
import kotlin.time.Duration.Companion.hours

const val PROOF_BUCKET = "proof-photos"
const val TASK_PHOTOS_BUCKET = "task-photos"

@Singleton
class TasksRepository @Inject constructor(
    private val client: SupabaseClient,
    private val auth: AuthRepository,
    private val storageBridge: StorageBridge,
) {
    private val _tasks = MutableStateFlow<List<TaskDto>>(emptyList())
    val tasks: StateFlow<List<TaskDto>> = _tasks.asStateFlow()

    private val _attachments = MutableStateFlow<List<AttachmentDto>>(emptyList())
    /** Photo galleries of the child's tasks (roles 'task' and 'proof'). */
    val attachments: StateFlow<List<AttachmentDto>> = _attachments.asStateFlow()

    private val _openIntervals = MutableStateFlow<Map<String, TaskIntervalDto>>(emptyMap())
    /** Open work interval per task id — powers the live task timer. */
    val openIntervals: StateFlow<Map<String, TaskIntervalDto>> = _openIntervals.asStateFlow()

    suspend fun refresh() {
        val uid = auth.currentUserId ?: return
        val rows = client.from("tasks").select {
            filter { eq("child_id", uid) }
            order("created_at", Order.DESCENDING)
        }.decodeList<TaskDto>()
        _tasks.value = rows

        // RLS already scopes attachments to the child's own tasks.
        _attachments.value = runCatching {
            client.from("attachments").select {
                order("created_at", Order.ASCENDING)
            }.decodeList<AttachmentDto>()
        }.getOrDefault(emptyList())
        storageBridge.refreshBackend()

        val activeIds = rows.filter { it.status == "in_progress" }.map { it.id }
        _openIntervals.value = if (activeIds.isEmpty()) emptyMap() else {
            client.from("task_intervals").select {
                filter {
                    isIn("task_id", activeIds)
                    exact("ended_at", null)
                }
            }.decodeList<TaskIntervalDto>().associateBy { it.taskId }
        }
    }

    suspend fun start(taskId: String) {
        client.postgrest.rpc("task_start", buildJsonObject { put("p_task_id", taskId) })
        refresh()
    }

    suspend fun pause(taskId: String) {
        client.postgrest.rpc("task_pause", buildJsonObject { put("p_task_id", taskId) })
        refresh()
    }

    suspend fun decline(taskId: String, reason: String?) {
        client.postgrest.rpc(
            "task_decline",
            buildJsonObject {
                put("p_task_id", taskId)
                put("p_reason", reason?.ifBlank { null })
            },
        )
        refresh()
    }

    /** Register one uploaded proof photo on the server (guarded RPC). */
    suspend fun attachProof(taskId: String, stored: StorageBridge.StoredFile, mime: String, sizeBytes: Int) {
        client.postgrest.rpc(
            "task_attach_proof",
            buildJsonObject {
                put("p_task_id", taskId)
                put("p_storage", stored.storage)
                put("p_path", stored.path)
                put("p_thumb_path", stored.thumbPath)
                put("p_mime", mime)
                put("p_size_bytes", sizeBytes)
            },
        )
    }

    suspend fun removeProof(attachmentId: String) {
        client.postgrest.rpc(
            "task_remove_proof",
            buildJsonObject { put("p_attachment_id", attachmentId) },
        )
        refresh()
    }

    /** Photos are attached beforehand via attachProof; this only submits. */
    suspend fun complete(taskId: String, proofText: String?) {
        client.postgrest.rpc(
            "task_complete",
            buildJsonObject {
                put("p_task_id", taskId)
                put("p_proof_text", proofText?.ifBlank { null })
            },
        )
        refresh()
    }

    suspend fun signedUrl(bucket: String, path: String?): String? {
        if (path.isNullOrBlank()) return null
        return runCatching {
            client.storage.from(bucket).createSignedUrl(path, 1.hours)
        }.getOrNull()
    }

    fun clear() {
        _tasks.value = emptyList()
        _attachments.value = emptyList()
        _openIntervals.value = emptyMap()
    }
}
