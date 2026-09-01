package ai.zetic.realtimetranslate

import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color

val Primary = Color(0xFF3B5BDB)
val Secondary = Color(0xFF0B7285)
val Surface = Color.White
val SurfaceMuted = Color(0xFFF1F3F5)
val TextPrimary = Color(0xFF1F2937)
val TextSecondary = Color(0xFF6B7280)
val Error = Color(0xFFC92A2A)

@Composable
fun RealtimeTranslateTheme(content: @Composable () -> Unit) {
    MaterialTheme(
        colorScheme = lightColorScheme(primary = Primary, secondary = Secondary, surface = Surface, onSurface = TextPrimary, error = Error),
        content = content,
    )
}
