package com.kabanchiki.app.feature.balance

import androidx.compose.foundation.background
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
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.kabanchiki.app.R
import com.kabanchiki.app.core.data.BalanceRepository
import com.kabanchiki.app.core.data.JobsRepository
import com.kabanchiki.app.core.data.TimeSync
import com.kabanchiki.app.core.designsystem.KButton
import com.kabanchiki.app.core.designsystem.KButtonVariant
import com.kabanchiki.app.core.designsystem.KCard
import com.kabanchiki.app.core.designsystem.KChip
import com.kabanchiki.app.core.designsystem.KabColors
import com.kabanchiki.app.core.model.BalanceConfigDto
import com.kabanchiki.app.core.model.JobStatsDto
import com.kabanchiki.app.core.model.LedgerEntryDto
import com.kabanchiki.app.core.model.WithdrawalDto
import com.kabanchiki.app.core.model.formatDateTime
import com.kabanchiki.app.core.designsystem.KAcorns
import com.kabanchiki.app.core.designsystem.acornWords
import com.kabanchiki.app.core.model.parseInstant
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import javax.inject.Inject

@HiltViewModel
class BalanceViewModel @Inject constructor(
    private val balance: BalanceRepository,
    private val jobs: JobsRepository,
    val timeSync: TimeSync,
) : ViewModel() {

    val ledger: StateFlow<List<LedgerEntryDto>> = balance.ledger
    val withdrawals: StateFlow<List<WithdrawalDto>> = balance.withdrawals
    val config: StateFlow<BalanceConfigDto> = balance.config
    val stats: StateFlow<List<JobStatsDto>> = jobs.stats

    private val _busy = MutableStateFlow(false)
    val busy: StateFlow<Boolean> = _busy.asStateFlow()

    private val _refreshing = MutableStateFlow(false)
    val refreshing: StateFlow<Boolean> = _refreshing.asStateFlow()

    // A failed load must never be indistinguishable from "you have nothing".
    // Without this the screen shows a confident 0 with no history, which reads
    // as lost money rather than a load that did not happen.
    private val _loadFailed = MutableStateFlow(false)
    val loadFailed: StateFlow<Boolean> = _loadFailed.asStateFlow()

    fun refresh() {
        viewModelScope.launch {
            _refreshing.value = true
            _loadFailed.value = runCatching { balance.refresh(); jobs.refresh() }.isFailure
            _refreshing.value = false
        }
    }

    /** Live balance: ledger sum + uncredited job accrual (with the live tail). */
    fun liveBalance(): Int =
        com.kabanchiki.app.core.model.liveBalance(ledger.value, stats.value, timeSync)

    fun withdraw(amount: Int?) = action { balance.requestWithdrawal(amount) }
    fun cancel(id: String) = action { balance.cancelWithdrawal(id) }
    fun confirm(id: String) = action { balance.confirmWithdrawal(id) }
    fun decline(id: String) = action { balance.declineWithdrawal(id) }

    private fun action(block: suspend () -> Unit) {
        viewModelScope.launch {
            _busy.value = true
            runCatching { block() }
            _busy.value = false
        }
    }
}

@OptIn(androidx.compose.material3.ExperimentalMaterial3Api::class)
@Composable
fun BalanceScreen(viewModel: BalanceViewModel = hiltViewModel()) {
    val ledger by viewModel.ledger.collectAsState()
    val withdrawals by viewModel.withdrawals.collectAsState()
    val config by viewModel.config.collectAsState()
    val stats by viewModel.stats.collectAsState()
    val busy by viewModel.busy.collectAsState()
    val refreshing by viewModel.refreshing.collectAsState()
    val loadFailed by viewModel.loadFailed.collectAsState()

    LaunchedEffect(Unit) { viewModel.refresh() }

    var tick by remember { mutableLongStateOf(0L) }
    LaunchedEffect(stats.any { it.runningSince != null }) {
        while (true) { delay(1000); tick++ }
    }
    @Suppress("UNUSED_EXPRESSION") tick
    val balance = viewModel.liveBalance()

    var showWithdraw by remember { mutableStateOf(false) }
    // Cash payouts awaiting the assignee's confirmation.
    val toConfirm = withdrawals.filter { it.status == "paid" && it.method == "cash" }
    val openRequests = withdrawals.filter { it.status == "requested" || it.status == "approved" }

    Column(Modifier.fillMaxSize()) {
        Text(
            stringResource(R.string.balance_title),
            style = MaterialTheme.typography.headlineMedium,
            modifier = Modifier.padding(start = 20.dp, top = 20.dp, bottom = 8.dp),
        )

        androidx.compose.material3.pulltorefresh.PullToRefreshBox(
            isRefreshing = refreshing,
            onRefresh = viewModel::refresh,
            modifier = Modifier.fillMaxSize(),
        ) {
            LazyColumn(
                modifier = Modifier.fillMaxSize(),
                contentPadding = androidx.compose.foundation.layout.PaddingValues(16.dp),
                verticalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                // ---- balance hero ----
                item {
                    KCard(Modifier.fillMaxWidth()) {
                        Column(
                            Modifier.fillMaxWidth().padding(20.dp),
                            horizontalAlignment = Alignment.CenterHorizontally,
                            verticalArrangement = Arrangement.spacedBy(6.dp),
                        ) {
                            Text(
                                stringResource(R.string.balance_available),
                                style = MaterialTheme.typography.labelMedium,
                                color = KabColors.textSecondary,
                            )
                            if (loadFailed) {
                                // Say the balance is unknown rather than show a 0
                                // that looks like an empty account.
                                Text(
                                    "—",
                                    fontSize = 40.sp,
                                    fontWeight = FontWeight.Bold,
                                    color = KabColors.textSecondary,
                                )
                                Text(
                                    stringResource(R.string.balance_load_failed),
                                    style = MaterialTheme.typography.bodySmall,
                                    color = KabColors.danger,
                                    textAlign = androidx.compose.ui.text.style.TextAlign.Center,
                                )
                            } else {
                                KAcorns(
                                    amount = balance,
                                    fontSize = 40.sp,
                                    fontWeight = FontWeight.Bold,
                                    color = KabColors.accent,
                                )
                            }
                            Spacer(Modifier.height(4.dp))
                            if (config.withdrawalsEnabled && !loadFailed) {
                                KButton(
                                    text = stringResource(R.string.balance_withdraw),
                                    onClick = { showWithdraw = true },
                                    enabled = !busy && balance >= config.minWithdrawal && balance > 0,
                                    modifier = Modifier.fillMaxWidth(),
                                )
                                if (balance < config.minWithdrawal) {
                                    Text(
                                        stringResource(R.string.balance_min_hint, acornWords(config.minWithdrawal)),
                                        style = MaterialTheme.typography.bodySmall,
                                        color = KabColors.textSecondary,
                                    )
                                }
                            } else {
                                Text(
                                    stringResource(R.string.balance_withdrawals_off),
                                    style = MaterialTheme.typography.bodySmall,
                                    color = KabColors.textSecondary,
                                )
                            }
                        }
                    }
                }

                // ---- cash to confirm ----
                items(toConfirm, key = { "cc-" + it.id }) { w ->
                    KCard(Modifier.fillMaxWidth()) {
                        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                            Text(
                                stringResource(R.string.balance_confirm_cash, acornWords(w.amount)),
                                style = MaterialTheme.typography.titleMedium,
                            )
                            if (!w.comment.isNullOrBlank()) {
                                Text(w.comment, style = MaterialTheme.typography.bodySmall, color = KabColors.textSecondary)
                            }
                            KButton(
                                text = stringResource(R.string.balance_confirm_received),
                                onClick = { viewModel.confirm(w.id) },
                                enabled = !busy,
                                modifier = Modifier.fillMaxWidth(),
                            )
                            KButton(
                                text = stringResource(R.string.balance_not_received),
                                onClick = { viewModel.decline(w.id) },
                                variant = KButtonVariant.Danger,
                                enabled = !busy,
                                modifier = Modifier.fillMaxWidth(),
                            )
                        }
                    }
                }

                // ---- open requests ----
                if (openRequests.isNotEmpty()) {
                    item { SectionLabel(stringResource(R.string.balance_your_requests)) }
                    items(openRequests, key = { "req-" + it.id }) { w ->
                        RequestRow(w, busy) { viewModel.cancel(w.id) }
                    }
                }

                // ---- operations feed ----
                item { SectionLabel(stringResource(R.string.balance_operations)) }
                if (ledger.isEmpty()) {
                    item {
                        Text(
                            stringResource(R.string.balance_no_ops),
                            style = MaterialTheme.typography.bodyMedium,
                            color = KabColors.textSecondary,
                            modifier = Modifier.padding(vertical = 16.dp),
                        )
                    }
                }
                items(ledger, key = { it.id }) { e -> LedgerRow(e) }
            }
        }
    }

    if (showWithdraw) {
        WithdrawSheet(
            balance = balance,
            minWithdrawal = config.minWithdrawal,
            busy = busy,
            onDismiss = { showWithdraw = false },
            onConfirm = { amount -> showWithdraw = false; viewModel.withdraw(amount) },
        )
    }
}

@Composable
private fun SectionLabel(text: String) {
    Text(
        text,
        style = MaterialTheme.typography.labelMedium,
        color = KabColors.textSecondary,
        modifier = Modifier.padding(top = 6.dp, start = 4.dp),
    )
}

@Composable
private fun RequestRow(w: WithdrawalDto, busy: Boolean, onCancel: () -> Unit) {
    val (label, color) = when (w.status) {
        "approved" -> stringResource(R.string.balance_status_approved) to KabColors.info
        else -> stringResource(R.string.balance_status_requested) to KabColors.warning
    }
    KCard(Modifier.fillMaxWidth()) {
        Row(
            Modifier.fillMaxWidth().padding(14.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            Column(Modifier.weight(1f)) {
                KAcorns(amount = w.amount, fontSize = 16.sp, fontWeight = FontWeight.Medium)
                Text(
                    formatDateTime(parseInstant(w.requestedAt)),
                    style = MaterialTheme.typography.bodySmall,
                    color = KabColors.textSecondary,
                )
            }
            KChip(text = label, color = color, filled = true)
            KButton(
                text = stringResource(R.string.balance_cancel),
                onClick = onCancel,
                variant = KButtonVariant.Ghost,
                enabled = !busy,
            )
        }
    }
}

@Composable
private fun LedgerRow(e: LedgerEntryDto) {
    val positive = e.amount >= 0
    val (icon, tint) = when (e.kind) {
        "task" -> "✓" to KabColors.success
        "job" -> "⏱" to KabColors.accent
        "bonus" -> "★" to KabColors.warning
        "adjustment" -> "±" to KabColors.info
        "withdrawal" -> "↑" to KabColors.danger
        else -> "↺" to KabColors.textSecondary
    }
    val title = kindTitle(e.kind)
    Row(
        Modifier.fillMaxWidth().padding(vertical = 4.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Box(
            Modifier.size(38.dp).clip(CircleShape).background(tint.copy(alpha = 0.14f)),
            contentAlignment = Alignment.Center,
        ) { Text(icon, color = tint) }
        Column(Modifier.weight(1f)) {
            Text(
                if (e.note.isNotBlank()) "$title · ${e.note}" else title,
                style = MaterialTheme.typography.titleMedium,
                maxLines = 1,
            )
            Text(
                formatDateTime(parseInstant(e.createdAt)),
                style = MaterialTheme.typography.bodySmall,
                color = KabColors.textSecondary,
            )
        }
        KAcorns(
            amount = e.amount,
            signed = true,
            fontSize = 16.sp,
            fontWeight = FontWeight.Bold,
            color = if (positive) KabColors.success else KabColors.danger,
        )
    }
}

@Composable
private fun kindTitle(kind: String): String = when (kind) {
    "task" -> stringResource(R.string.ledger_task)
    "job" -> stringResource(R.string.ledger_job)
    "bonus" -> stringResource(R.string.ledger_bonus)
    "adjustment" -> stringResource(R.string.ledger_adjustment)
    "withdrawal" -> stringResource(R.string.ledger_withdrawal)
    else -> stringResource(R.string.ledger_reversal)
}

@OptIn(androidx.compose.material3.ExperimentalMaterial3Api::class)
@Composable
private fun WithdrawSheet(
    balance: Int,
    minWithdrawal: Int,
    busy: Boolean,
    onDismiss: () -> Unit,
    onConfirm: (Int?) -> Unit,
) {
    // Acorns are indivisible, so the field holds digits and nothing else: a
    // number keyboard, and every non-digit dropped on the way in. Comparisons
    // are then exact and need no epsilon.
    var text by remember { mutableStateOf(balance.toString()) }
    val amount = text.toIntOrNull()
    val error = when {
        text.isBlank() || amount == null -> null
        amount < minWithdrawal -> stringResource(R.string.withdraw_below_min, acornWords(minWithdrawal))
        amount > balance -> stringResource(R.string.withdraw_above_balance, acornWords(balance))
        else -> null
    }
    val valid = amount != null && amount >= minWithdrawal && amount <= balance

    androidx.compose.material3.ModalBottomSheet(
        onDismissRequest = onDismiss,
        containerColor = KabColors.surface,
    ) {
        Column(
            Modifier.padding(start = 20.dp, end = 20.dp, bottom = 28.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            Text(stringResource(R.string.withdraw_title), style = MaterialTheme.typography.titleLarge)
            Row(horizontalArrangement = Arrangement.spacedBy(16.dp)) {
                Column {
                    Text(stringResource(R.string.withdraw_balance), style = MaterialTheme.typography.labelSmall)
                    KAcorns(amount = balance, fontSize = 16.sp, color = KabColors.success)
                }
                Column {
                    Text(stringResource(R.string.withdraw_min), style = MaterialTheme.typography.labelSmall)
                    KAcorns(amount = minWithdrawal, fontSize = 16.sp)
                }
            }
            androidx.compose.material3.OutlinedTextField(
                value = text,
                onValueChange = { input -> text = input.filter { it.isDigit() }.take(9) },
                label = { Text(stringResource(R.string.withdraw_amount)) },
                singleLine = true,
                isError = error != null,
                supportingText = error?.let { { Text(it, color = KabColors.danger) } },
                keyboardOptions = androidx.compose.foundation.text.KeyboardOptions(
                    keyboardType = androidx.compose.ui.text.input.KeyboardType.Number,
                ),
                modifier = Modifier.fillMaxWidth(),
            )
            KButton(
                text = stringResource(R.string.withdraw_all, acornWords(balance)),
                onClick = { onConfirm(null) },
                variant = KButtonVariant.Secondary,
                enabled = !busy,
                modifier = Modifier.fillMaxWidth(),
            )
            KButton(
                text = stringResource(R.string.withdraw_confirm),
                onClick = { onConfirm(amount) },
                enabled = valid && !busy,
                modifier = Modifier.fillMaxWidth(),
            )
        }
    }
}
