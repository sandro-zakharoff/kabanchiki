package com.kabanchiki.app.core.model

import kotlinx.datetime.Clock
import kotlinx.datetime.Instant
import kotlinx.datetime.TimeZone
import kotlinx.datetime.todayIn
import kotlinx.datetime.toLocalDateTime
import kotlin.math.abs

/**
 * 1234567 -> "1 234 567" — the number only (same as the desktop app).
 *
 * Acorns are indivisible, so there is never a fractional part, and the acorn
 * mark is an icon drawn beside the number (see KAcorns) rather than a character
 * glued onto the string: an image cannot be aligned to the baseline from inside
 * a String. For places that cannot draw an icon — notifications, the bot — use
 * the `acorns` plural resource instead, which gives the declined word.
 */
fun formatAcorns(amount: Int): String {
    val sign = if (amount < 0) "-" else ""
    val grouped = abs(amount).toString().reversed().chunked(3).joinToString(" ").reversed()
    return "$sign$grouped"
}

/**
 * Whole acorns for a running job, ticked forward from the server snapshot.
 *
 * Mirrors settle_job_member(): the exact earning is carried as acorn-seconds
 * (seconds x rate, both integers), so the ticking number and the number the
 * server credits can never disagree — and the balance does not jump when the
 * settle cron lands.
 */
fun liveAcorns(accruedAcornSeconds: Long, extraSeconds: Long, hourlyRate: Int): Int {
    val total = accruedAcornSeconds + extraSeconds * hourlyRate
    return (total.coerceAtLeast(0) / 3600).toInt()
}

/** 3725 -> "1:02:05" (hours keep growing, no day wrap). */
fun formatDuration(totalSeconds: Long): String {
    val s = totalSeconds.coerceAtLeast(0)
    val hours = s / 3600
    val minutes = (s % 3600) / 60
    val seconds = s % 60
    return "%d:%02d:%02d".format(hours, minutes, seconds)
}

fun formatDateTime(instant: Instant?): String {
    if (instant == null) return ""
    val dt = instant.toLocalDateTime(TimeZone.currentSystemDefault())
    return "%02d.%02d.%04d %02d:%02d".format(dt.dayOfMonth, dt.monthNumber, dt.year, dt.hour, dt.minute)
}

fun formatDate(instant: Instant?): String {
    if (instant == null) return ""
    val dt = instant.toLocalDateTime(TimeZone.currentSystemDefault())
    return "%02d.%02d.%04d".format(dt.dayOfMonth, dt.monthNumber, dt.year)
}

enum class DeadlineState { NONE, NORMAL, SOON, OVERDUE }

const val DEADLINE_SOON_HOURS = 24

/** Human deadline text + state — same wording/thresholds as desktop & Mini App. */
fun formatDeadline(instant: Instant?): Pair<String, DeadlineState> {
    if (instant == null) return "" to DeadlineState.NONE
    val tz = TimeZone.currentSystemDefault()
    val now = Clock.System.now()
    val secs = (instant - now).inWholeSeconds
    val dt = instant.toLocalDateTime(tz)
    val hhmm = "%02d:%02d".format(dt.hour, dt.minute)

    val state = when {
        secs < 0 -> DeadlineState.OVERDUE
        secs <= DEADLINE_SOON_HOURS * 3600 -> DeadlineState.SOON
        else -> DeadlineState.NORMAL
    }
    val dayDiff = instant.toLocalDateTime(tz).date.toEpochDays() -
        Clock.System.todayIn(tz).toEpochDays()
    val text = when {
        state == DeadlineState.OVERDUE -> "прострочено · ${formatDateTime(instant)}"
        dayDiff == 0 -> "сьогодні до $hhmm"
        dayDiff == 1 -> "завтра $hhmm"
        dayDiff in 2..6 -> "через $dayDiff дн${if (dayDiff < 5) "і" else "ів"}"
        else -> formatDateTime(instant)
    }
    return text to state
}
