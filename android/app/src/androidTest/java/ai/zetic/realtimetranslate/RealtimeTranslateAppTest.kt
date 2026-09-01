package ai.zetic.realtimetranslate

import androidx.activity.ComponentActivity
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.assertIsEnabled
import androidx.compose.ui.test.assertIsNotEnabled
import androidx.compose.ui.test.hasScrollAction
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performSemanticsAction
import androidx.compose.ui.test.performTouchInput
import androidx.compose.ui.test.swipeDown
import androidx.compose.ui.test.swipeUp
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.runtime.mutableStateOf
import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class RealtimeTranslateAppTest {
    @get:Rule val composeRule = createAndroidComposeRule<ComponentActivity>()

    @Test fun permanentPermissionDenialOffersAppSettings() {
        var opened = false
        setApp(SessionUiState(SessionPhase.PermissionRequired, permissionPermanentlyDenied = true), onOpenAppSettings = { opened = true })
        composeRule.onNodeWithContentDescription("Open app settings").performClick()
        assertEquals(true, opened)
    }

    @Test fun aListeningDisablesBAndShowsPartialCard() {
        setApp(readyConversationState().copy(phase = SessionPhase.ListeningA, conversations = listOf(item(Speaker.A, "Hello", false))))
        composeRule.onNodeWithText("Hello").assertIsDisplayed()
        composeRule.onNodeWithContentDescription("Stop speaker A").assertIsDisplayed()
        composeRule.onNodeWithContentDescription("Speaker B cannot start while speaker A is active").assertIsNotEnabled()
    }

    @Test fun tapAlternativeDispatchesToggle() {
        var action: UiAction? = null
        setApp(readyConversationState(), onAction = { action = it })
        composeRule.onNodeWithContentDescription("Start speaker A").performSemanticsAction(SemanticsActions.OnClick) { it() }
        assertEquals(UiAction.TogglePtt(Speaker.A), action)
    }

    @Test fun finalBubbleDisplaysSpeakerTargetAndTranslationError() {
        val state = readyConversationState().copy(conversations = listOf(item(Speaker.B, "hello", true).copy(translationError = "Hy-MT2 runtime verification is incomplete.")))
        setApp(state)
        composeRule.onNodeWithText("Speaker B").assertIsDisplayed()
        composeRule.onNodeWithText("To A - English").assertIsDisplayed()
        composeRule.onNodeWithText("Hy-MT2 runtime verification is incomplete.").assertIsDisplayed()
    }

    @Test fun chatBubblesAlignLeftForAAndRightForB() {
        setApp(
            readyConversationState().copy(
                conversations = listOf(
                    item(Speaker.A, "left side", true).copy(id = "a"),
                    item(Speaker.B, "right side", true).copy(id = "b"),
                ),
            ),
        )

        val a = composeRule.onNodeWithContentDescription("Speaker A utterance").fetchSemanticsNode().boundsInRoot
        val b = composeRule.onNodeWithContentDescription("Speaker B utterance").fetchSemanticsNode().boundsInRoot

        assertTrue(a.left < b.left)
        assertTrue(a.right < b.right)
    }

    @Test fun queuedBubbleAnnouncesTranslationPending() {
        setApp(readyConversationState().copy(conversations = listOf(item(Speaker.A, "hello", true))))
        composeRule.onNodeWithText("Translation pending").assertIsDisplayed()
    }

    @Test fun conversationCardsScrollWithoutMovingSessionControls() {
        val cards = (1..6).map { index ->
            item(Speaker.A, "Conversation card $index: " + "long transcript ".repeat(24), true).copy(id = "card-$index")
        }
        setApp(readyConversationState().copy(conversations = cards))

        val history = composeRule.onNode(hasScrollAction())
        repeat(12) { history.performTouchInput { swipeDown() } }
        composeRule.onNodeWithText("Conversation card 1:", substring = true).assertIsDisplayed()
        composeRule.onNodeWithContentDescription("Start speaker A").assertIsDisplayed()
        composeRule.onNodeWithContentDescription("Start speaker B").assertIsDisplayed()
        composeRule.onNodeWithContentDescription("End session").assertIsDisplayed()
        repeat(12) { history.performTouchInput { swipeUp() } }
        composeRule.onNodeWithText("Conversation card 6:", substring = true).assertIsDisplayed()
        composeRule.onNodeWithContentDescription("End session").assertIsDisplayed()
    }

    @Test fun appendedConversationCardAutoScrollsToNewest() {
        val conversations = (1..4).map { index ->
            item(Speaker.A, "Existing card $index: " + "long transcript ".repeat(24), true).copy(id = "existing-$index")
        }
        val state = mutableStateOf(readyConversationState().copy(conversations = conversations))
        composeRule.setContent { RealtimeTranslateTheme { RealtimeTranslateApp(state.value, {}) } }

        composeRule.runOnUiThread {
            state.value = state.value.copy(conversations = state.value.conversations + item(Speaker.B, "Newest appended card: " + "long transcript ".repeat(24), true).copy(id = "newest"))
        }

        composeRule.waitForIdle()
        composeRule.onNodeWithText("Newest appended card:", substring = true).assertIsDisplayed()
    }

    @Test fun mainScreenProvidesSeparateLanguageChipsForBothSpeakers() {
        setApp(SessionUiState(SessionPhase.Ready))
        composeRule.onNodeWithContentDescription("Speaker A recognition language selector: Automatic (device recognizer)").assertIsEnabled()
        composeRule.onNodeWithContentDescription("Speaker A translation language selector: English").assertIsEnabled()
        composeRule.onNodeWithContentDescription("Speaker B recognition language selector: Automatic (device recognizer)").assertIsEnabled()
        composeRule.onNodeWithContentDescription("Speaker B translation language selector: Korean").assertIsEnabled()
    }

    @Test fun idleMainScreenStartsInOneTapAndKeepsPushToTalkLocked() {
        setApp(SessionUiState(SessionPhase.Ready))
        composeRule.onNodeWithContentDescription("Start conversation").assertIsEnabled()
        composeRule.onNodeWithContentDescription("Speaker A push-to-talk unlocks when the translation model is ready").assertIsNotEnabled()
        composeRule.onNodeWithContentDescription("Speaker B push-to-talk unlocks when the translation model is ready").assertIsNotEnabled()
    }

    @Test fun modelLoadingRendersInlineAndLocksLanguageChips() {
        setApp(SessionUiState(SessionPhase.LoadingModel, modelLoadProgress = 0.5f))
        composeRule.onNodeWithText("Loading translation model 50%").assertIsDisplayed()
        composeRule.onNodeWithContentDescription("Speaker A recognition language selector: Automatic (device recognizer)").assertIsNotEnabled()
        composeRule.onNodeWithContentDescription("Speaker A push-to-talk unlocks when the translation model is ready").assertIsNotEnabled()
    }

    @Test fun modelLoadFailureOffersInlineRetryOnTheMainScreen() {
        var action: UiAction? = null
        setApp(SessionUiState(SessionPhase.ModelLoadFailed, errorMessage = "offline"), onAction = { action = it })
        composeRule.onNodeWithText("offline").assertIsDisplayed()
        composeRule.onNodeWithContentDescription("Retry model load").performClick()
        assertEquals(UiAction.Retry, action)
    }

    @Test fun languageChipsAreLockedWhileAnUtteranceIsActive() {
        setApp(readyConversationState().copy(phase = SessionPhase.TranslatingA))
        composeRule.onNodeWithContentDescription("Speaker A translation language selector: English").assertIsNotEnabled()
        composeRule.onNodeWithContentDescription("Speaker B translation language selector: Korean").assertIsNotEnabled()
    }

    @Test fun liveSessionKeepsLanguageChipsEditable() {
        setApp(readyConversationState())
        composeRule.onNodeWithContentDescription("Speaker A translation language selector: English").assertIsEnabled()
        composeRule.onNodeWithContentDescription("Speaker B recognition language selector: Automatic (device recognizer)").assertIsEnabled()
    }

    @Test fun recognitionIntentUsesOfflineSettingsAndExplicitLanguage() {
        val explicit = OnDeviceRecognitionIntentFactory.create(SpeechLanguage.Installed("fr-FR", "French (France)"), 35)
        val automatic = OnDeviceRecognitionIntentFactory.create(SpeechLanguage.Automatic, 34)
        assertTrue(explicit.getBooleanExtra(android.speech.RecognizerIntent.EXTRA_PREFER_OFFLINE, false))
        assertEquals("fr-FR", explicit.getStringExtra(android.speech.RecognizerIntent.EXTRA_LANGUAGE))
        assertTrue(automatic.getBooleanExtra(android.speech.RecognizerIntent.EXTRA_ENABLE_LANGUAGE_DETECTION, false))
    }

    @Test fun viewModelEnforcesMutualExclusionRoutesTargetsAndRecoversAfterTranslationGate() {
        val adapter = FakeTranscriber()
        val state = readyConversationState().copy(
            settings = mapOf(
                Speaker.A to SpeakerSettings(readingLanguage = HyMt2Languages.all.first { it.code == "ko" }),
                Speaker.B to SpeakerSettings(readingLanguage = HyMt2Languages.all.first { it.code == "en" }),
            ),
        )
        val viewModel = SessionViewModel(transcriberFactory = { adapter }, translator = FakeTranslator(), initialState = state)

        composeRule.runOnUiThread {
            viewModel.dispatch(SessionAction.PttPress(composeRule.activity, Speaker.A))
            adapter.listener.onPartial("hello")
            viewModel.dispatch(SessionAction.PttPress(composeRule.activity, Speaker.B))
        }
        assertEquals(SessionPhase.ListeningA, viewModel.state.value.phase)
        assertEquals(1, adapter.starts)
        assertEquals(Speaker.A, viewModel.state.value.conversations.single().speaker)
        assertEquals("en", viewModel.state.value.conversations.single().targetLanguage.code)

        composeRule.runOnUiThread {
            adapter.listener.onFinal("hello world")
            viewModel.dispatch(SessionAction.PttRelease(Speaker.A))
            adapter.listener.onStopped()
        }
        assertEquals(SessionPhase.Ready, viewModel.state.value.phase)
        composeRule.waitForIdle()
        assertEquals("translated", viewModel.state.value.conversations.single().translation)

        composeRule.runOnUiThread {
            viewModel.dispatch(SessionAction.PttPress(composeRule.activity, Speaker.B))
            adapter.listener.onPartial("Hello")
        }
        assertEquals(SessionPhase.ListeningB, viewModel.state.value.phase)
        assertEquals(2, adapter.starts)
        assertEquals("ko", viewModel.state.value.conversations.last().targetLanguage.code)
    }

    private fun setApp(state: SessionUiState, onAction: (UiAction) -> Unit = {}, onOpenAppSettings: () -> Unit = {}) {
        composeRule.setContent { RealtimeTranslateTheme { RealtimeTranslateApp(state, onAction, onOpenAppSettings) } }
    }

    private fun readyConversationState() = SessionUiState(SessionPhase.Ready, conversationStarted = true)
    private fun item(speaker: Speaker, transcript: String, final: Boolean) = ConversationItem("1", speaker, SpeechLanguage.Automatic, HyMt2Languages.all.first { it.code == "en" }, transcript, final)

    private class FakeTranscriber : SpeechTranscriber {
        lateinit var listener: SpeechTranscriptListener
        var starts = 0
        override fun start(language: SpeechLanguage, listener: SpeechTranscriptListener): SpeechStartResult {
            starts += 1
            this.listener = listener
            listener.onReady()
            return SpeechStartResult.Started
        }
        override fun stop() = Unit
        override fun destroy() = Unit
    }

    private class FakeTranslator : HyMt2Translator {
        override suspend fun load(context: android.content.Context, onProgress: (Float) -> Unit) = Unit
        override suspend fun translate(prompt: String) = "translated"
        override fun close() = Unit
    }
}
