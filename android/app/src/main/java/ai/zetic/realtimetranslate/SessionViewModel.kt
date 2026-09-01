package ai.zetic.realtimetranslate

import android.content.Context
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

sealed interface SessionAction {
    data class PermissionChanged(val granted: Boolean, val permanentlyDenied: Boolean = false) : SessionAction
    data class RefreshSpeechLanguages(val context: Context) : SessionAction
    data class InputLanguageChanged(val speaker: Speaker, val language: SpeechLanguage) : SessionAction
    data class ReadingLanguageChanged(val speaker: Speaker, val language: TranslationLanguage) : SessionAction
    data class StartConversation(val context: Context) : SessionAction
    data object EndSession : SessionAction
    data object ClearConversation : SessionAction
    data class PttPress(val context: Context, val speaker: Speaker) : SessionAction
    data class PttRelease(val speaker: Speaker) : SessionAction
    data class TogglePtt(val context: Context, val speaker: Speaker) : SessionAction
    data object Retry : SessionAction
}

class SessionViewModel(
    private val transcriberFactory: (Context) -> SpeechTranscriber = { AndroidOnDeviceSpeechTranscriber(it) },
    private val translator: HyMt2Translator = MelangeHyMt2Translator(BuildConfig.MELANGE_PERSONAL_KEY),
    private val speechLanguageCatalog: SpeechLanguageCatalog = AndroidSpeechLanguageCatalog,
    initialState: SessionUiState = SessionUiState(SessionPhase.PermissionRequired),
) : ViewModel() {
    private val mutableState = MutableStateFlow(initialState)
    val state: StateFlow<SessionUiState> = mutableState.asStateFlow()
    private var transcriber: SpeechTranscriber? = null
    private var applicationContext: Context? = null

    fun dispatch(action: SessionAction) = when (action) {
        is SessionAction.PermissionChanged -> mutableState.value = mutableState.value.copy(
            phase = if (action.granted) SessionPhase.Ready else SessionPhase.PermissionRequired,
            permissionPermanentlyDenied = !action.granted && action.permanentlyDenied,
            errorMessage = null,
        )
        is SessionAction.RefreshSpeechLanguages -> refreshSpeechLanguages(action.context)
        is SessionAction.InputLanguageChanged -> updateSettings(action.speaker) { it.copy(inputLanguage = action.language) }
        is SessionAction.ReadingLanguageChanged -> updateSettings(action.speaker) {
            alignInputLanguage(it.copy(readingLanguage = action.language), mutableState.value.speechLanguages)
        }
        is SessionAction.StartConversation -> loadModel(action.context)
        SessionAction.EndSession -> endSession()
        SessionAction.ClearConversation -> clearConversation()
        is SessionAction.PttPress -> start(action.context, action.speaker)
        is SessionAction.PttRelease -> stop(action.speaker)
        is SessionAction.TogglePtt -> toggle(action.context, action.speaker)
        SessionAction.Retry -> retry()
    }

    private fun updateSettings(speaker: Speaker, transform: (SpeakerSettings) -> SpeakerSettings) {
        val current = mutableState.value
        mutableState.value = current.copy(settings = current.settings + (speaker to transform(current.settingsFor(speaker))))
    }

    /**
     * A speaker's chip language drives what the recognizer listens for, so a speaker shown as
     * Korean is listened to in Korean. A reading language with no installed recognizer leaves the
     * spoken language exactly as it was.
     */
    private fun alignInputLanguage(settings: SpeakerSettings, languages: List<SpeechLanguage>): SpeakerSettings {
        val match = SpokenLanguageMatching.match(settings.readingLanguage, languages) ?: return settings
        return settings.copy(inputLanguage = match)
    }

    private fun refreshSpeechLanguages(context: Context) {
        if (mutableState.value.conversationStarted || mutableState.value.speechLanguageCatalogLoading) return
        mutableState.value = mutableState.value.copy(speechLanguageCatalogLoading = true, speechLanguageCatalogMessage = null)
        speechLanguageCatalog.load(context.applicationContext) { result ->
            val validLanguages = result.languages.ifEmpty { listOf(SpeechLanguage.Automatic) }
            val current = mutableState.value
            // The catalog arriving is the first moment a spoken language can be derived at all, so
            // it stands in for init here. A speaker who has explicitly picked a spoken language is
            // left alone; that override survives until their reading language changes again.
            val aligned = current.settings.mapValues { (_, settings) ->
                if (settings.inputLanguage == SpeechLanguage.Automatic) alignInputLanguage(settings, validLanguages) else settings
            }
            mutableState.value = current.copy(settings = aligned, speechLanguages = validLanguages, speechLanguageCatalogLoading = false, speechLanguageCatalogMessage = result.message)
        }
    }

    private fun loadModel(context: Context) {
        val current = mutableState.value
        if (current.phase !in setOf(SessionPhase.Ready, SessionPhase.ModelLoadFailed)) return
        applicationContext = context.applicationContext
        mutableState.value = current.copy(phase = SessionPhase.LoadingModel, errorMessage = null, modelLoadProgress = 0f)
        viewModelScope.launch {
            runCatching {
                translator.load(requireNotNull(applicationContext)) { progress ->
                    mutableState.value = mutableState.value.copy(modelLoadProgress = progress.coerceIn(0f, 1f))
                }
            }.onSuccess {
                mutableState.value = mutableState.value.copy(phase = SessionPhase.Ready, conversationStarted = true, modelLoadProgress = 1f)
            }.onFailure { error ->
                mutableState.value = mutableState.value.copy(phase = SessionPhase.ModelLoadFailed, errorMessage = error.asUiText(R.string.error_model_load_failed))
            }
        }
    }

    private fun start(context: Context, speaker: Speaker) {
        val current = mutableState.value
        if (!current.conversationStarted || current.phase != SessionPhase.Ready) return
        val newTranscriber = transcriberFactory(context.applicationContext)
        transcriber?.destroy()
        transcriber = newTranscriber
        mutableState.value = current.copy(phase = finalizingPhase(speaker), errorMessage = null)
        when (val result = newTranscriber.start(current.settingsFor(speaker).inputLanguage, transcriptListener(speaker, newTranscriber))) {
            SpeechStartResult.Started -> listening(speaker, newTranscriber)
            is SpeechStartResult.Failed -> fail(result.message)
        }
    }

    private fun toggle(context: Context, speaker: Speaker) = when (mutableState.value.phase) {
        listeningPhase(speaker) -> stop(speaker)
        SessionPhase.Ready -> start(context, speaker)
        else -> Unit
    }

    private fun listening(speaker: Speaker, owner: SpeechTranscriber) {
        val current = mutableState.value
        if (transcriber !== owner || current.phase !in setOf(finalizingPhase(speaker), listeningPhase(speaker))) return
        mutableState.value = current.copy(phase = listeningPhase(speaker))
    }

    private fun transcriptListener(speaker: Speaker, owner: SpeechTranscriber) = object : SpeechTranscriptListener {
        override fun onReady() = listening(speaker, owner)
        override fun onPartial(transcript: String) = updateTranscript(speaker, transcript, false, owner)
        override fun onFinal(transcript: String) = updateTranscript(speaker, transcript, true, owner)
        override fun onStopped() {
            if (transcriber !== owner) return
            owner.destroy()
            finalize(speaker, owner)
        }
        override fun onError(message: UiText) = fail(message, owner)
    }

    private fun updateTranscript(speaker: Speaker, transcript: String, isFinal: Boolean, owner: SpeechTranscriber) {
        val current = mutableState.value
        if (transcriber !== owner || current.activeSpeaker() != speaker) return
        val pending = current.conversations.lastOrNull()?.takeIf { it.speaker == speaker && !it.isFinal }
        val item = ConversationItem(
            id = pending?.id ?: "transcript-${current.conversations.size}", speaker = speaker,
            sourceLanguage = current.settingsFor(speaker).inputLanguage, targetLanguage = current.settingsFor(speaker.other()).readingLanguage,
            transcript = transcript, isFinal = isFinal,
        )
        mutableState.value = current.copy(conversations = if (pending == null) current.conversations + item else current.conversations.dropLast(1) + item)
    }

    private fun stop(speaker: Speaker) {
        if (mutableState.value.phase != listeningPhase(speaker)) return
        mutableState.value = mutableState.value.copy(phase = finalizingPhase(speaker))
        transcriber?.stop()
    }

    private fun finalize(speaker: Speaker, owner: SpeechTranscriber) {
        val current = mutableState.value
        if (transcriber !== owner || current.phase != finalizingPhase(speaker)) return
        val item = current.conversations.lastOrNull()?.takeIf { it.speaker == speaker && it.isFinal }
        if (item == null) {
            transcriber = null
            mutableState.value = current.copy(phase = SessionPhase.Ready)
            return
        }
        transcriber = null
        mutableState.value = current.copy(phase = translatingPhase(speaker))
        val prompt = HyMt2TranslationRequestBuilder.build(item.transcript, item.targetLanguage)
        viewModelScope.launch {
            runCatching { translator.translate(prompt) }
                .onSuccess { completeTranslation(item.id, it) }
                .onFailure { failTranslation(item.id, it.asUiText(R.string.error_translation_failed)) }
        }
    }

    private fun completeTranslation(id: String, translation: String) {
        val current = mutableState.value
        if (!current.conversationStarted) return
        mutableState.value = current.copy(phase = SessionPhase.Ready, conversations = current.conversations.map { if (it.id == id) it.copy(translation = translation, translationError = null) else it })
    }
    private fun failTranslation(id: String, message: UiText) {
        val current = mutableState.value
        if (!current.conversationStarted) return
        mutableState.value = current.copy(phase = SessionPhase.Ready, conversations = current.conversations.map { if (it.id == id) it.copy(translationError = message) else it })
    }
    private fun fail(message: UiText, owner: SpeechTranscriber? = transcriber) {
        if (owner !== transcriber || !mutableState.value.conversationStarted) return
        owner?.destroy(); transcriber = null
        mutableState.value = mutableState.value.copy(phase = SessionPhase.Error, errorMessage = message)
    }
    /**
     * Ending a session stops recognition and clears the conversation but keeps the model resident,
     * so the next Start conversation reaches Ready without loading again. The model is released in
     * [onCleared], when the view model itself goes away.
     */
    private fun endSession() {
        val activeTranscriber = transcriber
        transcriber = null
        activeTranscriber?.destroy()
        mutableState.value = mutableState.value.copy(phase = SessionPhase.Ready, conversationStarted = false, conversations = emptyList(), errorMessage = null, modelLoadProgress = 0f)
    }
    /**
     * Empties the transcript without ending the session: the model stays resident, both language
     * chips stay as they are, the session phase is untouched, and the next turn starts straight
     * away. Guarded by the same rule the drawer row is disabled under, so a late tap on a row that
     * has just become unavailable cannot strand an in-flight bubble.
     */
    private fun clearConversation() {
        val current = mutableState.value
        if (!current.canClearConversation) return
        mutableState.value = current.copy(conversations = emptyList())
    }

    private fun retry() {
        val current = mutableState.value
        when {
            current.phase == SessionPhase.ModelLoadFailed -> applicationContext?.let(::loadModel)
            current.phase == SessionPhase.Error && current.conversationStarted -> {
                mutableState.value = current.copy(phase = SessionPhase.Ready, errorMessage = null)
            }
        }
    }
    override fun onCleared() { transcriber?.destroy(); transcriber = null; translator.close() }
}

/**
 * The sentence a failure shows. A [TranslationFailure] already carries its own, and anything else
 * is a runtime or SDK error this app did not write and cannot translate, so its message is passed
 * through as-is and the generic line stands in when there is none.
 */
private fun Throwable.asUiText(fallback: Int): UiText =
    (this as? TranslationFailure)?.text ?: message?.takeIf { it.isNotBlank() }?.let(UiText::raw) ?: UiText.res(fallback)

private fun listeningPhase(speaker: Speaker) = if (speaker == Speaker.A) SessionPhase.ListeningA else SessionPhase.ListeningB
private fun finalizingPhase(speaker: Speaker) = if (speaker == Speaker.A) SessionPhase.FinalizingA else SessionPhase.FinalizingB
private fun translatingPhase(speaker: Speaker) = if (speaker == Speaker.A) SessionPhase.TranslatingA else SessionPhase.TranslatingB
