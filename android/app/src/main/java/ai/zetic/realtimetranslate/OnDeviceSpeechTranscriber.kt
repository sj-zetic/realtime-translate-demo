package ai.zetic.realtimetranslate

import android.content.Context
import android.content.pm.PackageManager
import android.content.Intent
import android.os.Build
import android.os.Looper
import android.speech.RecognitionListener
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import android.speech.RecognitionSupport
import android.speech.RecognitionSupportCallback
import java.util.Locale

interface SpeechTranscriber {
    fun start(language: SpeechLanguage, listener: SpeechTranscriptListener): SpeechStartResult
    fun stop()
    fun destroy()
}

interface SpeechTranscriptListener {
    fun onReady()
    fun onPartial(transcript: String)
    fun onFinal(transcript: String)
    fun onStopped()
    fun onError(message: String)
}

sealed interface SpeechStartResult {
    data object Started : SpeechStartResult
    data class Failed(val message: String) : SpeechStartResult
}

/** Android's platform recognizer is used exclusively; online recognizer fallback is never created. */
class AndroidOnDeviceSpeechTranscriber(
    private val context: Context,
    private val platform: OnDeviceSpeechRecognizerPlatform = AndroidOnDeviceSpeechRecognizerPlatform,
) : SpeechTranscriber {
    private var recognizer: SpeechRecognizer? = null
    private var activeListener: SpeechTranscriptListener? = null
    private var listening = false
    private var stopping = false
    private var destroyed = false

    override fun start(language: SpeechLanguage, listener: SpeechTranscriptListener): SpeechStartResult {
        if (Looper.myLooper() != Looper.getMainLooper()) {
            return SpeechStartResult.Failed("On-device speech recognition must start on the Android main thread.")
        }
        OnDeviceRecognitionEligibility.failureFor(
            sdkInt = Build.VERSION.SDK_INT,
            hasRecordAudioPermission = context.checkSelfPermission(android.Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED,
            isOnDeviceRecognizerAvailable = platform.isOnDeviceRecognitionAvailable(context),
        )?.let { return SpeechStartResult.Failed(it) }

        destroyed = false
        stopping = false
        activeListener = listener
        val intent = OnDeviceRecognitionIntentFactory.create(language, Build.VERSION.SDK_INT)
        val onDeviceRecognizer = platform.createOnDeviceSpeechRecognizer(context)
        recognizer = onDeviceRecognizer.apply { setRecognitionListener(listener(intent)) }
        beginListening(intent)
        return SpeechStartResult.Started
    }

    override fun stop() {
        if (Looper.myLooper() != Looper.getMainLooper()) return
        listening = false
        stopping = true
        recognizer?.stopListening()
    }

    override fun destroy() {
        if (Looper.myLooper() != Looper.getMainLooper()) return
        listening = false
        activeListener = null
        recognizer?.destroy()
        recognizer = null
        destroyed = true
    }

    private fun beginListening(intent: Intent) {
        if (!destroyed && recognizer != null) {
            listening = true
            stopping = false
            recognizer?.startListening(intent)
        }
    }

    private fun listener(intent: Intent) = object : RecognitionListener {
        override fun onReadyForSpeech(params: android.os.Bundle?) {
            activeListener?.onReady()
        }
        override fun onBeginningOfSpeech() = Unit
        override fun onRmsChanged(rmsdB: Float) = Unit
        override fun onBufferReceived(buffer: ByteArray?) = Unit
        override fun onEndOfSpeech() = Unit
        override fun onError(error: Int) {
            if (stopping) {
                activeListener?.onStopped()
            } else if (listening) {
                activeListener?.onError("On-device speech recognition failed (error $error).")
            }
        }
        override fun onResults(results: android.os.Bundle?) {
            results?.transcript()?.let { activeListener?.onFinal(it) }
            if (stopping) activeListener?.onStopped() else if (listening) beginListening(intent)
        }
        override fun onPartialResults(partialResults: android.os.Bundle?) {
            partialResults?.transcript()?.let { activeListener?.onPartial(it) }
        }
        override fun onEvent(eventType: Int, params: android.os.Bundle?) = Unit
    }

}

object OnDeviceRecognitionIntentFactory {
    fun create(language: SpeechLanguage, sdkInt: Int) = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
        putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, true)
        putExtra(RecognizerIntent.EXTRA_PREFER_OFFLINE, true)
        if (language is SpeechLanguage.Installed) putExtra(RecognizerIntent.EXTRA_LANGUAGE, language.languageTag)
        if (language is SpeechLanguage.Automatic && sdkInt >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            putExtra(RecognizerIntent.EXTRA_ENABLE_LANGUAGE_DETECTION, true)
        }
    }
}

interface SpeechLanguageCatalog {
    fun load(context: Context, onResult: (SpeechLanguageCatalogResult) -> Unit)
}

data class SpeechLanguageCatalogResult(val languages: List<SpeechLanguage>, val message: String? = null)

object AndroidSpeechLanguageCatalog : SpeechLanguageCatalog {
    override fun load(context: Context, onResult: (SpeechLanguageCatalogResult) -> Unit) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) {
            onResult(SpeechLanguageCatalogResult(listOf(SpeechLanguage.Automatic)))
            return
        }
        if (!AndroidOnDeviceSpeechRecognizerPlatform.isOnDeviceRecognitionAvailable(context)) {
            onResult(SpeechLanguageCatalogResult(listOf(SpeechLanguage.Automatic), "This device has no on-device speech recognizer."))
            return
        }
        val recognizer = AndroidOnDeviceSpeechRecognizerPlatform.createOnDeviceSpeechRecognizer(context)
        recognizer.checkRecognitionSupport(
            OnDeviceRecognitionIntentFactory.create(SpeechLanguage.Automatic, Build.VERSION.SDK_INT),
            context.mainExecutor,
            object : RecognitionSupportCallback {
                override fun onSupportResult(support: RecognitionSupport) {
                    val languages = SpeechLanguageCatalogMapping.installed(support.installedOnDeviceLanguages)
                    recognizer.destroy()
                    onResult(SpeechLanguageCatalogResult(listOf(SpeechLanguage.Automatic) + languages))
                }
                override fun onError(error: Int) {
                    recognizer.destroy()
                    onResult(SpeechLanguageCatalogResult(listOf(SpeechLanguage.Automatic), "Installed on-device language list is unavailable (error $error)."))
                }
            },
        )
    }

}

object SpeechLanguageCatalogMapping {
    fun installed(tags: List<String>): List<SpeechLanguage.Installed> = tags.map(::installedLanguage).distinctBy { it.languageTag }.sortedBy { it.displayName }

    private fun installedLanguage(tag: String): SpeechLanguage.Installed {
        val locale = Locale.forLanguageTag(tag)
        return SpeechLanguage.Installed(tag, locale.getDisplayName(Locale.ENGLISH).ifBlank { tag })
    }
}

/**
 * The installed recognizer language matching a reading language: same primary language subtag,
 * preferring the variant that code most likely implies (`fr` picks `fr-FR` over `fr-BE`, `zh-Hant`
 * picks `zh-TW`). A language with no installed recognizer has no match, and the caller leaves the
 * spoken language alone.
 */
object SpokenLanguageMatching {
    fun match(reading: TranslationLanguage, available: List<SpeechLanguage>): SpeechLanguage.Installed? {
        val primary = primarySubtag(reading.code) ?: return null
        val matches = available.filterIsInstance<SpeechLanguage.Installed>()
            .filter { primarySubtag(it.languageTag) == primary }
        if (matches.size <= 1) return matches.firstOrNull()
        val implied = variantSubtags(reading.code) + likelyVariants.getOrElse(reading.code) { emptySet() }
        return matches.firstOrNull { candidate ->
            variantSubtags(candidate.languageTag).any(implied::contains)
        } ?: matches.first()
    }

    private fun primarySubtag(tag: String): String? =
        Locale.forLanguageTag(tag).language.takeIf { it.isNotEmpty() }

    /** Everything after the primary subtag, upper-cased so `Hant` and `HANT` compare equal. */
    private fun variantSubtags(tag: String): Set<String> =
        tag.split('-', '_').drop(1).filter(String::isNotEmpty).map { it.uppercase(Locale.ROOT) }.toSet()

    /**
     * The variant a bare reading code implies, for the Hy-MT2 languages a device plausibly carries
     * more than one recognizer for. Everything else resolves on the primary subtag alone.
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

interface OnDeviceSpeechRecognizerPlatform {
    fun isOnDeviceRecognitionAvailable(context: Context): Boolean
    fun createOnDeviceSpeechRecognizer(context: Context): SpeechRecognizer
}

object AndroidOnDeviceSpeechRecognizerPlatform : OnDeviceSpeechRecognizerPlatform {
    override fun isOnDeviceRecognitionAvailable(context: Context): Boolean =
        Build.VERSION.SDK_INT >= Build.VERSION_CODES.S && SpeechRecognizer.isOnDeviceRecognitionAvailable(context)

    @android.annotation.TargetApi(Build.VERSION_CODES.S)
    override fun createOnDeviceSpeechRecognizer(context: Context): SpeechRecognizer =
        SpeechRecognizer.createOnDeviceSpeechRecognizer(context)
}

object OnDeviceRecognitionEligibility {
    fun failureFor(sdkInt: Int, hasRecordAudioPermission: Boolean, isOnDeviceRecognizerAvailable: Boolean): String? = when {
        sdkInt < Build.VERSION_CODES.S -> "This device requires Android 12 (API 31) or later for on-device speech recognition."
        !hasRecordAudioPermission -> "Microphone permission is required."
        !isOnDeviceRecognizerAvailable -> "This device has no on-device speech recognizer. The app will not fall back to online recognition."
        else -> null
    }
}

private fun android.os.Bundle.transcript(): String? =
    getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)?.firstOrNull()?.trim()?.takeIf(String::isNotEmpty)
