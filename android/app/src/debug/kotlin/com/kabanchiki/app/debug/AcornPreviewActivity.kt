package com.kabanchiki.app.debug

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.kabanchiki.app.core.designsystem.KAcorns
import com.kabanchiki.app.core.designsystem.KChip
import com.kabanchiki.app.core.designsystem.KStatTile
import com.kabanchiki.app.core.designsystem.KabColors
import com.kabanchiki.app.core.designsystem.KabanchikiTheme
import com.kabanchiki.app.core.designsystem.acornWords

/**
 * Debug-only gallery of the acorn mark at the sizes the app actually uses, so
 * its alignment and tinting can be eyeballed on a real device without needing a
 * signed-in account. Debug source set only — never part of a release build.
 */
class AcornPreviewActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContent { KabanchikiTheme { Gallery() } }
    }
}

@Composable
private fun Gallery() {
    Column(
        Modifier.fillMaxSize().background(KabColors.bg).padding(20.dp),
        verticalArrangement = Arrangement.spacedBy(14.dp),
    ) {
        Caption("Sizes")
        Row(horizontalArrangement = Arrangement.spacedBy(18.dp)) {
            KAcorns(amount = 8, fontSize = 12.sp)
            KAcorns(amount = 142, fontSize = 15.sp)
            KAcorns(amount = 1234, fontSize = 20.sp)
            KAcorns(amount = 883, fontSize = 26.sp, fontWeight = FontWeight.Bold)
        }

        Caption("Hero balance")
        KAcorns(amount = 1234567, fontSize = 40.sp, fontWeight = FontWeight.Bold, color = KabColors.accent)

        Caption("Ledger rows")
        Row(horizontalArrangement = Arrangement.spacedBy(18.dp)) {
            KAcorns(amount = 50, signed = true, fontWeight = FontWeight.Bold, color = KabColors.success)
            KAcorns(amount = -120, fontWeight = FontWeight.Bold, color = KabColors.danger)
            KAcorns(amount = 60, suffix = "/ год", fontSize = 13.sp,
                fontWeight = FontWeight.Normal, color = KabColors.textSecondary)
        }

        Caption("Chips")
        Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            KChip(text = "", acorns = 25, color = KabColors.accentDark)
            KChip(text = "", acorns = 60, suffix = "/ год", color = KabColors.accentDark)
            KChip(text = "", acorns = 100, filled = true, color = KabColors.accent)
            KChip(text = "без таймера", color = KabColors.info)
        }

        Caption("Stat tile")
        Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            KStatTile(label = "Зароблено", value = "", acorns = 348, valueColor = KabColors.success)
            KStatTile(label = "Час", value = "3:24:07")
        }

        Caption("Declension (plural resources)")
        Column {
            listOf(1, 2, 4, 5, 11, 12, 21, 22, 25, 883, 1234).forEach {
                Text(acornWords(it), fontSize = 13.sp, color = KabColors.textPrimary)
            }
        }
    }
}

@Composable
private fun Caption(text: String) =
    Text(text, fontSize = 11.sp, color = KabColors.textSecondary)
