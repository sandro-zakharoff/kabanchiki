package com.kabanchiki.app.core.designsystem

import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.spring
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsPressedAsState
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.scale
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import com.kabanchiki.app.R
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.input.VisualTransformation
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

/** White rounded card with the soft timetrack shadow. */
@Composable
fun KCard(
    modifier: Modifier = Modifier,
    corner: Dp = 16.dp,
    onClick: (() -> Unit)? = null,
    content: @Composable ColumnScope.() -> Unit,
) {
    val interaction = remember { MutableInteractionSource() }
    val pressed by interaction.collectIsPressedAsState()
    val scale by animateFloatAsState(
        targetValue = if (pressed && onClick != null) 0.98f else 1f,
        animationSpec = spring(stiffness = 800f),
        label = "cardScale",
    )
    Column(
        modifier = modifier
            .scale(scale)
            .shadow(elevation = 6.dp, shape = RoundedCornerShape(corner), spotColor = Color(0x33000000))
            .clip(RoundedCornerShape(corner))
            .background(KabColors.surface)
            .border(1.dp, KabColors.border, RoundedCornerShape(corner))
            .then(
                if (onClick != null) {
                    Modifier.clickable(interactionSource = interaction, indication = null, onClick = onClick)
                } else Modifier
            ),
        content = content,
    )
}

enum class KButtonVariant { Primary, Secondary, Danger, Ghost }

/**
 * iOS-flavored button: soft vertical gradient for filled variants, gentle
 * press-scale, no ripple. Filled buttons cast a tinted shadow.
 */
@Composable
fun KButton(
    text: String,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    variant: KButtonVariant = KButtonVariant.Primary,
    enabled: Boolean = true,
    compact: Boolean = false,
) {
    val interaction = remember { MutableInteractionSource() }
    val pressed by interaction.collectIsPressedAsState()
    val scale by animateFloatAsState(
        targetValue = if (pressed) 0.965f else 1f,
        animationSpec = spring(stiffness = 700f),
        label = "btnScale",
    )
    val pressOverlay by animateFloatAsState(
        targetValue = if (pressed) 0.16f else 0f,
        animationSpec = tween(140),
        label = "btnPress",
    )

    val shape = RoundedCornerShape(if (compact) 13.dp else 16.dp)
    val filled = variant == KButtonVariant.Primary || variant == KButtonVariant.Danger
    val gradient = when (variant) {
        KButtonVariant.Primary -> Brush.verticalGradient(
            listOf(Color(0xFF8A8090), Color(0xFF6B6270)),
        )
        KButtonVariant.Danger -> Brush.verticalGradient(
            listOf(Color(0xFFD57F73), Color(0xFFBC5D51)),
        )
        else -> null
    }
    val flatColor = when {
        !enabled -> KabColors.surfaceAlt
        variant == KButtonVariant.Secondary -> KabColors.surface
        else -> Color.Transparent
    }
    val fg = when {
        !enabled -> KabColors.textSecondary
        filled -> Color.White
        else -> KabColors.textPrimary
    }

    Box(
        contentAlignment = Alignment.Center,
        modifier = modifier
            .scale(scale)
            .then(
                if (filled && enabled) {
                    Modifier.shadow(
                        elevation = 8.dp,
                        shape = shape,
                        spotColor = KabColors.accent.copy(alpha = 0.55f),
                        ambientColor = KabColors.accent.copy(alpha = 0.25f),
                    )
                } else Modifier
            )
            .clip(shape)
            .then(
                if (filled && enabled && gradient != null) {
                    Modifier.background(gradient)
                } else Modifier.background(flatColor)
            )
            .background(
                // A dark overlay vanishes on dark surfaces — tint by scheme.
                (if (KabColors.palette.isDark) Color.White else Color.Black).copy(alpha = pressOverlay),
            )
            .then(
                if (variant == KButtonVariant.Secondary && enabled) {
                    Modifier.border(1.dp, KabColors.border, shape)
                } else Modifier
            )
            .clickable(
                interactionSource = interaction,
                indication = null,
                enabled = enabled,
                onClick = onClick,
            )
            .height(if (compact) 42.dp else 52.dp)
            .padding(horizontal = if (compact) 18.dp else 24.dp),
    ) {
        Text(
            text,
            fontSize = if (compact) 14.sp else 16.sp,
            fontWeight = FontWeight.Bold,
            letterSpacing = 0.2.sp,
            color = fg,
            maxLines = 1,
        )
    }
}

/** Rounded stat tile: small muted label on top, big value below. */
@Composable
fun KStatTile(
    label: String,
    value: String,
    modifier: Modifier = Modifier,
    valueColor: Color = KabColors.textPrimary,
) {
    Column(
        modifier = modifier
            .clip(RoundedCornerShape(16.dp))
            .background(KabColors.surface)
            .border(1.dp, KabColors.border, RoundedCornerShape(16.dp))
            .padding(horizontal = 16.dp, vertical = 14.dp),
    ) {
        Text(
            label.uppercase(),
            fontSize = 11.sp,
            fontWeight = FontWeight.SemiBold,
            letterSpacing = 0.6.sp,
            color = KabColors.textSecondary,
            maxLines = 1,
        )
        Box(Modifier.height(4.dp))
        Text(
            value,
            fontSize = 24.sp,
            fontWeight = FontWeight.Bold,
            color = valueColor,
            maxLines = 1,
        )
    }
}

/** Difficulty as 5 filled segments + a readable label instead of a bare digit. */
@Composable
fun KDifficultyBadge(level: Int, modifier: Modifier = Modifier, showLabel: Boolean = true) {
    val index = (level - 1).coerceIn(0, 4)
    val color = KabColors.difficulty[index]
    val labels = listOf(
        stringResource(R.string.difficulty_1),
        stringResource(R.string.difficulty_2),
        stringResource(R.string.difficulty_3),
        stringResource(R.string.difficulty_4),
        stringResource(R.string.difficulty_5),
    )
    Row(
        modifier = modifier
            .clip(RoundedCornerShape(50))
            .background(color.copy(alpha = 0.13f))
            .padding(horizontal = 10.dp, vertical = 5.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        Row(
            horizontalArrangement = Arrangement.spacedBy(2.dp),
        ) {
            repeat(5) { i ->
                Box(
                    Modifier
                        .size(width = 5.dp, height = 11.dp)
                        .clip(RoundedCornerShape(2.dp))
                        .background(if (i <= index) color else color.copy(alpha = 0.25f)),
                )
            }
        }
        if (showLabel) {
            Text(
                labels[index],
                fontSize = 11.sp,
                fontWeight = FontWeight.SemiBold,
                color = color,
            )
        }
    }
}

@Composable
fun KTextField(
    value: String,
    onValueChange: (String) -> Unit,
    modifier: Modifier = Modifier,
    placeholder: String = "",
    isPassword: Boolean = false,
    singleLine: Boolean = true,
    minLines: Int = 1,
    keyboardOptions: KeyboardOptions = KeyboardOptions.Default,
) {
    OutlinedTextField(
        value = value,
        onValueChange = onValueChange,
        modifier = modifier.fillMaxWidth(),
        placeholder = { Text(placeholder, color = KabColors.textSecondary) },
        singleLine = singleLine,
        minLines = minLines,
        keyboardOptions = keyboardOptions,
        visualTransformation = if (isPassword) PasswordVisualTransformation() else VisualTransformation.None,
        shape = RoundedCornerShape(10.dp),
        colors = OutlinedTextFieldDefaults.colors(
            focusedBorderColor = KabColors.accent,
            unfocusedBorderColor = KabColors.border,
            focusedContainerColor = KabColors.surfaceAlt,
            unfocusedContainerColor = KabColors.surfaceAlt,
            cursorColor = KabColors.accent,
        ),
    )
}

/** Small colored status/reward chip. */
@Composable
fun KChip(
    text: String,
    color: Color,
    modifier: Modifier = Modifier,
    filled: Boolean = false,
) {
    val bg by animateColorAsState(
        targetValue = if (filled) color else color.copy(alpha = 0.14f),
        animationSpec = tween(150),
        label = "chipBg",
    )
    Box(
        modifier = modifier
            .clip(RoundedCornerShape(50))
            .background(bg)
            .padding(horizontal = 10.dp, vertical = 4.dp),
        contentAlignment = Alignment.Center,
    ) {
        Text(
            text,
            fontSize = 11.sp,
            fontWeight = FontWeight.SemiBold,
            color = if (filled) Color.White else color,
        )
    }
}

/** Avatar: the photo when one is set, initials on the brand color otherwise. */
@Composable
fun KAvatar(name: String, color: Color, size: Dp = 36.dp, photoUrl: String? = null) {
    Box(
        modifier = Modifier
            .size(size)
            .clip(CircleShape)
            .background(color),
        contentAlignment = Alignment.Center,
    ) {
        Text(
            text = name.firstOrNull()?.uppercase() ?: "?",
            color = Color.White,
            fontWeight = FontWeight.Bold,
            fontSize = (size.value * 0.42f).sp,
        )
        if (!photoUrl.isNullOrBlank()) {
            coil.compose.AsyncImage(
                model = photoUrl,
                contentDescription = null,
                contentScale = androidx.compose.ui.layout.ContentScale.Crop,
                modifier = Modifier.size(size).clip(CircleShape),
            )
        }
    }
}
