package ai.zetic.realtimetranslate

import android.os.Build
import android.view.HapticFeedbackConstants

/**
 * The three session-comfort behaviors, and more importantly the decisions behind them.
 *
 * None of the effects here can be asserted in a JVM unit test: the window flag, the vibrator, and
 * the system clipboard all live outside the process the tests can observe. So each behavior is
 * split in two. The decision is a pure function, and the Android call is the thin shell around it
 * in [TurnTranslateRoot]. The tests exercise the decisions; the shell is verified on a device.
 */

// region Keep the screen awake

/**
 * The states where push-to-talk is on screen, which is exactly where the display must stay lit:
 * both speakers read the same phone and a turn can be seconds of silence while someone thinks.
 *
 * `conversationStarted` is the Android form of "the model is loaded and the conversation screen is
 * in use". The idle main screen is `Ready` with the flag false, so it is not a live session and
 * uses the platform's normal idle behavior, and neither does a model download.
 */
private val LiveSessionPhases = setOf(
    SessionPhase.Ready,
    SessionPhase.ListeningA,
    SessionPhase.ListeningB,
    SessionPhase.FinalizingA,
    SessionPhase.FinalizingB,
    SessionPhase.TranslatingA,
    SessionPhase.TranslatingB,
    SessionPhase.Error,
)

val SessionUiState.isSessionLive: Boolean
    get() = conversationStarted && phase in LiveSessionPhases

object ScreenAwakePolicy {
    /**
     * A backgrounded activity never holds the screen awake, whatever the session state is: the
     * screen the user is actually looking at belongs to some other app by then.
     */
    fun shouldKeepAwake(state: SessionUiState, isForeground: Boolean): Boolean =
        isForeground && state.isSessionLive
}

// endregion

// region Haptics

/**
 * What happened, not what it feels like. The session emits these; the mapping to a physical
 * sensation is a separate, testable table.
 */
enum class HapticEvent {
    /** A push-to-talk control was pressed and recording started. */
    TurnBegan,

    /** A push-to-talk control was released and the utterance is finalizing. */
    TurnEnded,

    /** A finalized transcript came back as a translation. */
    TranslationDelivered,

    /** A session error banner appeared. */
    SessionError,
}

/**
 * How an event feels. Deliberately quiet: one firm tap to say recording started, lighter taps for
 * the two things that end on their own, and a rejection buzz for the one failure that takes over
 * the screen. A failed translation stays silent, because the bubble already says so.
 */
enum class HapticPattern { Firm, Light, Soft, Error }

val HapticEvent.pattern: HapticPattern
    get() = when (this) {
        HapticEvent.TurnBegan -> HapticPattern.Firm
        HapticEvent.TurnEnded -> HapticPattern.Light
        HapticEvent.TranslationDelivered -> HapticPattern.Soft
        HapticEvent.SessionError -> HapticPattern.Error
    }

/**
 * The pattern rendered as a `View.performHapticFeedback` constant, so the phone's own haptic
 * strength and the user's system-wide haptics setting are respected instead of driving the
 * vibrator directly.
 *
 * `REJECT` only exists from API 30, and this app runs from API 26, so the error buzz falls back to
 * the firm tap rather than silently doing nothing. The SDK level is a parameter rather than a read
 * of [Build.VERSION.SDK_INT] so the fallback itself is unit tested.
 */
object AndroidHaptics {
    fun constantFor(pattern: HapticPattern, sdkInt: Int = Build.VERSION.SDK_INT): Int = when (pattern) {
        HapticPattern.Firm -> HapticFeedbackConstants.LONG_PRESS
        HapticPattern.Light -> HapticFeedbackConstants.KEYBOARD_TAP
        HapticPattern.Soft -> HapticFeedbackConstants.CLOCK_TICK
        HapticPattern.Error ->
            if (sdkInt >= Build.VERSION_CODES.R) HapticFeedbackConstants.REJECT else HapticFeedbackConstants.LONG_PRESS
    }

    fun constantFor(event: HapticEvent, sdkInt: Int = Build.VERSION.SDK_INT): Int =
        constantFor(event.pattern, sdkInt)
}

// endregion

// region Copy a bubble

/**
 * What a copy takes from this bubble: the translation once there is one, and the source transcript
 * until then. A bubble still waiting for its first words has nothing to copy, so it offers no
 * action rather than putting an empty string on the clipboard.
 */
val ConversationItem.copyableText: String?
    get() = (translation?.takeIf { it.isNotBlank() } ?: transcript).takeIf { it.isNotBlank() }

// endregion
