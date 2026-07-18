package com.kabanchiki.app.core.model

import com.kabanchiki.app.core.data.TimeSync
import kotlin.math.floor

/**
 * Live personal balance = ledger sum + uncredited job accrual (with the live
 * tail for a running job). Mirrors public.assignee_balance(); the server stays
 * the source of truth. Shared by the Balance screen and the profile widget.
 */
fun liveBalance(
    ledger: List<LedgerEntryDto>,
    stats: List<JobStatsDto>,
    timeSync: TimeSync,
): Double {
    val ledgerSum = ledger.sumOf { it.amount }
    val tail = stats.sumOf { stat ->
        val snapshot = parseInstant(stat.snapshotAt)
        val running = stat.runningSince != null
        val extra = if (running && snapshot != null)
            (timeSync.nowServer() - snapshot).inWholeSeconds.coerceAtLeast(0) else 0L
        val uncredited = stat.earnedTotal - stat.creditedAmount
        uncredited + floor(extra / 3600.0 * stat.hourlyRate * 100) / 100.0
    }
    return floor((ledgerSum + tail) * 100) / 100.0
}
