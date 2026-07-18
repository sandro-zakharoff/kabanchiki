package com.kabanchiki.app.core.data

import com.kabanchiki.app.core.model.parseInstant
import io.github.jan.supabase.SupabaseClient
import io.github.jan.supabase.postgrest.postgrest
import kotlinx.datetime.Clock
import kotlinx.datetime.Instant
import javax.inject.Inject
import javax.inject.Singleton
import kotlin.time.Duration
import kotlin.time.Duration.Companion.ZERO

/**
 * Server clock offset. All ticking timers derive from nowServer(), never from
 * the raw device clock, so a wrong phone clock cannot skew money or time.
 */
@Singleton
class TimeSync @Inject constructor(
    private val client: SupabaseClient,
) {
    @Volatile
    private var offset: Duration = ZERO

    suspend fun sync() {
        val raw = client.postgrest.rpc("server_now").data
            .trim().removeSurrounding("\"")
        val server = parseInstant(raw) ?: return
        offset = server - Clock.System.now()
    }

    fun nowServer(): Instant = Clock.System.now() + offset
}
