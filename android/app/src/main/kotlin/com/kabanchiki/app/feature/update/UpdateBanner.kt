package com.kabanchiki.app.feature.update

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.expandVertically
import androidx.compose.animation.fadeIn
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.collectAsState
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.kabanchiki.app.R
import com.kabanchiki.app.core.data.UpdateRepository
import com.kabanchiki.app.core.designsystem.KButton
import com.kabanchiki.app.core.designsystem.KButtonVariant
import com.kabanchiki.app.core.designsystem.KabColors
import com.kabanchiki.app.core.model.AppReleaseDto
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.launch
import javax.inject.Inject

@HiltViewModel
class UpdateViewModel @Inject constructor(
    private val repository: UpdateRepository,
) : ViewModel() {
    val available = repository.available
    val downloading = repository.downloading

    fun check() = viewModelScope.launch { repository.check() }
    fun install(release: AppReleaseDto) = repository.downloadAndInstall(release)
}

@Composable
fun UpdateBanner(modifier: Modifier = Modifier, viewModel: UpdateViewModel = hiltViewModel()) {
    val release by viewModel.available.collectAsState()
    val downloading by viewModel.downloading.collectAsState()

    LaunchedEffect(Unit) { viewModel.check() }

    AnimatedVisibility(
        visible = release != null,
        enter = fadeIn() + expandVertically(),
    ) {
        val r = release ?: return@AnimatedVisibility
        Row(
            modifier = modifier
                .fillMaxWidth()
                .clip(RoundedCornerShape(16.dp))
                .background(KabColors.accent)
                .padding(14.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text("🎉", fontSize = 22.sp)
            Spacer(Modifier.width(12.dp))
            Column(Modifier.weight(1f)) {
                Text(
                    stringResource(R.string.update_available_title, r.versionName),
                    color = Color.White,
                    fontWeight = FontWeight.Bold,
                    style = MaterialTheme.typography.titleMedium,
                )
                if (r.notes.isNotBlank()) {
                    Text(
                        r.notes,
                        color = Color.White.copy(alpha = 0.85f),
                        style = MaterialTheme.typography.bodySmall,
                        maxLines = 2,
                    )
                }
            }
            Spacer(Modifier.width(10.dp))
            KButton(
                text = stringResource(
                    if (downloading) R.string.update_downloading else R.string.update_action,
                ),
                onClick = { viewModel.install(r) },
                variant = KButtonVariant.Secondary,
                enabled = !downloading,
                compact = true,
            )
        }
    }
}
