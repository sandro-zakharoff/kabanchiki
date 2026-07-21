package com.kabanchiki.app.core.model

import kotlinx.datetime.Instant
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

// ---------------------------------------------------------------- parsing

/** Postgres timestamps arrive as ISO strings, sometimes with a short offset. */
fun parseInstant(raw: String?): Instant? {
    if (raw.isNullOrBlank()) return null
    var text = raw.replace(' ', 'T')
    // "+00" -> "+00:00"
    val shortOffset = Regex("([+-]\\d{2})$")
    if (shortOffset.containsMatchIn(text)) text += ":00"
    return runCatching { Instant.parse(text) }.getOrNull()
}

// ---------------------------------------------------------------- DTOs

@Serializable
data class ProfileDto(
    val id: String,
    val username: String,
    @SerialName("display_name") val displayName: String,
    @SerialName("avatar_color") val avatarColor: String = "#CDB1B1",
    @SerialName("avatar_storage") val avatarStorage: String? = null,
    @SerialName("avatar_path") val avatarPath: String? = null,
    val blocked: Boolean = false,
)

@Serializable
data class AttachmentDto(
    val id: String,
    @SerialName("task_id") val taskId: String? = null,
    @SerialName("withdrawal_id") val withdrawalId: String? = null,
    val role: String, // "task" | "proof" | "receipt"
    val storage: String = "supabase", // "supabase" | "drive"
    val path: String,
    @SerialName("thumb_path") val thumbPath: String? = null,
    val mime: String = "image/jpeg",
)

@Serializable
data class TaskDto(
    val id: String,
    @SerialName("child_id") val childId: String,
    val title: String,
    val description: String = "",
    @SerialName("photo_path") val photoPath: String? = null,
    @SerialName("reward_type") val rewardType: String,
    @SerialName("reward_amount") @Serializable(with = AcornSerializer::class) val rewardAmount: Int,
    @SerialName("completion_mode") val completionMode: String = "timer",
    val difficulty: Int = 1,
    val requirements: String = "",
    @SerialName("proof_text") val proofText: String = "none",
    @SerialName("proof_photo") val proofPhoto: String = "none",
    val status: String,
    @SerialName("proof_text_content") val proofTextContent: String? = null,
    @SerialName("proof_photo_path") val proofPhotoPath: String? = null,
    @SerialName("decline_reason") val declineReason: String? = null,
    @SerialName("total_seconds") val totalSeconds: Int = 0,
    @SerialName("earned_amount") @Serializable(with = AcornSerializer::class) val earnedAmount: Int? = null,
    @SerialName("created_at") val createdAt: String,
    @SerialName("started_at") val startedAt: String? = null,
    @SerialName("completed_at") val completedAt: String? = null,
    @SerialName("created_by_name") val createdByName: String = "",
    @SerialName("deadline_at") val deadlineAt: String? = null,
)

@Serializable
data class TaskIntervalDto(
    @SerialName("task_id") val taskId: String,
    @SerialName("started_at") val startedAt: String,
    @SerialName("ended_at") val endedAt: String? = null,
)

@Serializable
data class JobStatsDto(
    @SerialName("job_id") val jobId: String,
    @SerialName("child_id") val childId: String,
    val title: String,
    val description: String = "",
    @SerialName("hourly_rate") @Serializable(with = AcornSerializer::class) val hourlyRate: Int,
    val status: String,
    @SerialName("credited_amount") @Serializable(with = AcornSerializer::class) val creditedAmount: Int = 0,
    @SerialName("total_seconds") val totalSeconds: Long = 0,
    @SerialName("earned_seconds") val earnedSeconds: Long = 0,
    // Earned on this job so far (flows to the personal balance).
    @SerialName("earned_total") @Serializable(with = AcornSerializer::class) val earnedTotal: Int = 0,
    // Exact, un-rounded earning at snapshot time, in acorn-seconds (seconds x
    // rate). Ticking this forward and flooring by 3600 is what settle_job_member
    // does, so the live number never drifts from what the server will credit.
    @SerialName("accrued_acorn_seconds") val accruedAcornSeconds: Long = 0,
    @SerialName("running_since") val runningSince: String? = null,
    @SerialName("last_stopped_at") val lastStoppedAt: String? = null,
    @SerialName("snapshot_at") val snapshotAt: String,
)

/** One entry of the personal ledger (append-only balance journal). */
@Serializable
data class LedgerEntryDto(
    val id: Long,
    @SerialName("child_id") val childId: String,
    @Serializable(with = AcornSerializer::class) val amount: Int,
    val kind: String, // task | job | bonus | adjustment | withdrawal | reversal
    @SerialName("source_type") val sourceType: String? = null,
    val note: String = "",
    @SerialName("created_at") val createdAt: String,
    @SerialName("actor_name") val actorName: String = "",
)

/** Global money settings the app needs (from app_config). */
@Serializable
data class BalanceConfigDto(
    @SerialName("min_withdrawal") @Serializable(with = AcornSerializer::class) val minWithdrawal: Int = 0,
    @SerialName("withdrawals_enabled") val withdrawalsEnabled: Boolean = true,
)

@Serializable
data class AppReleaseDto(
    val id: String,
    val platform: String = "android",
    @SerialName("version_name") val versionName: String,
    @SerialName("version_code") val versionCode: Int,
    @SerialName("apk_path") val apkPath: String,
    val notes: String = "",
    val mandatory: Boolean = false,
)

@Serializable
data class BonusDto(
    val id: String,
    @SerialName("child_id") val childId: String,
    @Serializable(with = AcornSerializer::class) val amount: Int,
    val note: String = "",
    @SerialName("created_at") val createdAt: String,
)

@Serializable
data class WithdrawalDto(
    val id: String,
    @SerialName("child_id") val childId: String,
    @Serializable(with = AcornSerializer::class) val amount: Int,
    val status: String, // requested | approved | paid | confirmed | rejected
    val method: String? = null, // card | cash
    val comment: String? = null,
    @SerialName("reject_reason") val rejectReason: String? = null,
    @SerialName("requested_at") val requestedAt: String,
    @SerialName("approved_at") val approvedAt: String? = null,
    @SerialName("paid_at") val paidAt: String? = null,
    @SerialName("confirmed_at") val confirmedAt: String? = null,
)

// ---------------------------------------------------------------- enums

enum class TaskStatus(val wire: String) {
    New("new"), Declined("declined"), InProgress("in_progress"), Paused("paused"),
    Submitted("submitted"), Done("done");

    companion object {
        fun from(wire: String): TaskStatus = entries.firstOrNull { it.wire == wire } ?: New
    }
}

enum class ProofRequirement(val wire: String) {
    None("none"), Optional("optional"), Required("required");

    companion object {
        fun from(wire: String): ProofRequirement = entries.firstOrNull { it.wire == wire } ?: None
    }
}
