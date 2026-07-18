package com.kabanchiki.app.feature.tasks

import android.content.Context
import android.net.Uri
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.kabanchiki.app.core.data.AuthRepository
import com.kabanchiki.app.core.data.StorageBridge
import com.kabanchiki.app.core.data.TasksRepository
import com.kabanchiki.app.core.data.TimeSync
import com.kabanchiki.app.core.images.ImageOptimizer
import com.kabanchiki.app.core.model.AttachmentDto
import com.kabanchiki.app.core.model.TaskDto
import com.kabanchiki.app.core.model.TaskIntervalDto
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import javax.inject.Inject

/** One local proof photo travelling to the server. */
data class ProofUpload(
    val uri: Uri,
    val progress: Int? = null, // null = queued, 0..99 uploading, 100 done
    val error: Boolean = false,
)

@HiltViewModel
class TasksViewModel @Inject constructor(
    private val repository: TasksRepository,
    private val auth: AuthRepository,
    val storageBridge: StorageBridge,
    val timeSync: TimeSync,
) : ViewModel() {

    val tasks: StateFlow<List<TaskDto>> = repository.tasks
    val attachments: StateFlow<List<AttachmentDto>> = repository.attachments
    val openIntervals: StateFlow<Map<String, TaskIntervalDto>> = repository.openIntervals

    private val _busyTaskId = MutableStateFlow<String?>(null)
    val busyTaskId: StateFlow<String?> = _busyTaskId.asStateFlow()

    private val _refreshing = MutableStateFlow(false)
    val refreshing: StateFlow<Boolean> = _refreshing.asStateFlow()

    private val _error = MutableStateFlow<String?>(null)
    val error: StateFlow<String?> = _error.asStateFlow()

    // Resolved display URLs for attachments: attId -> url (thumb / full).
    private val _attachmentUrls = MutableStateFlow<Map<String, String>>(emptyMap())
    val attachmentUrls: StateFlow<Map<String, String>> = _attachmentUrls.asStateFlow()

    // Per-photo upload state of the proof dialog.
    private val _proofUploads = MutableStateFlow<List<ProofUpload>>(emptyList())
    val proofUploads: StateFlow<List<ProofUpload>> = _proofUploads.asStateFlow()

    fun refresh() {
        viewModelScope.launch {
            _refreshing.value = true
            runCatching { repository.refresh() }
                .onFailure { _error.value = it.message }
            _refreshing.value = false
        }
    }

    fun taskAttachments(taskId: String, role: String): List<AttachmentDto> =
        attachments.value.filter { it.taskId == taskId && it.role == role }

    /** Resolve display URLs (thumb + full) for a task's galleries. */
    fun loadAttachmentUrls(taskId: String) {
        viewModelScope.launch {
            val updates = mutableMapOf<String, String>()
            for (att in attachments.value.filter { it.taskId == taskId }) {
                storageBridge.attachmentUrl(att, thumb = true)?.let { updates["t:${att.id}"] = it }
                storageBridge.attachmentUrl(att, thumb = false)?.let { updates["f:${att.id}"] = it }
            }
            if (updates.isNotEmpty()) _attachmentUrls.value = _attachmentUrls.value + updates
        }
    }

    fun start(taskId: String) = action(taskId) { repository.start(taskId) }
    fun pause(taskId: String) = action(taskId) { repository.pause(taskId) }
    fun decline(taskId: String, reason: String?) = action(taskId) { repository.decline(taskId, reason) }

    fun setProofPhotos(uris: List<Uri>) {
        _proofUploads.value = uris.map { ProofUpload(it) }
    }

    fun addProofPhotos(uris: List<Uri>) {
        val have = _proofUploads.value.map { it.uri }.toSet()
        _proofUploads.value = (_proofUploads.value + uris.filter { it !in have }.map { ProofUpload(it) })
            .take(10)
    }

    fun removeProofPhoto(uri: Uri) {
        _proofUploads.value = _proofUploads.value.filter { it.uri != uri }
    }

    fun clearProofPhotos() {
        _proofUploads.value = emptyList()
    }

    /**
     * Optimize + upload every picked photo (per-photo progress), register each
     * via task_attach_proof, then submit the task.
     */
    fun complete(context: Context, taskId: String, proofText: String?, onDone: () -> Unit) {
        viewModelScope.launch {
            _busyTaskId.value = taskId
            val uid = auth.currentUserId
            try {
                val photos = _proofUploads.value
                for ((index, photo) in photos.withIndex()) {
                    if (photo.error) continue
                    updateUpload(index) { it.copy(progress = 5) }
                    val optimized = withContext(Dispatchers.Default) {
                        ImageOptimizer.optimize(context, photo.uri)
                    }
                    updateUpload(index) { it.copy(progress = 30) }
                    val stored = storageBridge.uploadProof(uid ?: error("no auth"), optimized)
                    updateUpload(index) { it.copy(progress = 85) }
                    repository.attachProof(
                        taskId, stored, optimized.full.mime, optimized.full.bytes.size,
                    )
                    updateUpload(index) { it.copy(progress = 100) }
                }
                repository.complete(taskId, proofText)
                _proofUploads.value = emptyList()
                onDone()
            } catch (e: Exception) {
                _error.value = e.message
                _proofUploads.value = _proofUploads.value.map {
                    if (it.progress != null && it.progress < 100) it.copy(error = true, progress = null) else it
                }
            } finally {
                _busyTaskId.value = null
            }
        }
    }

    private fun updateUpload(index: Int, transform: (ProofUpload) -> ProofUpload) {
        _proofUploads.value = _proofUploads.value.mapIndexed { i, p ->
            if (i == index) transform(p) else p
        }
    }

    fun clearError() {
        _error.value = null
    }

    private fun action(taskId: String, block: suspend () -> Unit) {
        viewModelScope.launch {
            _busyTaskId.value = taskId
            runCatching { block() }.onFailure { _error.value = it.message }
            _busyTaskId.value = null
        }
    }
}
