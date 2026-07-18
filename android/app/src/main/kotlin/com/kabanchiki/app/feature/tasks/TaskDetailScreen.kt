package com.kabanchiki.app.feature.tasks

import android.net.Uri
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.pager.HorizontalPager
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Close
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import coil.compose.AsyncImage
import com.kabanchiki.app.R
import com.kabanchiki.app.core.designsystem.KButton
import com.kabanchiki.app.core.designsystem.KButtonVariant
import com.kabanchiki.app.core.designsystem.KCard
import com.kabanchiki.app.core.designsystem.KChip
import com.kabanchiki.app.core.designsystem.KTextField
import com.kabanchiki.app.core.designsystem.KabColors
import com.kabanchiki.app.core.model.AttachmentDto
import com.kabanchiki.app.core.model.ProofRequirement
import com.kabanchiki.app.core.model.TaskStatus
import com.kabanchiki.app.core.model.formatDateTime
import com.kabanchiki.app.core.model.formatDuration
import com.kabanchiki.app.core.model.formatMoney
import com.kabanchiki.app.core.model.parseInstant
import kotlinx.coroutines.delay
import kotlinx.datetime.Instant

@Composable
fun TaskDetailScreen(
    taskId: String,
    onBack: () -> Unit,
    viewModel: TasksViewModel = hiltViewModel(),
) {
    val context = LocalContext.current
    val tasks by viewModel.tasks.collectAsState()
    val attachments by viewModel.attachments.collectAsState()
    val openIntervals by viewModel.openIntervals.collectAsState()
    val busyTaskId by viewModel.busyTaskId.collectAsState()
    val attachmentUrls by viewModel.attachmentUrls.collectAsState()

    val task = tasks.firstOrNull { it.id == taskId }
    var showDecline by remember { mutableStateOf(false) }
    var showProof by remember { mutableStateOf(false) }
    var viewer by remember { mutableStateOf<Pair<List<String>, Int>?>(null) }

    LaunchedEffect(task?.id, attachments) {
        task?.let { viewModel.loadAttachmentUrls(it.id) }
    }

    if (task == null) {
        Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
            Text(stringResource(R.string.common_loading), color = KabColors.textSecondary)
        }
        return
    }

    val status = TaskStatus.from(task.status)
    val busy = busyTaskId == task.id
    val taskPhotos = attachments.filter { it.taskId == task.id && it.role == "task" }
    val proofPhotos = attachments.filter { it.taskId == task.id && it.role == "proof" }

    fun openViewer(list: List<AttachmentDto>, index: Int) {
        val urls = list.mapNotNull { attachmentUrls["f:${it.id}"] }
        if (urls.isNotEmpty()) viewer = urls to index.coerceIn(0, urls.size - 1)
    }

    // Live timer for a task in progress.
    var liveSeconds by remember(task.id, task.totalSeconds, task.status, openIntervals) {
        mutableStateOf(task.totalSeconds.toLong())
    }
    LaunchedEffect(task.id, task.status, openIntervals) {
        if (status == TaskStatus.InProgress) {
            val openInterval = openIntervals[task.id]
            val startedAt: Instant? = parseInstant(openInterval?.startedAt)
            while (true) {
                val extra = if (startedAt != null) {
                    (viewModel.timeSync.nowServer() - startedAt).inWholeSeconds.coerceAtLeast(0)
                } else 0
                liveSeconds = task.totalSeconds.toLong() + extra
                delay(1000)
            }
        }
    }

    Column(
        Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            IconButton(onClick = onBack) {
                Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = null, tint = KabColors.textPrimary)
            }
            Text(
                task.title,
                style = MaterialTheme.typography.headlineMedium,
                modifier = Modifier.weight(1f),
            )
        }

        KCard(Modifier.fillMaxWidth()) {
            Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    val (label, color) = taskStatusChip(task)
                    KChip(text = label, color = color, filled = true)
                    KChip(text = rewardText(task), color = KabColors.accentDark)
                    Spacer(Modifier.weight(1f))
                    com.kabanchiki.app.core.designsystem.KDifficultyBadge(level = task.difficulty)
                }

                // Rework note (task came back to redo) or submitted-info.
                if (status == TaskStatus.New && !task.declineReason.isNullOrBlank()) {
                    Text(
                        stringResource(R.string.task_rework_note, task.declineReason),
                        style = MaterialTheme.typography.bodyMedium,
                        color = KabColors.warning,
                    )
                } else if (status == TaskStatus.Submitted) {
                    Text(
                        stringResource(R.string.task_submitted_hint),
                        style = MaterialTheme.typography.bodyMedium,
                        color = KabColors.info,
                    )
                } else if (status == TaskStatus.Declined && !task.declineReason.isNullOrBlank()) {
                    Text(
                        stringResource(R.string.task_declined_note, task.declineReason),
                        style = MaterialTheme.typography.bodyMedium,
                        color = KabColors.danger,
                    )
                }

                if (task.description.isNotBlank()) {
                    Text(task.description, style = MaterialTheme.typography.bodyLarge)
                }

                if (taskPhotos.isNotEmpty()) {
                    PhotoStrip(
                        photos = taskPhotos,
                        urls = attachmentUrls,
                        onClick = { index -> openViewer(taskPhotos, index) },
                    )
                }

                Text(
                    stringResource(R.string.task_created_at, formatDateTime(parseInstant(task.createdAt))),
                    style = MaterialTheme.typography.bodySmall,
                )
                if (task.createdByName.isNotBlank()) {
                    Text(
                        stringResource(R.string.task_created_by, task.createdByName),
                        style = MaterialTheme.typography.bodySmall,
                    )
                }
                run {
                    val (dlText, dlState) = com.kabanchiki.app.core.model.formatDeadline(
                        parseInstant(task.deadlineAt),
                    )
                    val active = status !in listOf(TaskStatus.Done, TaskStatus.Declined)
                    if (dlState != com.kabanchiki.app.core.model.DeadlineState.NONE && active) {
                        val tone = when (dlState) {
                            com.kabanchiki.app.core.model.DeadlineState.OVERDUE -> KabColors.danger
                            com.kabanchiki.app.core.model.DeadlineState.SOON -> KabColors.warning
                            else -> KabColors.info
                        }
                        Row(
                            verticalAlignment = Alignment.CenterVertically,
                            modifier = Modifier
                                .fillMaxWidth()
                                .clip(RoundedCornerShape(10.dp))
                                .background(tone.copy(alpha = 0.12f))
                                .padding(horizontal = 12.dp, vertical = 9.dp),
                        ) {
                            Text("⏰", style = MaterialTheme.typography.bodyMedium)
                            Spacer(Modifier.size(8.dp))
                            Text(
                                stringResource(R.string.task_deadline, dlText),
                                style = MaterialTheme.typography.bodyMedium,
                                color = tone,
                            )
                        }
                    }
                }
            }
        }

        if (task.requirements.isNotBlank()) {
            KCard(Modifier.fillMaxWidth()) {
                Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    Text(
                        stringResource(R.string.task_requirements),
                        style = MaterialTheme.typography.labelMedium,
                        color = KabColors.warning,
                    )
                    Text(task.requirements, style = MaterialTheme.typography.bodyMedium)
                }
            }
        }

        // Timer + earnings tiles. Simple tasks have no timer, so show earnings only.
        val showTimer = task.completionMode != "simple" &&
            (status == TaskStatus.InProgress || status == TaskStatus.Paused || status == TaskStatus.Done)
        val showEarned = status == TaskStatus.Done || task.rewardType == "hourly"
        if (showTimer || (task.completionMode == "simple" && status == TaskStatus.Done)) {
            Row(
                Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                if (showTimer) {
                    com.kabanchiki.app.core.designsystem.KStatTile(
                        label = stringResource(R.string.task_time_spent),
                        value = formatDuration(if (status == TaskStatus.InProgress) liveSeconds else task.totalSeconds.toLong()),
                        valueColor = if (status == TaskStatus.InProgress) KabColors.accent else KabColors.textPrimary,
                        modifier = Modifier.weight(1f),
                    )
                }
                if (showEarned) {
                    val earned = task.earnedAmount
                        ?: (liveSeconds / 3600.0 * task.rewardAmount)
                    com.kabanchiki.app.core.designsystem.KStatTile(
                        label = stringResource(R.string.task_earned),
                        value = formatMoney(earned),
                        valueColor = KabColors.success,
                        modifier = Modifier.weight(1f),
                    )
                }
            }
        }

        // Proof already submitted (done / under review).
        if ((status == TaskStatus.Done || status == TaskStatus.Submitted) &&
            (!task.proofTextContent.isNullOrBlank() || proofPhotos.isNotEmpty())
        ) {
            KCard(Modifier.fillMaxWidth()) {
                Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text(
                        stringResource(R.string.task_completed_at, formatDateTime(parseInstant(task.completedAt))),
                        style = MaterialTheme.typography.labelMedium,
                        color = KabColors.success,
                    )
                    task.proofTextContent?.takeIf { it.isNotBlank() }?.let {
                        Text(it, style = MaterialTheme.typography.bodyMedium)
                    }
                    if (proofPhotos.isNotEmpty()) {
                        PhotoStrip(
                            photos = proofPhotos,
                            urls = attachmentUrls,
                            onClick = { index -> openViewer(proofPhotos, index) },
                        )
                    }
                }
            }
        }

        if (busy) {
            LinearProgressIndicator(Modifier.fillMaxWidth(), color = KabColors.accent)
        }

        // Action buttons per status.
        val isSimple = task.completionMode == "simple"
        when (status) {
            TaskStatus.New -> Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                KButton(
                    text = stringResource(R.string.task_btn_decline),
                    onClick = { showDecline = true },
                    variant = KButtonVariant.Secondary,
                    enabled = !busy,
                    modifier = Modifier.weight(1f),
                )
                if (isSimple) {
                    // No timer: finish directly (proof dialog if required).
                    KButton(
                        text = stringResource(R.string.task_btn_done),
                        onClick = {
                            val needsProof = task.proofText != "none" || task.proofPhoto != "none"
                            if (needsProof) {
                                viewModel.clearProofPhotos(); showProof = true
                            } else viewModel.complete(context, task.id, null) { onBack() }
                        },
                        enabled = !busy,
                        modifier = Modifier.weight(1f),
                    )
                } else {
                    KButton(
                        text = stringResource(R.string.task_btn_start),
                        onClick = { viewModel.start(task.id) },
                        enabled = !busy,
                        modifier = Modifier.weight(1f),
                    )
                }
            }
            TaskStatus.InProgress -> Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                KButton(
                    text = stringResource(R.string.task_btn_pause),
                    onClick = { viewModel.pause(task.id) },
                    variant = KButtonVariant.Secondary,
                    enabled = !busy,
                    modifier = Modifier.weight(1f),
                )
                KButton(
                    text = stringResource(R.string.task_btn_done),
                    onClick = { viewModel.clearProofPhotos(); showProof = true },
                    enabled = !busy,
                    modifier = Modifier.weight(1f),
                )
            }
            TaskStatus.Paused -> Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                KButton(
                    text = stringResource(R.string.task_btn_start),
                    onClick = { viewModel.start(task.id) },
                    variant = KButtonVariant.Secondary,
                    enabled = !busy,
                    modifier = Modifier.weight(1f),
                )
                KButton(
                    text = stringResource(R.string.task_btn_done),
                    onClick = { viewModel.clearProofPhotos(); showProof = true },
                    enabled = !busy,
                    modifier = Modifier.weight(1f),
                )
            }
            else -> Unit
        }

        Spacer(Modifier.height(12.dp))
    }

    if (showDecline) {
        DeclineDialog(
            onDismiss = { showDecline = false },
            onConfirm = { reason ->
                showDecline = false
                viewModel.decline(task.id, reason)
                onBack()
            },
        )
    }

    if (showProof) {
        ProofDialog(
            textRequirement = ProofRequirement.from(task.proofText),
            photoRequirement = ProofRequirement.from(task.proofPhoto),
            busy = busy,
            viewModel = viewModel,
            onDismiss = { showProof = false },
            onSubmit = { text ->
                viewModel.complete(context, task.id, text) {
                    showProof = false
                }
            },
        )
    }

    viewer?.let { (urls, start) ->
        PhotoViewer(urls = urls, startIndex = start, onClose = { viewer = null })
    }
}

/** Horizontal gallery of square thumbnails. */
@Composable
private fun PhotoStrip(
    photos: List<AttachmentDto>,
    urls: Map<String, String>,
    onClick: (Int) -> Unit,
) {
    LazyRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
        itemsIndexed(photos, key = { _, a -> a.id }) { index, att ->
            AsyncImage(
                model = urls["t:${att.id}"],
                contentDescription = null,
                contentScale = ContentScale.Crop,
                modifier = Modifier
                    .size(104.dp)
                    .clip(RoundedCornerShape(12.dp))
                    .background(KabColors.surfaceAlt)
                    .clickable { onClick(index) },
            )
        }
    }
}

/** Fullscreen swipeable photo viewer with a counter. */
@Composable
fun PhotoViewer(urls: List<String>, startIndex: Int, onClose: () -> Unit) {
    val pagerState = rememberPagerState(initialPage = startIndex) { urls.size }
    Dialog(
        onDismissRequest = onClose,
        properties = DialogProperties(usePlatformDefaultWidth = false),
    ) {
        Box(
            Modifier
                .fillMaxSize()
                .background(Color(0xF2100D12)),
        ) {
            HorizontalPager(state = pagerState, modifier = Modifier.fillMaxSize()) { page ->
                Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                    AsyncImage(
                        model = urls[page],
                        contentDescription = null,
                        contentScale = ContentScale.Fit,
                        modifier = Modifier
                            .fillMaxSize()
                            .padding(horizontal = 8.dp, vertical = 48.dp)
                            .clickable(onClick = onClose),
                    )
                }
            }
            if (urls.size > 1) {
                Text(
                    "${pagerState.currentPage + 1} / ${urls.size}",
                    color = Color.White,
                    style = MaterialTheme.typography.labelLarge,
                    modifier = Modifier
                        .align(Alignment.TopCenter)
                        .padding(top = 22.dp)
                        .clip(RoundedCornerShape(50))
                        .background(Color(0x33000000))
                        .padding(horizontal = 14.dp, vertical = 5.dp),
                )
            }
            IconButton(
                onClick = onClose,
                modifier = Modifier
                    .align(Alignment.TopEnd)
                    .padding(12.dp)
                    .clip(CircleShape)
                    .background(Color(0x22FFFFFF)),
            ) {
                Icon(Icons.Filled.Close, contentDescription = null, tint = Color.White)
            }
        }
    }
}

@Composable
private fun DeclineDialog(onDismiss: () -> Unit, onConfirm: (String?) -> Unit) {
    var reason by remember { mutableStateOf("") }
    AlertDialog(
        onDismissRequest = onDismiss,
        containerColor = KabColors.surface,
        title = { Text(stringResource(R.string.task_decline_title), style = MaterialTheme.typography.titleLarge) },
        text = {
            KTextField(
                value = reason,
                onValueChange = { reason = it },
                placeholder = stringResource(R.string.task_decline_hint),
                singleLine = false,
                minLines = 2,
            )
        },
        confirmButton = {
            KButton(
                text = stringResource(R.string.task_decline_confirm),
                onClick = { onConfirm(reason.ifBlank { null }) },
                variant = KButtonVariant.Danger,
            )
        },
        dismissButton = {
            KButton(
                text = stringResource(R.string.common_cancel),
                onClick = onDismiss,
                variant = KButtonVariant.Ghost,
            )
        },
    )
}

@Composable
private fun ProofDialog(
    textRequirement: ProofRequirement,
    photoRequirement: ProofRequirement,
    busy: Boolean,
    viewModel: TasksViewModel,
    onDismiss: () -> Unit,
    onSubmit: (String?) -> Unit,
) {
    var text by remember { mutableStateOf("") }
    val uploads by viewModel.proofUploads.collectAsState()

    val picker = rememberLauncherForActivityResult(
        ActivityResultContracts.PickMultipleVisualMedia(10),
    ) { uris ->
        if (uris.isNotEmpty()) viewModel.addProofPhotos(uris)
    }

    val textOk = textRequirement != ProofRequirement.Required || text.isNotBlank()
    val photoOk = photoRequirement != ProofRequirement.Required || uploads.isNotEmpty()

    AlertDialog(
        onDismissRequest = { if (!busy) onDismiss() },
        containerColor = KabColors.surface,
        title = { Text(stringResource(R.string.task_proof_title), style = MaterialTheme.typography.titleLarge) },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                if (textRequirement != ProofRequirement.None) {
                    KTextField(
                        value = text,
                        onValueChange = { text = it },
                        placeholder = stringResource(
                            if (textRequirement == ProofRequirement.Required) R.string.task_proof_text_required
                            else R.string.task_proof_text_optional,
                        ),
                        singleLine = false,
                        minLines = 3,
                    )
                }
                if (photoRequirement != ProofRequirement.None) {
                    Text(
                        stringResource(
                            if (photoRequirement == ProofRequirement.Required) R.string.task_proof_photo_required
                            else R.string.task_proof_photo_optional,
                        ),
                        style = MaterialTheme.typography.bodySmall,
                    )
                    LazyRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        items(uploads, key = { it.uri }) { photo ->
                            Box(Modifier.size(84.dp)) {
                                AsyncImage(
                                    model = photo.uri,
                                    contentDescription = null,
                                    contentScale = ContentScale.Crop,
                                    modifier = Modifier
                                        .fillMaxSize()
                                        .clip(RoundedCornerShape(12.dp))
                                        .background(KabColors.surfaceAlt),
                                )
                                photo.progress?.let { pct ->
                                    Box(
                                        Modifier
                                            .fillMaxSize()
                                            .clip(RoundedCornerShape(12.dp))
                                            .background(Color(0x66141014)),
                                        contentAlignment = Alignment.Center,
                                    ) {
                                        CircularProgressIndicator(
                                            progress = { pct / 100f },
                                            color = Color.White,
                                            modifier = Modifier.size(34.dp),
                                        )
                                    }
                                }
                                if (!busy) {
                                    Box(
                                        Modifier
                                            .align(Alignment.TopEnd)
                                            .padding(4.dp)
                                            .size(22.dp)
                                            .clip(CircleShape)
                                            .background(Color(0x99141014))
                                            .clickable { viewModel.removeProofPhoto(photo.uri) },
                                        contentAlignment = Alignment.Center,
                                    ) {
                                        Icon(
                                            Icons.Filled.Close, contentDescription = null,
                                            tint = Color.White, modifier = Modifier.size(12.dp),
                                        )
                                    }
                                }
                            }
                        }
                        if (uploads.size < 10 && !busy) {
                            item {
                                Box(
                                    Modifier
                                        .size(84.dp)
                                        .clip(RoundedCornerShape(12.dp))
                                        .background(KabColors.surfaceAlt)
                                        .clickable {
                                            picker.launch(
                                                PickVisualMediaRequest(
                                                    ActivityResultContracts.PickVisualMedia.ImageOnly,
                                                ),
                                            )
                                        },
                                    contentAlignment = Alignment.Center,
                                ) {
                                    Icon(
                                        Icons.Filled.Add, contentDescription = null,
                                        tint = KabColors.textSecondary,
                                    )
                                }
                            }
                        }
                    }
                    Text(
                        stringResource(R.string.task_proof_photo_hint),
                        style = MaterialTheme.typography.labelSmall,
                        color = KabColors.textSecondary,
                    )
                }
                if (busy) {
                    LinearProgressIndicator(Modifier.fillMaxWidth(), color = KabColors.accent)
                }
            }
        },
        confirmButton = {
            KButton(
                text = stringResource(if (busy) R.string.task_proof_uploading else R.string.task_proof_submit),
                onClick = { onSubmit(text.ifBlank { null }) },
                enabled = !busy && textOk && photoOk,
            )
        },
        dismissButton = {
            KButton(
                text = stringResource(R.string.common_cancel),
                onClick = onDismiss,
                variant = KButtonVariant.Ghost,
                enabled = !busy,
            )
        },
    )
}
