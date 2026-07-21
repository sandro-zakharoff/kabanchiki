package com.kabanchiki.app.core.model

import com.kabanchiki.app.core.data.TimeSync

/**
 * Live personal balance = ledger sum + uncredited job accrual (with the live
 * tail for a running job). Mirrors public.assignee_balance(); the server stays
 * the source of truth. Shared by the Balance screen and the profile widget.
 *
 * Everything here is whole acorns. The tail comes from the exact acorn-seconds
 * accumulator rather than from an already-rounded amount, so the number shown
 * while a job runs is precisely the one the next settlement will post — the
 * balance never jumps when the settle cron lands.
 */
fun liveBalance(
    ledger: List<LedgerEntryDto>,
    stats: List<JobStatsDto>,
    timeSync: TimeSync,
): Int {
    val ledgerSum = ledger.sumOf { it.amount }
    val tail = stats.sumOf { stat ->
        val snapshot = parseInstant(stat.snapshotAt)
        val running = stat.runningSince != null
        val extra = if (running && snapshot != null) {
            (timeSync.nowServer() - snapshot).inWholeSeconds.coerceAtLeast(0)
        } else {
            0L
        }
        // The uncredited tail is non-negative by construction: credited_amount is
        // floor(accrued / 3600) at the last settlement, and accrued only grows.
        // A negative value can therefore only mean the snapshot and the ledger
        // disagree — clamp instead of quietly subtracting from the balance.
        (liveAcorns(stat.accruedAcornSeconds, extra, stat.hourlyRate) - stat.creditedAmount)
            .coerceAtLeast(0)
    }
    return ledgerSum + tail
}
