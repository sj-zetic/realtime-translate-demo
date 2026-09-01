package ai.zetic.realtimetranslate

import android.content.Context
import android.media.AudioAttributes
import android.media.AudioFocusRequest
import android.media.AudioManager
import android.speech.tts.TextToSpeech
import android.speech.tts.UtteranceProgressListener
import java.util.Locale

/**
 * Spoken translation output, and the decisions behind it.
 *
 * A translation that arrives is read aloud in the language it was translated into, so the person it
 * is for can listen instead of leaning over the phone. The voice is the platform's own synthesizer;
 * no model is downloaded and nothing is sent anywhere.
 *
 * Nothing here can be asserted by listening to a speaker, so the split the session-comfort work
 * uses applies again: every decision is a pure function or a small state machine over an injected
 * seam, and the `TextToSpeech` call is the thin shell around it. The tests exercise the decisions;
 * the sound itself is verified on a device.
 */

// region What gets spoken

/**
 * The states in which the microphone is open and the recognizer owns the audio route. Nothing is
 * ever spoken in these. `Translating` is not one of them: the recognizer has already been released
 * by the time a translation is under way.
 */
val SessionUiState.isRecognizerLive: Boolean
    get() = phase in setOf(
        SessionPhase.ListeningA,
        SessionPhase.ListeningB,
        SessionPhase.FinalizingA,
        SessionPhase.FinalizingB,
    )

/**
 * The text this bubble can speak: a finished translation and nothing else. A bubble that is still
 * recognizing, still translating, or whose translation failed has nothing to say, which is exactly
 * when the replay control is absent rather than disabled.
 */
val ConversationItem.speakableTranslation: String?
    get() = translation?.takeIf { translationError == null && it.isNotBlank() }

/**
 * Whether a bubble speaks, and in which language. The one rule both the automatic announcement and
 * the replay control go through, so muting cannot suppress only one of them.
 */
sealed interface SpokenTranslation {
    data class Speak(val text: String, val languageCode: String) : SpokenTranslation
    data object Silent : SpokenTranslation

    companion object {
        fun decision(item: ConversationItem, isMuted: Boolean): SpokenTranslation {
            if (isMuted) return Silent
            val text = item.speakableTranslation ?: return Silent
            return Speak(text, item.targetLanguage.code)
        }
    }
}

/**
 * The replay control on a translated bubble. Absent when there is nothing to play, and present but
 * disabled while sound is off or the recognizer holds the microphone: a control that answers a tap
 * with silence reads as broken rather than busy.
 */
object ReplayControl {
    fun isPresent(item: ConversationItem): Boolean = item.speakableTranslation != null

    fun isEnabled(item: ConversationItem, isMuted: Boolean, isRecognizerLive: Boolean): Boolean =
        isPresent(item) && !isMuted && !isRecognizerLive
}

// endregion

// region Voice matching

/**
 * Picking the voice a translation is read in. The reading language is a Hy-MT2 code such as `ko` or
 * `zh-Hant`; the installed voices are concrete locales such as `ko-KR` or `zh-TW`. The two are
 * matched rather than compared, in three steps: an exact match for the code, then the variant that
 * code implies, then any installed voice for the same language.
 *
 * No match means the translation stays silent. A language with no installed voice is never read out
 * in another language's voice.
 */
object SpeechVoiceMatching {
    fun match(code: String, available: List<Locale>): Locale? {
        val target = Locale.forLanguageTag(code)
        val language = target.language.takeIf { it.isNotEmpty() } ?: return null
        available.firstOrNull { it.toLanguageTag().equals(code, ignoreCase = true) }?.let { return it }
        val candidates = available
            .filter { it.language.equals(language, ignoreCase = true) }
            .sortedBy { it.toLanguageTag() }
        if (candidates.size <= 1) return candidates.firstOrNull()
        val implied = subtags(code) + likelyVariants.getOrElse(code) { emptySet() }
        return candidates.firstOrNull { subtags(it.toLanguageTag()).any(implied::contains) } ?: candidates.first()
    }

    /** Everything after the primary subtag, upper-cased so `Hant` and `HANT` compare equal. */
    private fun subtags(tag: String): Set<String> =
        tag.split('-', '_').drop(1).filter(String::isNotEmpty).map { it.uppercase(Locale.ROOT) }.toSet()

    /**
     * The variant a bare reading code implies, for the Hy-MT2 languages a phone plausibly carries
     * more than one voice for. The same table the recognizer's language matching uses, because the
     * question is the same one.
     */
    private val likelyVariants = mapOf(
        "ar" to setOf("SA"),
        "bn" to setOf("BD"),
        "de" to setOf("DE"),
        "en" to setOf("US"),
        "es" to setOf("ES"),
        "fr" to setOf("FR"),
        "it" to setOf("IT"),
        "ms" to setOf("MY"),
        "nl" to setOf("NL"),
        "pt" to setOf("BR"),
        "ta" to setOf("IN"),
        "ur" to setOf("PK"),
        "zh" to setOf("CN", "HANS"),
        "zh-Hant" to setOf("TW", "HANT"),
    )
}

// endregion

// region Audio focus

/** The audio focus the speech output needs. `AudioManager` in the app, a spy in tests. */
interface SpeechAudioFocus {
    /** @return whether focus was granted. A refusal means nothing is spoken. */
    fun request(): Boolean
    fun abandon()
}

/**
 * Owns the focus handoff, and remembers which side currently holds it.
 *
 * The memory is the point. A translation that finishes while another is being spoken must not drop
 * and re-take focus mid-sentence, and the utterance-done callback that says speech ended arrives
 * after the next push-to-talk may already have claimed the microphone. Both are the same bug, and
 * both are prevented by only ever writing a change: [release] after focus was already handed back
 * does nothing at all.
 */
class SpeechAudioCoordinator(private val focus: SpeechAudioFocus) {
    var isHoldingFocus: Boolean = false
        private set

    /**
     * Claims focus for speech. Returns whether it is safe to speak: a refusal leaves focus
     * unclaimed, so nothing is spoken over whatever holds the route, and the next translation
     * tries again from scratch.
     */
    fun claim(): Boolean {
        if (isHoldingFocus) return true
        isHoldingFocus = focus.request()
        return isHoldingFocus
    }

    /** Hands focus back, once. Called when speech ends and, synchronously, before a turn starts. */
    fun release() {
        if (!isHoldingFocus) return
        isHoldingFocus = false
        focus.abandon()
    }
}

/**
 * Transient focus that ducks rather than pauses: a translation is one short sentence, and whatever
 * else the phone is playing should dip under it and come straight back.
 */
class AndroidSpeechAudioFocus(context: Context) : SpeechAudioFocus {
    private val manager = context.applicationContext.getSystemService(AudioManager::class.java)
    private var request: AudioFocusRequest? = null

    private val listener = AudioManager.OnAudioFocusChangeListener { }

    override fun request(): Boolean {
        val audioManager = manager ?: return false
        val focusRequest = AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN_TRANSIENT_MAY_DUCK)
            .setAudioAttributes(
                AudioAttributes.Builder()
                    .setUsage(AudioAttributes.USAGE_ASSISTANT)
                    .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH)
                    .build(),
            )
            // The listener is required for a focus request and deliberately does nothing: losing
            // focus mid-sentence is not worth reacting to, and the engine stops on its own.
            .setOnAudioFocusChangeListener(listener)
            .build()
        request = focusRequest
        return audioManager.requestAudioFocus(focusRequest) == AudioManager.AUDIOFOCUS_REQUEST_GRANTED
    }

    override fun abandon() {
        val audioManager = manager ?: return
        request?.let { audioManager.abandonAudioFocusRequest(it) }
        request = null
    }
}

// endregion

// region Speech output

/** Anything that can read a translation aloud. `TextToSpeech` in the app, a fake in tests. */
interface SpeechOutput {
    /**
     * Speaks [text] in the best available voice for [languageCode], replacing anything already
     * being spoken. A language with no installed voice speaks nothing rather than reading the
     * sentence in the wrong accent.
     */
    fun speak(text: String, languageCode: String)

    /** Stops immediately and hands audio focus back, so an interrupting turn can start clean. */
    fun stop()

    fun shutdown()
}

/**
 * The announcement rule over an injected [SpeechOutput]: a translation is spoken exactly once, at
 * the moment its bubble reaches the translated state, and a newer translation cuts off an older one
 * rather than queueing behind it. Two people talking must never build a backlog of sentences the
 * phone still owes them.
 *
 * The set of already-announced ids is the whole state. It is seeded from the transcript the
 * announcer is created over, so a recomposition or a rotation never re-reads a conversation that
 * has already been spoken.
 */
class SpokenTranslationAnnouncer(private val output: SpeechOutput) {
    private val announced = mutableSetOf<String>()

    /** Marks everything already translated as heard, without speaking any of it. */
    fun seed(items: List<ConversationItem>) = apply {
        items.filter { it.speakableTranslation != null }.forEach { announced += it.id }
    }

    /**
     * Speaks whatever reached the translated state since the last call. More than one at once is
     * only possible when the transcript was rebuilt, and newest-wins makes it the last one anyway.
     */
    fun onConversationsChanged(items: List<ConversationItem>, isMuted: Boolean) {
        val arrived = items.filter { it.speakableTranslation != null && it.id !in announced }
        // Marked heard whether or not sound is on, so unmuting never blurts out a backlog.
        arrived.forEach { announced += it.id }
        arrived.lastOrNull()?.let { speak(it, isMuted) }
        // A cleared or restarted transcript takes its ids with it.
        announced.retainAll(items.mapTo(mutableSetOf()) { it.id })
    }

    /** The replay control. Same rule as the automatic announcement, including newest-wins. */
    fun replay(item: ConversationItem, isMuted: Boolean) = speak(item, isMuted)

    /**
     * Nothing is ever spoken while the microphone is open, so a turn beginning stops speech
     * synchronously before the recognizer starts. Ending a session and clearing the transcript stop
     * it too: that sentence belongs to a conversation that is going away.
     */
    fun stop() = output.stop()

    private fun speak(item: ConversationItem, isMuted: Boolean) {
        when (val decision = SpokenTranslation.decision(item, isMuted)) {
            is SpokenTranslation.Speak -> output.speak(decision.text, decision.languageCode)
            SpokenTranslation.Silent -> Unit
        }
    }
}

/**
 * The platform synthesizer, behind [SpeechOutput].
 *
 * The engine is asynchronous to start and the first translation can land before it is ready, so
 * every call guards on the init callback rather than assuming it. Focus is claimed once and held
 * across a replacement, because replacing one sentence with a newer one is a cut, not a route
 * change the listener should hear.
 */
class AndroidSpeechOutput(
    context: Context,
    private val audio: SpeechAudioCoordinator = SpeechAudioCoordinator(AndroidSpeechAudioFocus(context)),
) : SpeechOutput {
    private var engine: TextToSpeech? = null
    private var isReady = false
    private var utteranceCount = 0

    init {
        engine = TextToSpeech(context.applicationContext) { status ->
            isReady = status == TextToSpeech.SUCCESS
        }.apply {
            setOnUtteranceProgressListener(object : UtteranceProgressListener() {
                override fun onStart(utteranceId: String?) = Unit
                override fun onDone(utteranceId: String?) = releaseIfIdle()
                override fun onStop(utteranceId: String?, interrupted: Boolean) = releaseIfIdle()

                @Deprecated("Replaced by onError(String, Int)", ReplaceWith(""))
                override fun onError(utteranceId: String?) = releaseIfIdle()
                override fun onError(utteranceId: String?, errorCode: Int) = releaseIfIdle()
            })
        }
    }

    private val availableLocales: List<Locale>
        get() = runCatching { engine?.availableLanguages?.toList() }.getOrNull().orEmpty()

    override fun speak(text: String, languageCode: String) {
        val tts = engine?.takeIf { isReady } ?: return
        val voice = SpeechVoiceMatching.match(languageCode, availableLocales)
        if (voice == null) {
            // No voice for this language at all: say nothing rather than read it in another accent.
            stop()
            return
        }
        val setLanguage = runCatching { tts.setLanguage(voice) }.getOrDefault(TextToSpeech.LANG_MISSING_DATA)
        if (setLanguage == TextToSpeech.LANG_MISSING_DATA || setLanguage == TextToSpeech.LANG_NOT_SUPPORTED) {
            stop()
            return
        }
        // Newest wins. Focus is deliberately not released here: the cut should not be audible.
        if (!audio.claim()) return
        utteranceCount += 1
        tts.speak(text, TextToSpeech.QUEUE_FLUSH, null, "translation-$utteranceCount")
    }

    override fun stop() {
        runCatching { engine?.stop() }
        audio.release()
    }

    override fun shutdown() {
        stop()
        runCatching { engine?.shutdown() }
        engine = null
        isReady = false
    }

    /** The end of one utterance is only the end of speech when nothing took its place. */
    private fun releaseIfIdle() {
        if (engine?.isSpeaking == true) return
        audio.release()
    }
}

// endregion
