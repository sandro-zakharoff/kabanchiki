package com.kabanchiki.app.core.designsystem

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Shapes
import androidx.compose.material3.Typography
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.SideEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

/**
 * Kabanchiki design system: the brand iOS look shared with Windows and the Mini
 * App, in light and dark. Palettes are held in a mutableStateOf so that reading
 * KabColors.* inside a composable subscribes to theme changes — the whole app
 * recomposes when KabanchikiTheme swaps the palette, with no call-site churn.
 */
data class KabPalette(
    val bg: Color,
    val surface: Color,
    val surfaceAlt: Color,
    val surfacePressed: Color,
    val border: Color,
    val textPrimary: Color,
    val textSecondary: Color,
    val accent: Color,
    val accentSoft: Color,
    val accentDark: Color,
    val danger: Color,
    val warning: Color,
    val success: Color,
    val info: Color,
    val isDark: Boolean,
)

private val LightPalette = KabPalette(
    bg = Color(0xFFF7F3F1),
    surface = Color(0xFFFFFFFF),
    surfaceAlt = Color(0xFFF1ECEA),
    surfacePressed = Color(0xFFE7E0DE),
    border = Color(0xFFE4DCD9),
    textPrimary = Color(0xFF38333B),
    textSecondary = Color(0xFFA29AA5),
    accent = Color(0xFF766D78),
    accentSoft = Color(0xFFCDB1B1),
    accentDark = Color(0xFF4A434E),
    danger = Color(0xFFC96A5F),
    warning = Color(0xFFD99A5B),
    success = Color(0xFF6FA287),
    info = Color(0xFF8598B5),
    isDark = false,
)

// Dark palette mirrors the Mini App's dark scheme; brand accents stay recognizable.
private val DarkPalette = KabPalette(
    bg = Color(0xFF17161A),
    surface = Color(0xFF232228),
    surfaceAlt = Color(0xFF2C2A32),
    surfacePressed = Color(0xFF3A3742),
    border = Color(0xFF38343D),
    textPrimary = Color(0xFFF3F0F2),
    textSecondary = Color(0xFF9C93A0),
    accent = Color(0xFF9C8FA0),
    accentSoft = Color(0xFF7C6E74),
    accentDark = Color(0xFFB8A9BC),
    danger = Color(0xFFD98A80),
    warning = Color(0xFFE0AE73),
    success = Color(0xFF86B79E),
    info = Color(0xFF9AAECB),
    isDark = true,
)

/** Static-looking accessor; each getter reads the current palette reactively. */
object KabColors {
    var palette by mutableStateOf(LightPalette)
        internal set

    val bg get() = palette.bg
    val surface get() = palette.surface
    val surfaceAlt get() = palette.surfaceAlt
    val surfacePressed get() = palette.surfacePressed
    val border get() = palette.border
    val textPrimary get() = palette.textPrimary
    val textSecondary get() = palette.textSecondary
    val accent get() = palette.accent
    val accentSoft get() = palette.accentSoft
    val accentDark get() = palette.accentDark
    val danger get() = palette.danger
    val warning get() = palette.warning
    val success get() = palette.success
    val info get() = palette.info

    // Difficulty ramp reads well on both schemes; kept scheme-independent.
    val difficulty = listOf(
        Color(0xFF6FA287),
        Color(0xFF8598B5),
        Color(0xFFD99A5B),
        Color(0xFFCE8158),
        Color(0xFFC96A5F),
    )
}

private fun schemeOf(p: KabPalette) =
    (if (p.isDark) darkColorScheme() else lightColorScheme()).copy(
        primary = p.accent,
        onPrimary = Color.White,
        background = p.bg,
        onBackground = p.textPrimary,
        surface = p.surface,
        onSurface = p.textPrimary,
        surfaceVariant = p.surfaceAlt,
        onSurfaceVariant = p.textSecondary,
        outline = p.border,
        error = p.danger,
    )

private fun typography(p: KabPalette) = Typography(
    headlineLarge = TextStyle(fontSize = 28.sp, fontWeight = FontWeight.Bold, color = p.textPrimary),
    headlineMedium = TextStyle(fontSize = 22.sp, fontWeight = FontWeight.Bold, color = p.textPrimary),
    titleLarge = TextStyle(fontSize = 17.sp, fontWeight = FontWeight.Bold, color = p.textPrimary),
    titleMedium = TextStyle(fontSize = 14.sp, fontWeight = FontWeight.SemiBold, color = p.textPrimary),
    bodyLarge = TextStyle(fontSize = 16.sp, color = p.textPrimary),
    bodyMedium = TextStyle(fontSize = 14.sp, color = p.textPrimary),
    bodySmall = TextStyle(fontSize = 12.sp, color = p.textSecondary),
    labelLarge = TextStyle(fontSize = 14.sp, fontWeight = FontWeight.SemiBold),
    labelMedium = TextStyle(fontSize = 12.sp, fontWeight = FontWeight.SemiBold),
    labelSmall = TextStyle(fontSize = 11.sp, fontWeight = FontWeight.Medium, color = p.textSecondary),
)

private val KabShapes = Shapes(
    small = RoundedCornerShape(10.dp),
    medium = RoundedCornerShape(16.dp),
    large = RoundedCornerShape(22.dp),
)

@Composable
fun KabanchikiTheme(
    darkTheme: Boolean = isSystemInDarkTheme(),
    content: @Composable () -> Unit,
) {
    val palette = if (darkTheme) DarkPalette else LightPalette
    SideEffect { KabColors.palette = palette }
    MaterialTheme(
        colorScheme = schemeOf(palette),
        typography = typography(palette),
        shapes = KabShapes,
        content = content,
    )
}
