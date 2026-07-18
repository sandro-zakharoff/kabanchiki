package com.kabanchiki.app.core.data

import com.kabanchiki.app.core.model.BonusDto
import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.postgrest.from
import io.github.jan.supabase.postgrest.query.Order
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class BonusesRepository @Inject constructor(
    private val client: SupabaseClient,
    private val auth: AuthRepository,
) {
    private val _bonuses = MutableStateFlow<List<BonusDto>>(emptyList())
    val bonuses: StateFlow<List<BonusDto>> = _bonuses.asStateFlow()

    suspend fun refresh() {
        val uid = auth.currentUserId ?: return
        _bonuses.value = client.from("bonuses").select {
            filter { eq("child_id", uid) }
            order("created_at", Order.DESCENDING)
            limit(100)
        }.decodeList<BonusDto>()
    }

    fun clear() {
        _bonuses.value = emptyList()
    }
}
