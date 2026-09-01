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

/**
 * Per-speaker identity families, both derived from the brand system: speaker A is the teal
 * family and speaker B is the ink family. Color is always redundant with the speaker label and
 * the left/right alignment, never the only distinguisher.
 */
val AccentA = Color(0xFF2DBDB2)
val DeepA = Color(0xFF17877D)
val TintA = Color(0xFFE9F7F5)
val BorderA = Color(0xFFBFE7E2)
val AccentB = Color(0xFF0A0A0A)
val DeepB = Color(0xFF0A0A0A)
val TintB = Color(0xFFF0F0F0)
val BorderB = Color(0xFFE8E8E8)

fun speakerAccent(speaker: Speaker) = if (speaker == Speaker.A) AccentA else AccentB
fun speakerDeep(speaker: Speaker) = if (speaker == Speaker.A) DeepA else DeepB
fun speakerTint(speaker: Speaker) = if (speaker == Speaker.A) TintA else TintB
fun speakerBorder(speaker: Speaker) = if (speaker == Speaker.A) BorderA else BorderB

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
