package ai.zetic.realtimetranslate

import android.content.Context
import android.content.ContextWrapper
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.test.setMain
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.async
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeout
import com.zeticai.mlange.core.model.llm.LLMNextTokenResult
import com.zeticai.mlange.core.model.llm.LLMRunResult
import java.util.concurrent.CountDownLatch
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

@OptIn(ExperimentalCoroutinesApi::class)
class SessionViewModelTest {
    private val dispatcher = StandardTestDispatcher()

    @Before fun setUp() = Dispatchers.setMain(dispatcher)
    @After fun tearDown() = Dispatchers.resetMain()

    @Test fun `starts only after the model finishes loading`() = runTest {
        val translator = FakeTranslator()
        val viewModel = SessionViewModel(translator = translator, initialState = SessionUiState(SessionPhase.Ready))

        viewModel.dispatch(SessionAction.StartConversation(TestContext()))
        assertEquals(SessionPhase.LoadingModel, viewModel.state.value.phase)
        withTimeout(5_000) { viewModel.state.first { it.phase == SessionPhase.Ready } }

        assertTrue(viewModel.state.value.conversationStarted)
        assertEquals(SessionPhase.Ready, viewModel.state.value.phase)
        assertEquals(1f, viewModel.state.value.modelLoadProgress)
    }

    @Test fun `model load failure offers retry state without enabling conversation`() = runTest {
        val translator = FakeTranslator(loadError = IllegalStateException("offline"))
        val viewModel = SessionViewModel(translator = translator, initialState = SessionUiState(SessionPhase.Ready))

        viewModel.dispatch(SessionAction.StartConversation(TestContext()))
        advanceUntilIdle()

        assertEquals(SessionPhase.ModelLoadFailed, viewModel.state.value.phase)
        assertFalse(viewModel.state.value.conversationStarted)
        assertEquals("offline", viewModel.state.value.errorMessage)
    }

    @Test fun `retry reloads after model load failure`() = runTest {
        val translator = FakeTranslator(loadError = IllegalStateException("offline"))
        val viewModel = SessionViewModel(translator = translator, initialState = SessionUiState(SessionPhase.Ready))

        viewModel.dispatch(SessionAction.StartConversation(TestContext()))
        advanceUntilIdle()
        viewModel.dispatch(SessionAction.Retry)
        advanceUntilIdle()

        assertEquals(2, translator.loads)
        assertEquals(SessionPhase.ModelLoadFailed, viewModel.state.value.phase)
    }

    @Test fun `ending a session unloads the translator before returning to setup`() = runTest {
        val translator = FakeTranslator()
        val viewModel = SessionViewModel(
            translator = translator,
            initialState = SessionUiState(SessionPhase.Ready, conversationStarted = true, conversations = listOf(ConversationItem("partial", Speaker.A, SpeechLanguage.Automatic, HyMt2Languages.all.first(), "partial", false, translationError = "error"))),
        )

        viewModel.dispatch(SessionAction.EndSession)

        assertEquals(SessionPhase.EndingSession, viewModel.state.value.phase)
        withTimeout(5_000) { viewModel.state.first { it.phase == SessionPhase.Ready } }
        assertTrue(translator.closed)
        assertFalse(viewModel.state.value.conversationStarted)
        assertEquals(SessionPhase.Ready, viewModel.state.value.phase)
        assertTrue(viewModel.state.value.conversations.isEmpty())
    }

    @Test fun `late speech callbacks after ending cannot restart translation`() = runTest {
        val translator = FakeTranslator()
        val transcriber = DelayedTranscriber()
        val viewModel = SessionViewModel(
            transcriberFactory = { transcriber },
            translator = translator,
            initialState = SessionUiState(SessionPhase.Ready, conversationStarted = true),
        )

        viewModel.dispatch(SessionAction.PttPress(TestContext(), Speaker.A))
        assertEquals(SessionPhase.ListeningA, viewModel.state.value.phase)
        viewModel.dispatch(SessionAction.EndSession)
        transcriber.listener.onFinal("late transcript")
        transcriber.listener.onStopped()
        advanceUntilIdle()

        assertTrue(translator.closed)
        assertEquals(0, translator.translations)
        assertEquals(SessionPhase.Ready, viewModel.state.value.phase)
        assertFalse(viewModel.state.value.conversationStarted)
        assertTrue(viewModel.state.value.conversations.isEmpty())
    }

    @Test fun `retry recovers an active session from a speech error without reloading`() = runTest {
        val translator = FakeTranslator()
        val transcriber = DelayedTranscriber()
        val viewModel = SessionViewModel(
            transcriberFactory = { transcriber },
            translator = translator,
            initialState = SessionUiState(SessionPhase.Ready, conversationStarted = true),
        )

        viewModel.dispatch(SessionAction.PttPress(TestContext(), Speaker.A))
        transcriber.listener.onError("Speech recognition failed.")
        assertEquals(SessionPhase.Error, viewModel.state.value.phase)
        viewModel.dispatch(SessionAction.Retry)

        assertEquals(SessionPhase.Ready, viewModel.state.value.phase)
        assertTrue(viewModel.state.value.conversationStarted)
        assertEquals(0, translator.loads)
    }

    @Test fun `unload waits for a running translation before closing the model`() = runTest {
        val enteredTokenWait = CountDownLatch(1)
        val releaseTokenWait = CountDownLatch(1)
        val fakeModel = object : HyMt2ModelSession {
            var closed = false
            override fun run(prompt: String) = LLMRunResult(0)
            override fun waitForNextToken(): LLMNextTokenResult {
                enteredTokenWait.countDown()
                releaseTokenWait.await()
                return LLMNextTokenResult(0, "bonjour", 1, isFinal = true)
            }
            override fun cleanUp() = Unit
            override fun close() { closed = true }
        }
        val translator = MelangeHyMt2Translator("test") { _, _ -> fakeModel }
        translator.load(TestContext()) { }
        val translating = async(Dispatchers.Default) { translator.translate("prompt") }
        withContext(Dispatchers.IO) { enteredTokenWait.await() }
        val unloading = async(Dispatchers.Default) { translator.unload() }

        assertFalse(fakeModel.closed)
        releaseTokenWait.countDown()
        translating.await()
        unloading.await()
        assertTrue(fakeModel.closed)
    }

    private class TestContext : ContextWrapper(null) {
        override fun getApplicationContext(): Context = this
    }

    private class FakeTranslator(private val loadError: Throwable? = null) : HyMt2Translator {
        var closed = false
        var loads = 0
        var translations = 0
        override suspend fun load(context: Context, onProgress: (Float) -> Unit) {
            loads += 1
            onProgress(0.5f)
            loadError?.let { throw it }
        }
        override suspend fun translate(prompt: String): String {
            translations += 1
            return "translated"
        }
        override fun close() { closed = true }
    }

    private class DelayedTranscriber : SpeechTranscriber {
        lateinit var listener: SpeechTranscriptListener
        override fun start(language: SpeechLanguage, listener: SpeechTranscriptListener): SpeechStartResult {
            this.listener = listener
            return SpeechStartResult.Started
        }
        override fun stop() = Unit
        override fun destroy() = Unit
    }
}
