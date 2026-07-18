package com.kabanchiki.app.core.data

import com.kabanchiki.app.core.model.JobStatsDto
import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.postgrest.from
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class JobsRepository @Inject constructor(
    private val client: SupabaseClient,
    private val auth: AuthRepository,
) {
    private val _stats = MutableStateFlow<List<JobStatsDto>>(emptyList())
    val stats: StateFlow<List<JobStatsDto>> = _stats.asStateFlow()

    suspend fun refresh() {
        val uid = auth.currentUserId ?: return
        _stats.value = client.from("job_member_stats").select {
            filter { eq("child_id", uid) }
        }.decodeList<JobStatsDto>().filter { it.status != "archived" }
    }

    fun clear() {
        _stats.value = emptyList()
    }
}
