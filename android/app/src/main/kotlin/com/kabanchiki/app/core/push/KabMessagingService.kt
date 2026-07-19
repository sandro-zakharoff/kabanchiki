package com.kabanchiki.app.core.push

import android.Manifest
import android.app.PendingIntent
import android.content.Intent
import android.content.pm.PackageManager
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import com.google.firebase.messaging.FirebaseMessagingService
import com.google.firebase.messaging.RemoteMessage
import com.kabanchiki.app.MainActivity
import com.kabanchiki.app.R
import com.kabanchiki.app.core.data.DeviceRepository
import com.kabanchiki.app.core.model.formatMoney
import dagger.hilt.android.AndroidEntryPoint
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import javax.inject.Inject

/**
 * Renders data-only FCM messages sent by the send-push Edge Function.
 * Building the notification locally gives localized text and per-channel
 * custom sounds even when the app process was dead.
 */
@AndroidEntryPoint
class KabMessagingService : FirebaseMessagingService() {

    @Inject
    lateinit var deviceRepository: DeviceRepository

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    override fun onNewToken(token: String) {
        scope.launch { deviceRepository.registerToken(token) }
    }

    override fun onMessageReceived(message: RemoteMessage) {
        val data = message.data
        val event = data["event_type"] ?: return
        NotificationChannels.ensure(this)

        val (category, title, body) = when (event) {
            "task_created" -> Triple(
                NotificationCategory.TASKS,
                getString(R.string.notif_task_created_title),
                getString(
                    R.string.notif_task_created_body,
                    data["title"].orEmpty(),
                    rewardText(data["reward_type"], data["reward_amount"]),
                ),
            )
            "job_assigned" -> Triple(
                NotificationCategory.JOBS,
                getString(R.string.notif_job_assigned_title),
                getString(
                    R.string.notif_job_assigned_body,
                    data["title"].orEmpty(),
                    formatMoney(data["hourly_rate"]?.toDoubleOrNull() ?: 0.0),
                ),
            )
            "job_started" -> Triple(
                NotificationCategory.JOBS,
                getString(R.string.notif_job_started_title),
                getString(R.string.notif_job_started_body, data["title"].orEmpty()),
            )
            "job_stopped" -> Triple(
                NotificationCategory.JOBS,
                getString(R.string.notif_job_stopped_title),
                getString(R.string.notif_job_stopped_body, data["title"].orEmpty()),
            )
            "withdrawal_approved" -> {
                val amount = formatMoney(data["amount"]?.toDoubleOrNull() ?: 0.0)
                Triple(
                    NotificationCategory.PAYOUTS,
                    getString(R.string.notif_withdrawal_approved_title),
                    getString(R.string.notif_withdrawal_approved_body, amount),
                )
            }
            "withdrawal_rejected" -> {
                val amount = formatMoney(data["amount"]?.toDoubleOrNull() ?: 0.0)
                val reason = data["reason"].orEmpty()
                Triple(
                    NotificationCategory.PAYOUTS,
                    getString(R.string.notif_withdrawal_declined_title),
                    if (reason.isBlank()) getString(R.string.notif_withdrawal_declined_body, amount)
                    else getString(R.string.notif_withdrawal_declined_note, amount, reason),
                )
            }
            "withdrawal_cash_pending" -> {
                val amount = formatMoney(data["amount"]?.toDoubleOrNull() ?: 0.0)
                Triple(
                    NotificationCategory.PAYOUTS,
                    getString(R.string.notif_cash_pending_title),
                    getString(R.string.notif_cash_pending_body, amount),
                )
            }
            "balance_adjusted" -> {
                val amount = data["amount"]?.toDoubleOrNull() ?: 0.0
                val note = data["note"].orEmpty()
                val signed = (if (amount >= 0) "+" else "") + formatMoney(amount)
                Triple(
                    NotificationCategory.PAYOUTS,
                    getString(R.string.notif_adjust_title, signed),
                    if (note.isBlank()) getString(R.string.notif_adjust_body_plain)
                    else getString(R.string.notif_adjust_body, note),
                )
            }
            "bonus_granted" -> {
                val amount = formatMoney(data["amount"]?.toDoubleOrNull() ?: 0.0)
                val note = data["note"].orEmpty()
                Triple(
                    NotificationCategory.PAYOUTS,
                    getString(R.string.notif_bonus_title, amount),
                    if (note.isBlank()) getString(R.string.notif_bonus_body_plain)
                    else getString(R.string.notif_bonus_body, note),
                )
            }
            "app_update" -> Triple(
                NotificationCategory.SYSTEM,
                getString(R.string.notif_update_title, data["version_name"].orEmpty()),
                data["notes"].orEmpty().ifBlank { getString(R.string.notif_update_body) },
            )
            "deadline_soon" -> Triple(
                NotificationCategory.TASKS,
                getString(R.string.notif_deadline_title),
                getString(R.string.notif_deadline_body, data["title"].orEmpty()),
            )
            "task_reviewed" -> {
                val title = data["title"].orEmpty()
                val note = data["note"].orEmpty()
                when (data["action"]) {
                    "approve" -> Triple(
                        NotificationCategory.PAYOUTS,
                        getString(R.string.notif_task_approved_title),
                        getString(R.string.notif_task_approved_body, title),
                    )
                    "rework" -> Triple(
                        NotificationCategory.TASKS,
                        getString(R.string.notif_task_rework_title),
                        if (note.isBlank()) getString(R.string.notif_task_rework_body, title)
                        else getString(R.string.notif_task_rework_note, title, note),
                    )
                    else -> Triple(
                        NotificationCategory.PAYOUTS,
                        getString(R.string.notif_task_rejected_title),
                        if (note.isBlank()) getString(R.string.notif_task_rejected_body, title)
                        else getString(R.string.notif_task_rejected_note, title, note),
                    )
                }
            }
            "withdrawal_paid" -> Triple(
                NotificationCategory.PAYOUTS,
                getString(R.string.notif_paid_title, formatMoney(data["amount"]?.toDoubleOrNull() ?: 0.0)),
                getString(R.string.notif_withdrawal_paid_body),
            )
            else -> return
        }

        showNotification(event, NotificationChannels.channelId(this, category), title, body)
    }

    private fun rewardText(type: String?, amount: String?): String {
        val money = formatMoney(amount?.toDoubleOrNull() ?: 0.0)
        return if (type == "hourly") getString(R.string.task_reward_hourly, money) else money
    }

    private fun showNotification(event: String, channel: String, title: String, body: String) {
        if (
            android.os.Build.VERSION.SDK_INT >= 33 &&
            checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
        ) {
            return
        }
        val intent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            putExtra("event_type", event)
        }
        val pending = PendingIntent.getActivity(
            this,
            event.hashCode(),
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val notification = NotificationCompat.Builder(this, channel)
            .setSmallIcon(R.drawable.ic_notification)
            .setContentTitle(title)
            .setContentText(body)
            .setStyle(NotificationCompat.BigTextStyle().bigText(body))
            .setAutoCancel(true)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setContentIntent(pending)
            .build()
        NotificationManagerCompat.from(this).notify(System.currentTimeMillis().toInt(), notification)
    }
}
