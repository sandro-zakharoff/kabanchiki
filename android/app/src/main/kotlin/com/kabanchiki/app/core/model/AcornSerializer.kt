package com.kabanchiki.app.core.model

import kotlinx.serialization.KSerializer
import kotlinx.serialization.descriptors.PrimitiveKind
import kotlinx.serialization.descriptors.PrimitiveSerialDescriptor
import kotlinx.serialization.descriptors.SerialDescriptor
import kotlinx.serialization.encoding.Decoder
import kotlinx.serialization.encoding.Encoder
import kotlin.math.roundToInt

/**
 * Acorns are whole numbers, but they arrive over the wire as JSON numbers.
 *
 * Decoding leniently — take whatever number the server sent and round it — is
 * deliberate. A strict `Int` field rejects `953.13`, and kotlinx aborts the
 * WHOLE response on one bad field, so a single unexpected value empties the
 * ledger, the payout list and the balance at once. The screen then shows a
 * confident `0` with no history, which reads as "my money is gone" rather than
 * "the app could not read the server".
 *
 * The integer column type in Postgres is what actually guarantees whole acorns.
 * This is the client being liberal in what it accepts, so that a server briefly
 * out of step with the app degrades to a rounded number instead of a blank.
 */
object AcornSerializer : KSerializer<Int> {
    override val descriptor: SerialDescriptor =
        PrimitiveSerialDescriptor("Acorns", PrimitiveKind.INT)

    override fun serialize(encoder: Encoder, value: Int) = encoder.encodeInt(value)

    override fun deserialize(decoder: Decoder): Int = decoder.decodeDouble().roundToInt()
}
