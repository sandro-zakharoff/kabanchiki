package com.kabanchiki.app.core.data

import com.kabanchiki.app.core.model.BalanceConfigDto
import com.kabanchiki.app.core.model.LedgerEntryDto
import com.kabanchiki.app.core.model.WithdrawalDto
import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.postgrest.from
import io.github.jan.supabase.postgrest.postgrest
import io.github.jan.supabase.postgrest.query.Order
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import javax.inject.Inject
import javax.inject.Singleton

/**
 * The assignee's personal balance: the append-only ledger, their payout
 * requests and the global money settings. The balance itself is derived from
 * the ledger plus the live job tail (computed in the ViewModel), never stored.
 */
@Singleton
class BalanceRepository @Inject constructor(
    private val client: SupabaseClient,
    private val auth: AuthRepository,
) {
    private val _ledger = MutableStateFlow<List<LedgerEntryDto>>(emptyList())
    val ledger: StateFlow<List<LedgerEntryDto>> = _ledger.asStateFlow()

    private val _withdrawals = MutableStateFlow<List<WithdrawalDto>>(emptyList())
    val withdrawals: StateFlow<List<WithdrawalDto>> = _withdrawals.asStateFlow()

    private val _config = MutableStateFlow(BalanceConfigDto())
    val config: StateFlow<BalanceConfigDto> = _config.asStateFlow()

    suspend fun refresh() {
        val uid = auth.currentUserId ?: return
        _ledger.value = client.from("ledger_entries").select {
            filter { eq("child_id", uid) }
            order("id", Order.DESCENDING)
            limit(400)
        }.decodeList<LedgerEntryDto>()

        _withdrawals.value = client.from("withdrawals").select {
            filter { eq("child_id", uid) }
            order("requested_at", Order.DESCENDING)
            limit(100)
        }.decodeList<WithdrawalDto>()

        _config.value = client.from("app_config").select().decodeList<BalanceConfigDto>()
            .firstOrNull() ?: BalanceConfigDto()
    }

    /** amount == null cashes out the whole balance. Returns the new payout id. */
    suspend fun requestWithdrawal(amount: Double? = null): String {
        val result = client.postgrest.rpc(
            "request_withdrawal",
            buildJsonObject { if (amount != null) put("p_amount", amount) },
        )
        refresh()
        return result.data.trim().removeSurrounding("\"")
    }

    suspend fun cancelWithdrawal(id: String) {
        client.postgrest.rpc("cancel_withdrawal", buildJsonObject { put("p_id", id) })
        refresh()
    }

    suspend fun confirmWithdrawal(id: String) {
        client.postgrest.rpc("confirm_withdrawal", buildJsonObject { put("p_id", id) })
        refresh()
    }

    suspend fun declineWithdrawal(id: String) {
        client.postgrest.rpc("decline_withdrawal", buildJsonObject { put("p_id", id) })
        refresh()
    }

    fun clear() {
        _ledger.value = emptyList()
        _withdrawals.value = emptyList()
        _config.value = BalanceConfigDto()
    }
}
