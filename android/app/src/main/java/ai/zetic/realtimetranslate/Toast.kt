package ai.zetic.realtimetranslate

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.Stable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import kotlinx.coroutines.delay

/**
 * The app's one confirmation surface: a short non-interactive line that fades out on its own.
 *
 * A `Toast` rather than a `Snackbar`, in behavior if not in class: a Snackbar owes the user an
 * action and a dismiss affordance, and these confirmations have neither. Drawn in Compose rather
 * than handed to `android.widget.Toast` so it carries the design tokens the spec names and so it
 * can be anchored where the spec anchors it, which the platform toast cannot be.
 */
@Stable
class ToastState {
    var message by mutableStateOf<String?>(null)
        private set

    /**
     * Bumped on every show so a second confirmation restarts the fade instead of inheriting the
     * first one's remaining time, which would leave a repeated copy on screen for a blink.
     */
    internal var token by mutableIntStateOf(0)
        private set

    fun show(text: String) {
        message = text
        token += 1
    }

    internal fun clear() {
        message = null
    }
}

@Composable
fun rememberToastState(): ToastState = remember { ToastState() }

const val ToastDurationMillis = 2_000L

/**
 * Renders [state] where the caller places it. The message is an assertive live region, so it is
 * announced as well as shown: the confirmation is never visual only.
 */
@Composable
fun ToastHost(state: ToastState, modifier: Modifier = Modifier) {
    val message = state.message
    LaunchedEffect(state.token) {
        if (state.message != null) {
            delay(ToastDurationMillis)
            state.clear()
        }
    }
    AnimatedVisibility(visible = message != null, enter = fadeIn(), exit = fadeOut(), modifier = modifier) {
        Text(
            message.orEmpty(),
            color = Surface,
            fontSize = 14.sp,
            textAlign = TextAlign.Center,
            modifier = Modifier
                .padding(16.dp)
                .clip(ControlShape)
                .background(TextPrimary)
                .padding(horizontal = 16.dp, vertical = 10.dp)
                .semantics { liveRegion = LiveRegionMode.Assertive },
        )
    }
}
