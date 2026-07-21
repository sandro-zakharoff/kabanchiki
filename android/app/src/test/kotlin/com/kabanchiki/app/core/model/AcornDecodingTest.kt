package com.kabanchiki.app.core.model

import kotlinx.serialization.json.Json
import kotlin.test.Test
import kotlin.test.assertEquals

/**
 * Guards the failure that blanked every balance in the field: money declared as
 * a strict `Int` rejected `953.13` from a server that had not been migrated yet,
 * and kotlinx aborts the WHOLE response on one bad field — so the ledger, the
 * payouts and the balance all came back empty and the screen showed a confident
 * `0`. Decoding must survive a number the app did not expect.
 */
class AcornDecodingTest {
    private val json = Json { ignoreUnknownKeys = true }

    @Test
    fun `fractional amounts decode to whole acorns instead of failing`() {
        val e = json.decodeFromString<LedgerEntryDto>(
            """{"id":1,"child_id":"c","amount":953.13,"kind":"task","created_at":"2026-07-21T10:00:00Z"}""",
        )
        assertEquals(953, e.amount)
    }

    @Test
    fun `whole amounts decode unchanged`() {
        val e = json.decodeFromString<LedgerEntryDto>(
            """{"id":2,"child_id":"c","amount":953,"kind":"job","created_at":"2026-07-21T10:00:00Z"}""",
        )
        assertEquals(953, e.amount)
    }

    @Test
    fun `negative and rounding-boundary amounts decode correctly`() {
        fun amount(raw: String) = json.decodeFromString<LedgerEntryDto>(
            """{"id":3,"child_id":"c","amount":$raw,"kind":"adjustment","created_at":"2026-07-21T10:00:00Z"}""",
        ).amount
        assertEquals(-17, amount("-17.00"))
        assertEquals(-12, amount("-12.4"))
        assertEquals(13, amount("12.7"))
        assertEquals(0, amount("0.0"))
    }

    @Test
    fun `a job stats row missing the accumulator still decodes`() {
        // Exactly what an un-migrated server returns: no accrued_acorn_seconds.
        val s = json.decodeFromString<JobStatsDto>(
            """{"job_id":"j","child_id":"c","title":"t","hourly_rate":37.5,
                "status":"running","credited_amount":123.90,"earned_total":124.5,
                "snapshot_at":"2026-07-21T10:00:00Z"}""",
        )
        assertEquals(38, s.hourlyRate)
        assertEquals(124, s.creditedAmount)
        assertEquals(0L, s.accruedAcornSeconds)
    }

    @Test
    fun `the uncredited tail is never negative`() {
        // A stale snapshot (no accumulator, non-zero credited) must not subtract
        // from the balance — it clamps to zero instead.
        val stat = json.decodeFromString<JobStatsDto>(
            """{"job_id":"j","child_id":"c","title":"t","hourly_rate":40,
                "status":"running","credited_amount":500,"earned_total":500,
                "snapshot_at":"2026-07-21T10:00:00Z"}""",
        )
        val tail = (liveAcorns(stat.accruedAcornSeconds, 0, stat.hourlyRate) - stat.creditedAmount)
            .coerceAtLeast(0)
        assertEquals(0, tail)
    }

    @Test
    fun `live acorns floor the exact accumulator, never rounding up`() {
        assertEquals(30, liveAcorns(1800L * 60, 0, 60))
        assertEquals(0, liveAcorns(1800L * 1, 0, 1))
        assertEquals(49, liveAcorns(0, 1799, 100))
        assertEquals(50, liveAcorns(0, 1800, 100))
        assertEquals(1, liveAcorns(1800L, 1800, 1))
    }
}
