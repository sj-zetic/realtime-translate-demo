package ai.zetic.realtimetranslate

import android.content.Context
import android.net.ConnectivityManager

/**
 * Everything the first run of Turn Translate needs to decide what to show and when: the remembered
 * flags, the step they imply, the model-download consent decision, and the copy the first-run
 * surfaces render. Kept out of the composables so every decision is testable without UI.
 *
 * The flow is three steps, each shown at most once and each skipped silently when it has nothing
 * to say: the welcome, the permission priming that precedes the system prompt, and the download
 * consent that precedes a genuine 1.9 GB transfer.
 */

// region Remembered flags

/**
 * The app's one preference file. `SharedPreferences` rather than DataStore: the app stores three
 * booleans read synchronously on the first frame, and a DataStore dependency plus a suspending
 * first read would buy nothing here.
 *
 * The two first-run keys are spelled exactly as the iOS `@AppStorage` keys, so the two platforms
 * can be reasoned about as one contract.
 */
class FirstRunPreferences(context: Context) {
    private val preferences =
        context.applicationContext.getSharedPreferences(FILE_NAME, Context.MODE_PRIVATE)

    var welcomeSeen: Boolean
        get() = preferences.getBoolean(WELCOME_SEEN_KEY, false)
        set(value) = preferences.edit().putBoolean(WELCOME_SEEN_KEY, value).apply()

    var permissionPrimingSeen: Boolean
        get() = preferences.getBoolean(PRIMING_SEEN_KEY, false)
        set(value) = preferences.edit().putBoolean(PRIMING_SEEN_KEY, value).apply()

    /**
     * Stands in for "a complete model is on disk". The Melange Android SDK exposes no read-only way
     * to ask whether `SJ_zetic/Hy-MT2-1.8B` is already cached, so the honest approximation is to
     * remember that a load has succeeded at least once on this install. The one case it gets wrong
     * is a user who clears app data or storage without uninstalling: they are asked to consent to a
     * download that is genuinely about to happen, which is the safe direction to be wrong in.
     */
    var hasEverLoadedModel: Boolean
        get() = preferences.getBoolean(MODEL_LOADED_KEY, false)
        set(value) = preferences.edit().putBoolean(MODEL_LOADED_KEY, value).apply()

    /**
     * Whether spoken translation is off. Default is sound on, and the key is spelled exactly as the
     * iOS `@AppStorage` key. Read on the first frame rather than after it, so a launch that starts
     * muted never speaks before the screen appears.
     *
     * The app language is deliberately not here: that one is written to the platform's own per-app
     * locale, which the phone's Settings app shows and edits too.
     */
    var speechMuted: Boolean
        get() = preferences.getBoolean(SPEECH_MUTED_KEY, false)
        set(value) = preferences.edit().putBoolean(SPEECH_MUTED_KEY, value).apply()

    companion object {
        const val FILE_NAME = "turn-translate"
        const val WELCOME_SEEN_KEY = "firstRun.welcomeSeen"
        const val PRIMING_SEEN_KEY = "firstRun.permissionPrimingSeen"
        const val MODEL_LOADED_KEY = "model.hasEverLoaded"
        const val SPEECH_MUTED_KEY = "speech.muted"
    }
}

/** Which first-run surface belongs on screen before the main screen becomes usable. */
enum class FirstRunStep {
    None,
    Welcome,
    PermissionPriming;

    companion object {
        /**
         * The welcome always comes first. The priming follows only while the system prompt is still
         * unanswered: a returning user who already granted access skips it silently.
         */
        fun step(welcomeSeen: Boolean, primingSeen: Boolean, permissionNeeded: Boolean): FirstRunStep = when {
            !welcomeSeen -> Welcome
            !primingSeen && permissionNeeded -> PermissionPriming
            else -> None
        }
    }
}

// endregion

// region Network cost and consent

/**
 * What the current network path costs. Android answers one question rather than iOS's two:
 * `isActiveNetworkMetered` already folds cellular, metered Wi-Fi, and a metered hotspot together,
 * and either way the consent card says the same sentence.
 */
object NetworkCost {
    fun isMetered(context: Context): Boolean {
        val manager = context.applicationContext
            .getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager ?: return false
        return runCatching { manager.isActiveNetworkMetered }.getOrDefault(false)
    }
}

object ModelDownloadSize {
    /** A byte size, not a sentence. User-facing copy always hedges it as "about 1.9 GB". */
    const val TOTAL = "1.9 GB"
}

/**
 * Whether starting a session has to ask first. A model already on this phone loads locally in
 * seconds with no network at all, so the consent step exists only for a genuine first download.
 */
object ModelDownloadConsent {
    sealed interface Decision {
        data object StartImmediately : Decision
        data class Ask(val cellularWarning: Boolean) : Decision
    }

    /**
     * A build with no Melange personal key cannot download anything, so offering `Download now`
     * would promise a transfer that ends a frame later in the missing-key failure. The start runs
     * instead, and the load reports that failure where every other model failure is reported: the
     * session banner, with its retry.
     */
    fun decision(hasLocalModel: Boolean, isMetered: Boolean, hasPersonalKey: Boolean = true): Decision =
        if (hasLocalModel || !hasPersonalKey) Decision.StartImmediately else Decision.Ask(isMetered)
}

// endregion

// region Copy

/**
 * The words the app never translates, held as constants so nothing can localize them by accident.
 * Every other string the first run shows now lives in `res/values/strings.xml` and reaches the
 * surfaces as a resource, so the French and Spanish passes cover them without touching this file.
 */
object FirstRunCopy {
    const val PRODUCT_NAME = "Turn Translate"
}

/** The consent card's one composed sentence: a translated frame around a hedged, formatted size. */
val ConsentSizeLine: UiText
    get() = UiText.res(
        R.string.first_run_consent_size,
        UiText.res(R.string.model_size_approximate, ModelDownloadSize.TOTAL),
    )

// endregion
