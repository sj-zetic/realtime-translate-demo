package ai.zetic.realtimetranslate

import android.os.Build
import android.view.HapticFeedbackConstants
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * The session-comfort decisions, state by state and event by event. The window flag, the vibrator,
 * and the clipboard themselves are only verifiable on a device; everything that decides when to
 * reach for them is here.
 */
class SessionComfortTest {

    // region Keep the screen awake

    @Test fun `the screen is held awake in exactly the states where push-to-talk is on screen`() {
        val live = listOf(
            SessionPhase.Ready, SessionPhase.ListeningA, SessionPhase.ListeningB,
            SessionPhase.FinalizingA, SessionPhase.FinalizingB,
            SessionPhase.TranslatingA, SessionPhase.TranslatingB, SessionPhase.Error,
        )

        live.forEach { phase ->
            assertTrue(
                "$phase should hold the screen awake",
                ScreenAwakePolicy.shouldKeepAwake(state(phase, conversationStarted = true), isForeground = true),
            )
        }
    }

    @Test fun `setup, permission, and model loading use the platform's normal idle behavior`() {
        // The idle main screen is Ready with no session started, so it is not a live session.
        assertFalse(ScreenAwakePolicy.shouldKeepAwake(state(SessionPhase.Ready, conversationStarted = false), true))
        assertFalse(ScreenAwakePolicy.shouldKeepAwake(state(SessionPhase.PermissionRequired, false), true))
        assertFalse(ScreenAwakePolicy.shouldKeepAwake(state(SessionPhase.LoadingModel, false), true))
        assertFalse(ScreenAwakePolicy.shouldKeepAwake(state(SessionPhase.ModelLoadFailed, false), true))
    }

    @Test fun `a long model download does not hold the screen awake`() {
        assertFalse(ScreenAwakePolicy.shouldKeepAwake(state(SessionPhase.LoadingModel, conversationStarted = true), true))
    }

    @Test fun `backgrounding releases the hold whatever the session state is`() {
        val live = state(SessionPhase.ListeningA, conversationStarted = true)

        assertTrue(ScreenAwakePolicy.shouldKeepAwake(live, isForeground = true))
        assertFalse(ScreenAwakePolicy.shouldKeepAwake(live, isForeground = false))
    }

    // endregion

    // region Haptics

    @Test fun `the haptic vocabulary is four events and nothing else`() {
        assertEquals(HapticPattern.Firm, HapticEvent.TurnBegan.pattern)
        assertEquals(HapticPattern.Light, HapticEvent.TurnEnded.pattern)
        assertEquals(HapticPattern.Soft, HapticEvent.TranslationDelivered.pattern)
        assertEquals(HapticPattern.Error, HapticEvent.SessionError.pattern)
        assertEquals(4, HapticEvent.entries.size)
    }

    @Test fun `each pattern maps to the platform constant that respects the phone's haptic settings`() {
        val sdk = Build.VERSION_CODES.R

        assertEquals(HapticFeedbackConstants.LONG_PRESS, AndroidHaptics.constantFor(HapticEvent.TurnBegan, sdk))
        assertEquals(HapticFeedbackConstants.KEYBOARD_TAP, AndroidHaptics.constantFor(HapticEvent.TurnEnded, sdk))
        assertEquals(HapticFeedbackConstants.CLOCK_TICK, AndroidHaptics.constantFor(HapticEvent.TranslationDelivered, sdk))
        assertEquals(HapticFeedbackConstants.REJECT, AndroidHaptics.constantFor(HapticEvent.SessionError, sdk))
    }

    @Test fun `the error buzz falls back rather than doing nothing below API 30`() {
        assertEquals(
            HapticFeedbackConstants.LONG_PRESS,
            AndroidHaptics.constantFor(HapticEvent.SessionError, Build.VERSION_CODES.O),
        )
    }

    // endregion

    // region Copy a bubble

    @Test fun `a translated bubble copies its translation`() {
        assertEquals("bonjour", bubble(transcript = "hello", translation = "bonjour").copyableText)
    }

    @Test fun `a bubble with no translation yet copies its source transcript`() {
        assertEquals("hello", bubble(transcript = "hello", translation = null).copyableText)
    }

    @Test fun `a failed translation still copies the source transcript`() {
        assertEquals(
            "hello",
            bubble(transcript = "hello", translation = null).copy(translationError = UiText.raw("Translation failed.")).copyableText,
        )
    }

    @Test fun `a bubble with nothing in it yet offers no copy`() {
        assertNull(bubble(transcript = "", translation = null).copyableText)
        assertNull(bubble(transcript = "   ", translation = null).copyableText)
    }

    @Test fun `an empty translation falls back to the transcript rather than copying nothing`() {
        assertEquals("hello", bubble(transcript = "hello", translation = "").copyableText)
    }

    // endregion

    private fun state(phase: SessionPhase, conversationStarted: Boolean) =
        SessionUiState(phase, conversationStarted = conversationStarted)

    private fun bubble(transcript: String, translation: String?) = ConversationItem(
        id = "bubble",
        speaker = Speaker.A,
        sourceLanguage = SpeechLanguage.Automatic,
        targetLanguage = HyMt2Languages.all.first { it.code == "ko" },
        transcript = transcript,
        isFinal = translation != null,
        translation = translation,
    )
}
