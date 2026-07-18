package com.kabanchiki.app.core.model

import kotlinx.datetime.Clock
import kotlinx.datetime.Instant
import kotlinx.datetime.TimeZone
import kotlinx.datetime.todayIn
import kotlinx.datetime.toLocalDateTime
import kotlin.math.abs
import kotlin.math.roundToLong

/** 1234567.5 -> "1 234 567.50 ₴" (same format as the desktop app). */
fun formatMoney(amount: Double): String {
    val sign = if (amount < 0) "-" else ""
    val cents = abs(amount * 100).roundToLong()
    val whole = cents / 100
    val frac = cents % 100
    val grouped = whole.toString().reversed().chunked(3).joinToString(" ").reversed()
    return "$sign$grouped.${frac.toString().padStart(2, '0')} ₴"
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
