package com.kabanchiki.app.feature.profile

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.KeyboardArrowRight
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.RadioButton
import androidx.compose.material3.RadioButtonDefaults
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.kabanchiki.app.R
import com.kabanchiki.app.core.designsystem.KButton
import com.kabanchiki.app.core.designsystem.KButtonVariant
import com.kabanchiki.app.core.designsystem.KCard
import com.kabanchiki.app.core.designsystem.KabColors
import com.kabanchiki.app.core.push.NotificationCategory
import com.kabanchiki.app.core.push.NotificationChannels
import com.kabanchiki.app.core.push.NotificationSound
import com.kabanchiki.app.core.push.NotificationSoundStore
import com.kabanchiki.app.core.push.SoundPreviewPlayer

/**
 * "Notification sounds" settings: one row per category, each opening a picker
 * that previews every sound and saves the choice (recreating the channel).
 */
@Composable
fun NotificationSoundsCard() {
    val context = LocalContext.current
    val store = remember { NotificationSoundStore(context) }
    val preview = remember { SoundPreviewPlayer(context) }
    DisposableEffect(Unit) { onDispose { preview.release() } }

    // Bumped after a save so the rows re-read the freshly chosen sound.
    var revision by remember { mutableIntStateOf(0) }
    var editing by remember { mutableStateOf<NotificationCategory?>(null) }

    KCard(Modifier.fillMaxWidth()) {
        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Text(
                stringResource(R.string.sound_section_title),
                style = MaterialTheme.typography.titleMedium,
            )
            Text(
                stringResource(R.string.sound_section_hint),
                style = MaterialTheme.typography.bodySmall,
                color = KabColors.textSecondary,
            )
            Spacer(Modifier.height(6.dp))
            NotificationCategory.entries.forEachIndexed { index, category ->
                revision // read so a save recomposes the current-sound label
                val current = store.soundFor(category)
                if (index > 0) {
                    Surface(color = KabColors.border, modifier = Modifier.fillMaxWidth().height(1.dp)) {}
                }
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .clickable { editing = category }
                        .padding(vertical = 12.dp),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    Column(Modifier.weight(1f)) {
                        Text(
                            stringResource(category.titleRes),
                            style = MaterialTheme.typography.bodyLarge,
                            fontWeight = FontWeight.Medium,
                        )
                        Text(
                            stringResource(category.descRes),
                            style = MaterialTheme.typography.bodySmall,
                            color = KabColors.textSecondary,
                        )
                    }
                    Text(
                        stringResource(current.labelRes),
                        style = MaterialTheme.typography.bodyMedium,
                        color = KabColors.accent,
                        fontWeight = FontWeight.Medium,
                    )
                    Icon(
                        Icons.Filled.KeyboardArrowRight,
                        contentDescription = null,
                        tint = KabColors.textSecondary,
                    )
                }
            }
        }
    }

    editing?.let { category ->
        SoundPickerSheet(
            category = category,
            initial = store.soundFor(category),
            onPreview = { preview.play(it) },
            onDismiss = {
                preview.release()
                editing = null
            },
            onSave = { sound ->
                NotificationChannels.applySound(context, category, sound)
                preview.release()
                revision++
                editing = null
            },
        )
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun SoundPickerSheet(
    category: NotificationCategory,
    initial: NotificationSound,
    onPreview: (NotificationSound) -> Unit,
    onDismiss: () -> Unit,
    onSave: (NotificationSound) -> Unit,
) {
    var selected by remember { mutableStateOf(initial) }
    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true),
        containerColor = KabColors.bg,
    ) {
        Column(
            Modifier
                .fillMaxWidth()
                .padding(start = 20.dp, end = 20.dp, bottom = 28.dp),
            verticalArrangement = Arrangement.spacedBy(4.dp),
        ) {
            Text(
                stringResource(category.titleRes),
                style = MaterialTheme.typography.titleLarge,
            )
            Text(
                stringResource(R.string.sound_pick_hint),
                style = MaterialTheme.typography.bodySmall,
                color = KabColors.textSecondary,
            )
            Spacer(Modifier.height(8.dp))

            NotificationSound.entries.forEach { sound ->
                val isSelected = sound == selected
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .clip(RoundedCornerShape(14.dp))
                        .background(if (isSelected) KabColors.accentSoft.copy(alpha = 0.25f) else Color.Transparent)
                        .clickable {
                            selected = sound
                            onPreview(sound)
                        }
                        .padding(horizontal = 12.dp, vertical = 10.dp),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(6.dp),
                ) {
                    RadioButton(
                        selected = isSelected,
                        onClick = {
                            selected = sound
                            onPreview(sound)
                        },
                        colors = RadioButtonDefaults.colors(selectedColor = KabColors.accent),
                    )
                    Text(
                        stringResource(sound.labelRes),
                        style = MaterialTheme.typography.bodyLarge,
                        modifier = Modifier.weight(1f),
                    )
                    Icon(
                        Icons.Filled.PlayArrow,
                        contentDescription = stringResource(R.string.sound_preview),
                        tint = KabColors.accent,
                        modifier = Modifier
                            .size(28.dp)
                            .clip(RoundedCornerShape(50))
                            .clickable { onPreview(sound) }
                            .padding(2.dp),
                    )
                }
            }

            Spacer(Modifier.height(16.dp))
            Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                KButton(
                    text = stringResource(R.string.action_cancel),
                    onClick = onDismiss,
                    variant = KButtonVariant.Ghost,
                    modifier = Modifier.weight(1f),
                )
                KButton(
                    text = stringResource(R.string.action_save),
                    onClick = { onSave(selected) },
                    modifier = Modifier.weight(1f),
                )
            }
        }
    }
}
