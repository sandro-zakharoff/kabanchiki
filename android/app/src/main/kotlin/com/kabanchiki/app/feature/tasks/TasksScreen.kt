package com.kabanchiki.app.feature.tasks

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
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.foundation.background
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.hilt.navigation.compose.hiltViewModel
import com.kabanchiki.app.R
import com.kabanchiki.app.core.designsystem.KCard
import com.kabanchiki.app.core.designsystem.KChip
import com.kabanchiki.app.core.designsystem.KabColors
import com.kabanchiki.app.core.model.DeadlineState
import com.kabanchiki.app.core.model.TaskDto
import com.kabanchiki.app.core.model.TaskStatus
import com.kabanchiki.app.core.model.formatDate
import com.kabanchiki.app.core.model.formatDeadline
import com.kabanchiki.app.core.designsystem.KAcorns
import com.kabanchiki.app.core.model.parseInstant

@Composable
fun statusChip(status: TaskStatus): Pair<String, androidx.compose.ui.graphics.Color> = when (status) {
    TaskStatus.New -> stringResource(R.string.task_status_new) to KabColors.info
    TaskStatus.InProgress -> stringResource(R.string.task_status_in_progress) to KabColors.accent
    TaskStatus.Paused -> stringResource(R.string.task_status_paused) to KabColors.warning
    TaskStatus.Submitted -> stringResource(R.string.task_status_submitted) to KabColors.info
    TaskStatus.Done -> stringResource(R.string.task_status_done) to KabColors.success
    TaskStatus.Declined -> stringResource(R.string.task_status_declined) to KabColors.danger
}

/** A brand-new task that carries a rework note is a "redo". */
@Composable
fun taskStatusChip(task: TaskDto): Pair<String, androidx.compose.ui.graphics.Color> {
    val status = TaskStatus.from(task.status)
    return if (status == TaskStatus.New && !task.declineReason.isNullOrBlank()) {
        stringResource(R.string.task_status_rework) to KabColors.warning
    } else {
        statusChip(status)
    }
}

@OptIn(androidx.compose.material3.ExperimentalMaterial3Api::class)
@Composable
fun TasksScreen(
    onOpenTask: (String) -> Unit,
    viewModel: TasksViewModel = hiltViewModel(),
) {
    val context = LocalContext.current
    val tasks by viewModel.tasks.collectAsState()
    val refreshing by viewModel.refreshing.collectAsState()

    LaunchedEffect(Unit) { viewModel.refresh() }

    Column(Modifier.fillMaxSize()) {
        com.kabanchiki.app.feature.update.UpdateBanner(
            modifier = Modifier.padding(start = 16.dp, end = 16.dp, top = 16.dp),
        )
        Text(
            stringResource(R.string.tasks_title),
            style = MaterialTheme.typography.headlineMedium,
            modifier = Modifier.padding(start = 20.dp, top = 20.dp, bottom = 8.dp),
        )

        androidx.compose.material3.pulltorefresh.PullToRefreshBox(
            isRefreshing = refreshing,
            onRefresh = viewModel::refresh,
            modifier = Modifier.fillMaxSize(),
        ) {
            if (tasks.isEmpty()) {
                Box(
                    Modifier
                        .fillMaxSize()
                        .verticalScroll(rememberScrollState()),
                    contentAlignment = Alignment.Center,
                ) {
                    Text(
                        stringResource(R.string.tasks_empty),
                        style = MaterialTheme.typography.bodyMedium,
                        color = KabColors.textSecondary,
                        textAlign = TextAlign.Center,
                        modifier = Modifier.padding(32.dp),
                    )
                }
            } else {
                val grouped = tasks.groupBy { formatDate(parseInstant(it.createdAt)) }

                LazyColumn(
                    modifier = Modifier.fillMaxSize(),
                    contentPadding = androidx.compose.foundation.layout.PaddingValues(
                        start = 16.dp, end = 16.dp, top = 4.dp, bottom = 24.dp,
                    ),
                    verticalArrangement = Arrangement.spacedBy(10.dp),
                ) {
                    grouped.forEach { (date, dayTasks) ->
                        item(key = "header-$date") {
                            Text(
                                date,
                                style = MaterialTheme.typography.labelSmall,
                                color = KabColors.textSecondary,
                                modifier = Modifier.padding(start = 6.dp, top = 10.dp),
                            )
                        }
                        items(dayTasks, key = { it.id }) { task ->
                            TaskCard(
                                task = task,
                                onClick = { onOpenTask(task.id) },
                                onQuickComplete = {
                                    val needsProof = task.proofText == "required" || task.proofPhoto == "required"
                                    if (needsProof) {
                                        onOpenTask(task.id)
                                    } else {
                                        viewModel.clearProofPhotos()
                                        viewModel.complete(context, task.id, null) {}
                                    }
                                },
                            )
                        }
                    }
                }
            }
        }
    }
}

@Composable
private fun TaskCard(task: TaskDto, onClick: () -> Unit, onQuickComplete: () -> Unit) {
    val status = TaskStatus.from(task.status)
    val (label, color) = taskStatusChip(task)
    val diffColor = KabColors.difficulty[(task.difficulty - 1).coerceIn(0, 4)]
    // A simple (no-timer) task that is still new can be finished right here.
    val quickDone = task.completionMode == "simple" && status == TaskStatus.New

    KCard(modifier = Modifier.fillMaxWidth(), onClick = onClick) {
        Column(Modifier.padding(16.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Box(
                    Modifier
                        .width(4.dp)
                        .height(52.dp)
                        .clip(RoundedCornerShape(2.dp))
                        .background(diffColor),
                )
                Spacer(Modifier.width(14.dp))
                Column(Modifier.weight(1f)) {
                    Text(
                        task.title,
                        style = MaterialTheme.typography.titleMedium,
                        maxLines = 2,
                    )
                    if (task.description.isNotBlank()) {
                        Spacer(Modifier.height(2.dp))
                        Text(
                            task.description,
                            style = MaterialTheme.typography.bodySmall,
                            maxLines = 1,
                        )
                    }
                    Spacer(Modifier.height(6.dp))
                    Row(
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(6.dp),
                    ) {
                        com.kabanchiki.app.core.designsystem.KDifficultyBadge(level = task.difficulty)
                        DeadlineBadge(task)
                    }
                }
                Spacer(Modifier.width(10.dp))
                Column(horizontalAlignment = Alignment.End, verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    KAcorns(
                        amount = task.rewardAmount,
                        suffix = if (task.rewardType == "hourly") stringResource(R.string.job_rate_suffix) else null,
                        fontSize = 15.sp,
                        fontWeight = FontWeight.Bold,
                        color = KabColors.success,
                    )
                    KChip(text = label, color = color)
                }
            }
            if (quickDone) {
                Spacer(Modifier.height(12.dp))
                com.kabanchiki.app.core.designsystem.KButton(
                    text = stringResource(R.string.task_btn_done),
                    onClick = onQuickComplete,
                    compact = true,
                    modifier = Modifier.fillMaxWidth(),
                )
            }
        }
    }
}

/** Compact deadline chip; hidden for finished tasks and tasks without one. */
@Composable
fun DeadlineBadge(task: TaskDto) {
    val status = TaskStatus.from(task.status)
    if (status == TaskStatus.Done || status == TaskStatus.Declined) return
    val (text, state) = formatDeadline(parseInstant(task.deadlineAt))
    if (state == DeadlineState.NONE) return
    val color = when (state) {
        DeadlineState.OVERDUE -> KabColors.danger
        DeadlineState.SOON -> KabColors.warning
        else -> KabColors.textSecondary
    }
    KChip(text = "⏰ $text", color = color, filled = state == DeadlineState.OVERDUE)
}
