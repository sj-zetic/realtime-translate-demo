package ai.zetic.realtimetranslate

enum class SessionPhase { PermissionRequired, LoadingModel, ModelLoadFailed, Ready, ListeningA, ListeningB, FinalizingA, FinalizingB, TranslatingA, TranslatingB, Error }

enum class Speaker(val label: String) {
    A("A"), B("B");

    fun other() = if (this == A) B else A
}

sealed interface SpeechLanguage {
    val displayName: UiText

    data object Automatic : SpeechLanguage {
        override val displayName: UiText get() = UiText.res(R.string.speech_language_automatic)
    }

    /**
     * [name] comes from the platform's own locale display names, already in the app's language, so
     * it is carried as text rather than as a key.
     */
    data class Installed(val languageTag: String, val name: String) : SpeechLanguage {
        override val displayName: UiText get() = UiText.raw(name)
    }
}

/**
 * [displayName] is deliberately never translated: it is not only a label but the argument the
 * Hy-MT2 prompt is built from (`Translate the following text into French`), so the instruction has
 * to stay English whatever the interface is written in.
 */
data class TranslationLanguage(val code: String, val displayName: String)

object HyMt2Languages {
    val all = listOf(
        TranslationLanguage("zh", "Chinese"), TranslationLanguage("en", "English"), TranslationLanguage("fr", "French"), TranslationLanguage("pt", "Portuguese"),
        TranslationLanguage("es", "Spanish"), TranslationLanguage("ja", "Japanese"), TranslationLanguage("tr", "Turkish"), TranslationLanguage("ru", "Russian"),
        TranslationLanguage("ar", "Arabic"), TranslationLanguage("ko", "Korean"), TranslationLanguage("th", "Thai"), TranslationLanguage("it", "Italian"),
        TranslationLanguage("de", "German"), TranslationLanguage("vi", "Vietnamese"), TranslationLanguage("ms", "Malay"), TranslationLanguage("id", "Indonesian"),
        TranslationLanguage("fil", "Filipino"), TranslationLanguage("hi", "Hindi"), TranslationLanguage("zh-Hant", "Traditional Chinese"), TranslationLanguage("pl", "Polish"),
        TranslationLanguage("cs", "Czech"), TranslationLanguage("nl", "Dutch"), TranslationLanguage("km", "Khmer"), TranslationLanguage("my", "Burmese"),
        TranslationLanguage("fa", "Persian"), TranslationLanguage("gu", "Gujarati"), TranslationLanguage("ur", "Urdu"), TranslationLanguage("te", "Telugu"),
        TranslationLanguage("mr", "Marathi"), TranslationLanguage("he", "Hebrew"), TranslationLanguage("bn", "Bengali"), TranslationLanguage("ta", "Tamil"),
        TranslationLanguage("uk", "Ukrainian"), TranslationLanguage("bo", "Tibetan"), TranslationLanguage("kk", "Kazakh"), TranslationLanguage("mn", "Mongolian"),
        TranslationLanguage("ug", "Uyghur"), TranslationLanguage("yue", "Cantonese"),
    )
}

data class SpeakerSettings(
    val inputLanguage: SpeechLanguage = SpeechLanguage.Automatic,
    val readingLanguage: TranslationLanguage = HyMt2Languages.all.first { it.code == "en" },
)

/**
 * Defaults let a first session start in one tap: automatic recognition for both speakers and two
 * different reading languages, so the very first utterance is actually translated.
 */
fun defaultSpeakerSettings(): Map<Speaker, SpeakerSettings> = mapOf(
    Speaker.A to SpeakerSettings(readingLanguage = HyMt2Languages.all.first { it.code == "en" }),
    Speaker.B to SpeakerSettings(readingLanguage = HyMt2Languages.all.first { it.code == "ko" }),
)

data class ConversationItem(
    val id: String,
    val speaker: Speaker,
    val sourceLanguage: SpeechLanguage,
    val targetLanguage: TranslationLanguage,
    val transcript: String,
    val isFinal: Boolean,
    val translation: String? = null,
    val translationError: UiText? = null,
)

data class SessionUiState(
    val phase: SessionPhase,
    val permissionPermanentlyDenied: Boolean = false,
    val settings: Map<Speaker, SpeakerSettings> = defaultSpeakerSettings(),
    val conversations: List<ConversationItem> = emptyList(),
    val conversationStarted: Boolean = false,
    val modelLoadProgress: Float = 0f,
    val speechLanguages: List<SpeechLanguage> = listOf(SpeechLanguage.Automatic),
    val speechLanguageCatalogLoading: Boolean = false,
    val speechLanguageCatalogMessage: UiText? = null,
    val errorMessage: UiText? = null,
) {
    fun settingsFor(speaker: Speaker) = settings.getValue(speaker)

    /**
     * The drawer's `Clear conversation` row is disabled, not hidden, when there is nothing to clear
     * and while an utterance is recording, finalizing, or translating: the row never moves, and it
     * never strands a bubble a translation is about to land in.
     */
    val canClearConversation: Boolean get() = conversations.isNotEmpty() && activeSpeaker() == null

    fun activeSpeaker(): Speaker? = when (phase) {
        SessionPhase.ListeningA, SessionPhase.FinalizingA, SessionPhase.TranslatingA -> Speaker.A
        SessionPhase.ListeningB, SessionPhase.FinalizingB, SessionPhase.TranslatingB -> Speaker.B
        else -> null
    }
}
