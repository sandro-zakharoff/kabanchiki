package com.kabanchiki.app.core.designsystem

import android.content.Context
import androidx.compose.foundation.Image
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ColorFilter
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.res.pluralStringResource
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.TextUnit
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.kabanchiki.app.R
import com.kabanchiki.app.core.model.formatAcorns
import kotlin.math.abs

/**
 * An amount of acorns: the number, then the acorn mark.
 *
 * The acorn replaced the ₴ symbol, and a mark that is an image cannot be glued
 * onto the end of a formatted string the way a character could — it has to be
 * laid out beside the number so it lands on the same optical line at every text
 * size. So every screen shows money through this one composable, matching
 * AcornAmount.qml on the desktop.
 *
 * The mark keeps its own colour by default: it is the currency's identity, and
 * its two-tone cap is what keeps it readable as an acorn down to the smallest
 * label sizes, which a flat silhouette does not survive. `tint` is for dark
 * fills only, where the brown would disappear.
 */
@Composable
fun KAcorns(
    amount: Int,
    modifier: Modifier = Modifier,
    fontSize: TextUnit = 15.sp,
    fontWeight: FontWeight = FontWeight.SemiBold,
    color: Color = KabColors.textPrimary,
    fontFamily: FontFamily? = null,
    tint: Color? = null,
    signed: Boolean = false,
    suffix: String? = null,
) {
    val text = (if (signed && amount >= 0) "+" else "") + formatAcorns(amount)
    // Sized off the digits rather than the full line box, so the mark matches
    // the numerals instead of towering over them.
    val markSize = (fontSize.value * 1.06f).dp
    Row(modifier = modifier, verticalAlignment = Alignment.CenterVertically) {
        Text(
            text,
            fontSize = fontSize,
            fontWeight = fontWeight,
            fontFamily = fontFamily,
            color = color,
            maxLines = 1,
        )
        Spacer(Modifier.width((fontSize.value * 0.3f).dp))
        Image(
            painter = painterResource(R.drawable.ic_acorn),
            contentDescription = null,
            modifier = Modifier.size(markSize),
            colorFilter = tint?.let { ColorFilter.tint(it) },
        )
        if (!suffix.isNullOrEmpty()) {
            Spacer(Modifier.width((fontSize.value * 0.2f).dp))
            Text(suffix, fontSize = fontSize, color = color, maxLines = 1)
        }
    }
}

/**
 * "5 жолудів" — the declined word, for places that cannot draw an icon:
 * notifications, dialog prose, anything that goes into a sentence.
 *
 * Declension is left to the platform's plural rules (values/values-uk), which
 * already know that Ukrainian needs one/few/many and that 11-14 take the 'many'
 * form. The count is passed twice: once to pick the form, once as the grouped
 * number that fills %s.
 */
@Composable
fun acornWords(amount: Int): String =
    // abs() for the form: a debit of -3 declines like 3, and Android's plural
    // rules are not defined for negative counts.
    pluralStringResource(R.plurals.acorns, abs(amount), formatAcorns(amount))

/** The same word, for the services that build notifications outside Compose. */
fun acornWords(context: Context, amount: Int): String =
    context.resources.getQuantityString(R.plurals.acorns, abs(amount), formatAcorns(amount))
