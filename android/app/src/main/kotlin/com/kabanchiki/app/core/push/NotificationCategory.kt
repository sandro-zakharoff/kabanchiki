package com.kabanchiki.app.core.push

import com.kabanchiki.app.R

/**
 * The notification groups whose sound the assignee can choose independently.
 * Each maps to one Android notification channel (its sound baked in at
 * creation, hence the recreate-on-change dance in [NotificationChannels]).
 *
 * [channelBase] stays equal to the historical channel names so the mapping of
 * events to groups is unchanged; only the sound now varies.
 */
enum class NotificationCategory(
    val key: String,
    val channelBase: String,
    val titleRes: Int,
    val descRes: Int,
    val default: NotificationSound,
) {
    TASKS("tasks", "tasks", R.string.channel_tasks, R.string.sound_cat_tasks_desc, NotificationSound.CLASSIC),
    JOBS("jobs", "job", R.string.channel_job, R.string.sound_cat_jobs_desc, NotificationSound.CLASSIC),
    PAYOUTS("payouts", "decisions", R.string.channel_decisions, R.string.sound_cat_payouts_desc, NotificationSound.CLASSIC),
    SYSTEM("system", "system", R.string.channel_system, R.string.sound_cat_system_desc, NotificationSound.CLASSIC),
}
