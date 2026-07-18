package com.kabanchiki.app.feature.profile

import android.net.Uri
import androidx.compose.foundation.background
import androidx.compose.foundation.gestures.detectTransformGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.dp
import coil.compose.AsyncImage
import com.kabanchiki.app.R
import com.kabanchiki.app.core.designsystem.KButton
import com.kabanchiki.app.core.designsystem.KButtonVariant
import com.kabanchiki.app.core.designsystem.KabColors
import com.kabanchiki.app.core.images.ImageOptimizer
import kotlin.math.max
import kotlin.math.min

/**
 * Pan + pinch-zoom circular crop; emits the square crop rect in upright
 * source pixels — ImageOptimizer applies the same orientation fix before
 * cutting, so the math matches the desktop's crop dialog.
 */
@Composable
fun AvatarCropDialog(
    uri: Uri,
    onDismiss: () -> Unit,
    onDone: (FloatArray) -> Unit, // [x, y, size]
) {
    val context = LocalContext.current
    val frameDp = 260.dp
    val framePx = with(LocalDensity.current) { frameDp.toPx() }

    var srcW by remember { mutableFloatStateOf(0f) }
    var srcH by remember { mutableFloatStateOf(0f) }
    var zoom by remember { mutableFloatStateOf(1f) }
    var panX by remember { mutableFloatStateOf(0f) }
    var panY by remember { mutableFloatStateOf(0f) }
    var ready by remember { mutableStateOf(false) }

    LaunchedEffect(uri) {
        val (w, h) = ImageOptimizer.imageSize(context, uri)
        srcW = w.toFloat(); srcH = h.toFloat()
        ready = w > 0 && h > 0
    }

    // cover-fit base scale × user zoom
    val scaleK = if (ready) max(framePx / srcW, framePx / srcH) * zoom else 1f

    fun clampPan() {
        val maxX = max(0f, (srcW * scaleK - framePx) / 2f)
        val maxY = max(0f, (srcH * scaleK - framePx) / 2f)
        panX = panX.coerceIn(-maxX, maxX)
        panY = panY.coerceIn(-maxY, maxY)
    }

    AlertDialog(
        onDismissRequest = onDismiss,
        containerColor = KabColors.surface,
        title = { Text(stringResource(R.string.avatar_crop_title), style = MaterialTheme.typography.titleLarge) },
        text = {
            Column(
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(10.dp),
                modifier = Modifier.fillMaxWidth(),
            ) {
                Box(
                    Modifier
                        .size(frameDp)
                        .clip(CircleShape)
                        .background(KabColors.surfaceAlt)
                        .pointerInput(ready) {
                            detectTransformGestures { _, pan, gestureZoom, _ ->
                                zoom = (zoom * gestureZoom).coerceIn(1f, 4f)
                                panX += pan.x
                                panY += pan.y
                                clampPan()
                            }
                        },
                    contentAlignment = Alignment.Center,
                ) {
                    if (ready) {
                        AsyncImage(
                            model = uri,
                            contentDescription = null,
                            contentScale = ContentScale.Crop,
                            modifier = Modifier
                                .size(frameDp)
                                .graphicsLayer {
                                    scaleX = zoom
                                    scaleY = zoom
                                    translationX = panX
                                    translationY = panY
                                },
                        )
                    }
                }
                Text(
                    stringResource(R.string.avatar_crop_hint),
                    style = MaterialTheme.typography.labelSmall,
                    color = KabColors.textSecondary,
                )
            }
        },
        confirmButton = {
            KButton(
                text = stringResource(R.string.common_done),
                enabled = ready,
                onClick = {
                    // ContentScale.Crop centers the cover-fit image; translation
                    // is in frame px on top of that, ×zoom via graphicsLayer.
                    val size = framePx / scaleK
                    val x = (srcW - size) / 2f - panX / scaleK
                    val y = (srcH - size) / 2f - panY / scaleK
                    onDone(
                        floatArrayOf(
                            x.coerceIn(0f, max(0f, srcW - size)),
                            y.coerceIn(0f, max(0f, srcH - size)),
                            min(size, min(srcW, srcH)),
                        ),
                    )
                },
            )
        },
        dismissButton = {
            KButton(
                text = stringResource(R.string.common_cancel),
                onClick = onDismiss,
                variant = KButtonVariant.Ghost,
            )
        },
    )
}
