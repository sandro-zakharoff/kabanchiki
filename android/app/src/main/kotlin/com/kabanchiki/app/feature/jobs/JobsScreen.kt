package com.kabanchiki.app.feature.jobs

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
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
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.kabanchiki.app.R
import com.kabanchiki.app.core.data.JobsRepository
import com.kabanchiki.app.core.data.TimeSync
import com.kabanchiki.app.core.designsystem.KAcorns
import com.kabanchiki.app.core.designsystem.KCard
import com.kabanchiki.app.core.designsystem.KChip
import com.kabanchiki.app.core.designsystem.KStatTile
import com.kabanchiki.app.core.designsystem.KabColors
import com.kabanchiki.app.core.model.JobStatsDto
import com.kabanchiki.app.core.model.formatDateTime
import com.kabanchiki.app.core.model.formatDuration
import com.kabanchiki.app.core.model.liveAcorns
import com.kabanchiki.app.core.model.parseInstant
import dagger.hilt.android.lifecycle.HiltViewModel
import javax.inject.Inject
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

@HiltViewModel
class JobsViewModel @Inject constructor(
    private val repository: JobsRepository,
    val timeSync: TimeSync,
) : ViewModel() {

    val stats: StateFlow<List<JobStatsDto>> = repository.stats

    private val _refreshing = MutableStateFlow(false)
    val refreshing: StateFlow<Boolean> = _refreshing.asStateFlow()

    fun refresh() {
        viewModelScope.launch {
            _refreshing.value = true
            runCatching { repository.refresh() }
            _refreshing.value = false
        }
    }
}

/** Live view of one job derived from the last server snapshot. */
private data class LiveJob(val totalSeconds: Long, val earned: Int)

private fun liveOf(stat: JobStatsDto, timeSync: TimeSync): LiveJob {
    val snapshot = parseInstant(stat.snapshotAt)
    val running = stat.runningSince != null
    val extra = if (running && snapshot != null) {
        (timeSync.nowServer() - snapshot).inWholeSeconds.coerceAtLeast(0)
    } else 0L
    // Tick the exact acorn-seconds accumulator, exactly as the server does, so
    // the number never drifts from what the next settlement credits.
    val earned = liveAcorns(stat.accruedAcornSeconds, extra, stat.hourlyRate)
    return LiveJob(stat.totalSeconds + extra, earned)
}

@OptIn(androidx.compose.material3.ExperimentalMaterial3Api::class)
@Composable
fun JobsScreen(viewModel: JobsViewModel = hiltViewModel()) {
    val stats by viewModel.stats.collectAsState()
    val refreshing by viewModel.refreshing.collectAsState()

    LaunchedEffect(Unit) { viewModel.refresh() }

    var tick by remember { mutableLongStateOf(0L) }
    LaunchedEffect(stats.any { it.runningSince != null }) {
        while (true) { delay(1000); tick++ }
    }

    Column(Modifier.fillMaxSize()) {
        Text(
            stringResource(R.string.job_title),
            style = MaterialTheme.typography.headlineMedium,
            modifier = Modifier.padding(start = 20.dp, top = 20.dp, bottom = 8.dp),
        )

        androidx.compose.material3.pulltorefresh.PullToRefreshBox(
            isRefreshing = refreshing,
            onRefresh = viewModel::refresh,
            modifier = Modifier.fillMaxSize(),
        ) {
            if (stats.isEmpty()) {
                Box(
                    Modifier.fillMaxSize().verticalScroll(rememberScrollState()),
                    contentAlignment = Alignment.Center,
                ) {
                    Text(
                        stringResource(R.string.job_empty),
                        style = MaterialTheme.typography.bodyMedium,
                        color = KabColors.textSecondary,
                        textAlign = TextAlign.Center,
                        modifier = Modifier.padding(32.dp),
                    )
                }
            } else {
                LazyColumn(
                    modifier = Modifier.fillMaxSize(),
                    contentPadding = androidx.compose.foundation.layout.PaddingValues(16.dp),
                    verticalArrangement = Arrangement.spacedBy(12.dp),
                ) {
                    items(stats, key = { it.jobId }) { stat ->
                        @Suppress("UNUSED_EXPRESSION") tick
                        JobCard(stat = stat, live = liveOf(stat, viewModel.timeSync))
                    }
                }
            }
        }
    }
}

@Composable
private fun JobCard(stat: JobStatsDto, live: LiveJob) {
    val running = stat.runningSince != null

    KCard(Modifier.fillMaxWidth()) {
        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Text(stat.title, style = MaterialTheme.typography.titleLarge, modifier = Modifier.weight(1f))
                KChip(
                    text = stringResource(if (running) R.string.job_running else R.string.job_stopped),
                    color = if (running) KabColors.success else KabColors.textSecondary,
                    filled = running,
                )
            }

            if (!running && stat.lastStoppedAt != null) {
                Text(
                    stringResource(R.string.job_stopped_at, formatDateTime(parseInstant(stat.lastStoppedAt))),
                    style = MaterialTheme.typography.bodySmall,
                    color = KabColors.warning,
                )
            }

            if (stat.description.isNotBlank()) {
                Text(stat.description, style = MaterialTheme.typography.bodyMedium)
            }

            KAcorns(
                amount = stat.hourlyRate,
                suffix = stringResource(R.string.job_rate_suffix),
                fontSize = 13.sp,
                fontWeight = FontWeight.Normal,
                color = KabColors.textSecondary,
            )

            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                KStatTile(
                    label = stringResource(R.string.job_total_time),
                    value = formatDuration(live.totalSeconds),
                    valueColor = if (running) KabColors.accent else KabColors.textPrimary,
                    modifier = Modifier.weight(1f),
                )
                KStatTile(
                    label = stringResource(R.string.job_earned_now),
                    value = "",
                    acorns = live.earned,
                    valueColor = KabColors.success,
                    modifier = Modifier.weight(1f),
                )
            }

            Text(
                stringResource(R.string.job_earned_note),
                style = MaterialTheme.typography.bodySmall,
                color = KabColors.textSecondary,
            )
        }
    }
}
