package ai.zetic.realtimetranslate

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.util.Locale

/**
 * The spoken-translation decisions. Nothing here listens to a speaker: the announcement rule, the
 * voice match, and the audio-focus handoff are all exercised over fakes, and the `TextToSpeech`
 * shell around them is verified on a device.
 */
class SpeechOutputTest {

    // region What gets spoken

    @Test fun `a translation is spoken once, at the moment its bubble reaches the translated state`() {
        val output = FakeSpeechOutput()
        val announcer = SpokenTranslationAnnouncer(output)

        announcer.onConversationsChanged(listOf(pending("1")), isMuted = false)
        assertEquals(emptyList<String>(), output.spoken)

        announcer.onConversationsChanged(listOf(translated("1", "annyeong")), isMuted = false)
        assertEquals(listOf("annyeong" to "ko"), output.spoken)

        // The same transcript arriving again, as any recomposition delivers it, says nothing more.
        announcer.onConversationsChanged(listOf(translated("1", "annyeong")), isMuted = false)
        assertEquals(listOf("annyeong" to "ko"), output.spoken)
    }

    @Test fun `a transcript already on screen is never read aloud when the announcer is created`() {
        val output = FakeSpeechOutput()
        val existing = listOf(translated("1", "annyeong"), translated("2", "yeoboseyo"))
        val announcer = SpokenTranslationAnnouncer(output).seed(existing)

        announcer.onConversationsChanged(existing, isMuted = false)

        assertEquals(emptyList<Pair<String, String>>(), output.spoken)
    }

    @Test fun `newest wins, so a translation that lands mid-sentence cuts the older one off`() {
        val output = FakeSpeechOutput()
        val announcer = SpokenTranslationAnnouncer(output)

        announcer.onConversationsChanged(listOf(translated("1", "first")), isMuted = false)
        announcer.onConversationsChanged(
            listOf(translated("1", "first"), translated("2", "second")),
            isMuted = false,
        )

        assertEquals(listOf("first" to "ko", "second" to "ko"), output.spoken)
        // The output replaces rather than queues, which is what QUEUE_FLUSH means downstream.
        assertEquals(2, output.speakCalls)
    }

    @Test fun `two translations arriving in one update speak only the newest`() {
        val output = FakeSpeechOutput()
        val announcer = SpokenTranslationAnnouncer(output)

        announcer.onConversationsChanged(
            listOf(translated("1", "first"), translated("2", "second")),
            isMuted = false,
        )

        assertEquals(listOf("second" to "ko"), output.spoken)
    }

    @Test fun `muting suppresses the announcement and never builds a backlog to unmute into`() {
        val output = FakeSpeechOutput()
        val announcer = SpokenTranslationAnnouncer(output)

        announcer.onConversationsChanged(listOf(translated("1", "annyeong")), isMuted = true)
        assertEquals(emptyList<Pair<String, String>>(), output.spoken)

        // Unmuting is not a cue to read what was missed: that turn is over.
        announcer.onConversationsChanged(listOf(translated("1", "annyeong")), isMuted = false)
        assertEquals(emptyList<Pair<String, String>>(), output.spoken)
    }

    @Test fun `a failed translation and an empty one say nothing`() {
        val output = FakeSpeechOutput()
        val announcer = SpokenTranslationAnnouncer(output)

        announcer.onConversationsChanged(
            listOf(
                translated("1", "  ").copy(translationError = null),
                translated("2", "annyeong").copy(translationError = UiText.raw("failed")),
            ),
            isMuted = false,
        )

        assertEquals(emptyList<Pair<String, String>>(), output.spoken)
    }

    @Test fun `a cleared transcript lets the same ids speak again when they are rebuilt`() {
        val output = FakeSpeechOutput()
        val announcer = SpokenTranslationAnnouncer(output)

        announcer.onConversationsChanged(listOf(translated("1", "annyeong")), isMuted = false)
        announcer.onConversationsChanged(emptyList(), isMuted = false)
        announcer.onConversationsChanged(listOf(translated("1", "annyeong")), isMuted = false)

        assertEquals(listOf("annyeong" to "ko", "annyeong" to "ko"), output.spoken)
    }

    @Test fun `beginning a turn stops speech, because nothing is spoken over an open microphone`() {
        val output = FakeSpeechOutput()
        val announcer = SpokenTranslationAnnouncer(output)

        announcer.onConversationsChanged(listOf(translated("1", "annyeong")), isMuted = false)
        announcer.stop()

        assertEquals(1, output.stops)
    }

    @Test fun `replay speaks the same bubble again under the same rules`() {
        val output = FakeSpeechOutput()
        val announcer = SpokenTranslationAnnouncer(output)
        val bubble = translated("1", "annyeong")

        announcer.replay(bubble, isMuted = false)
        announcer.replay(bubble, isMuted = true)

        assertEquals(listOf("annyeong" to "ko"), output.spoken)
    }

    @Test fun `the recognizer holding the microphone is exactly listening and finalizing`() {
        val live = setOf(
            SessionPhase.ListeningA,
            SessionPhase.ListeningB,
            SessionPhase.FinalizingA,
            SessionPhase.FinalizingB,
        )
        SessionPhase.entries.forEach { phase ->
            assertEquals(phase.name, phase in live, SessionUiState(phase).isRecognizerLive)
        }
    }

    // endregion

    // region The replay control

    @Test fun `the replay control is absent on a bubble with nothing to play`() {
        assertFalse(ReplayControl.isPresent(pending("1")))
        assertFalse(ReplayControl.isPresent(translated("1", "annyeong").copy(translationError = UiText.raw("no"))))
        assertTrue(ReplayControl.isPresent(translated("1", "annyeong")))
    }

    @Test fun `the replay control is present but disabled while muted or while the microphone is open`() {
        val bubble = translated("1", "annyeong")
        assertTrue(ReplayControl.isEnabled(bubble, isMuted = false, isRecognizerLive = false))
        assertFalse(ReplayControl.isEnabled(bubble, isMuted = true, isRecognizerLive = false))
        assertFalse(ReplayControl.isEnabled(bubble, isMuted = false, isRecognizerLive = true))
    }

    // endregion

    // region Voice matching

    @Test fun `an exact match for the reading code wins`() {
        assertEquals(
            Locale.forLanguageTag("zh-TW"),
            SpeechVoiceMatching.match("zh-TW", locales("zh-CN", "zh-TW", "en-US")),
        )
    }

    @Test fun `a bare code takes the variant it implies before any other of the same language`() {
        assertEquals(
            Locale.forLanguageTag("zh-TW"),
            SpeechVoiceMatching.match("zh-Hant", locales("zh-CN", "zh-TW")),
        )
        assertEquals(
            Locale.forLanguageTag("en-US"),
            SpeechVoiceMatching.match("en", locales("en-GB", "en-US")),
        )
        assertEquals(
            Locale.forLanguageTag("pt-BR"),
            SpeechVoiceMatching.match("pt", locales("pt-PT", "pt-BR")),
        )
    }

    @Test fun `a code with no implied variant falls back to any voice for the same language`() {
        assertEquals(
            Locale.forLanguageTag("th-TH"),
            SpeechVoiceMatching.match("th", locales("th-TH", "en-US")),
        )
    }

    @Test fun `a language with no installed voice stays silent rather than borrowing another`() {
        assertNull(SpeechVoiceMatching.match("bo", locales("en-US", "ko-KR")))
        assertNull(SpeechVoiceMatching.match("ko", emptyList()))
    }

    // endregion

    // region Audio focus

    @Test fun `focus is claimed once and held across a replacement`() {
        val focus = FakeAudioFocus()
        val coordinator = SpeechAudioCoordinator(focus)

        assertTrue(coordinator.claim())
        assertTrue(coordinator.claim())

        assertEquals(1, focus.requests)
        assertTrue(coordinator.isHoldingFocus)
    }

    @Test fun `focus is handed back once, and a second release does nothing`() {
        val focus = FakeAudioFocus()
        val coordinator = SpeechAudioCoordinator(focus)

        coordinator.claim()
        coordinator.release()
        coordinator.release()

        assertEquals(1, focus.abandons)
        assertFalse(coordinator.isHoldingFocus)
    }

    @Test fun `a refused focus request leaves nothing claimed and is retried next time`() {
        val focus = FakeAudioFocus(granted = false)
        val coordinator = SpeechAudioCoordinator(focus)

        assertFalse(coordinator.claim())
        assertFalse(coordinator.isHoldingFocus)
        coordinator.release()
        assertEquals(0, focus.abandons)

        focus.granted = true
        assertTrue(coordinator.claim())
        assertEquals(2, focus.requests)
    }

    // endregion

    private fun locales(vararg tags: String) = tags.map(Locale::forLanguageTag)

    private fun pending(id: String) = ConversationItem(
        id = id,
        speaker = Speaker.A,
        sourceLanguage = SpeechLanguage.Automatic,
        targetLanguage = HyMt2Languages.all.first { it.code == "ko" },
        transcript = "hello",
        isFinal = true,
    )

    private fun translated(id: String, translation: String) = pending(id).copy(translation = translation)

    private class FakeSpeechOutput : SpeechOutput {
        val spoken = mutableListOf<Pair<String, String>>()
        var speakCalls = 0
        var stops = 0

        override fun speak(text: String, languageCode: String) {
            speakCalls += 1
            spoken += text to languageCode
        }

        override fun stop() { stops += 1 }
        override fun shutdown() = Unit
    }

    private class FakeAudioFocus(var granted: Boolean = true) : SpeechAudioFocus {
        var requests = 0
        var abandons = 0

        override fun request(): Boolean {
            requests += 1
            return granted
        }

        override fun abandon() { abandons += 1 }
    }
}
