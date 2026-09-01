package ai.zetic.realtimetranslate

import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color

/** ZETIC minimal design tokens. White surfaces, near-black text, one teal accent. */
val Accent = Color(0xFF2DBDB2)
val Surface = Color.White
val SurfaceSubtle = Color(0xFFF0F0F0)
val DividerLine = Color(0xFFE8E8E8)
val TextPrimary = Color(0xFF0A0A0A)
val TextSecondary = Color(0xFF6B6B6B)
val Error = Color(0xFFC92A2A)

@Composable
fun RealtimeTranslateTheme(content: @Composable () -> Unit) {
    MaterialTheme(
        colorScheme = lightColorScheme(
            primary = Accent,
            onPrimary = Surface,
            secondary = Accent,
            onSecondary = Surface,
            background = Surface,
            onBackground = TextPrimary,
            surface = Surface,
            onSurface = TextPrimary,
            surfaceVariant = SurfaceSubtle,
            onSurfaceVariant = TextSecondary,
            outline = DividerLine,
            error = Error,
        ),
        content = content,
    )
}
