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

    companion object {
        const val FILE_NAME = "turn-translate"
        const val WELCOME_SEEN_KEY = "firstRun.welcomeSeen"
        const val PRIMING_SEEN_KEY = "firstRun.permissionPrimingSeen"
        const val MODEL_LOADED_KEY = "model.hasEverLoaded"
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
    const val APPROXIMATE = "about $TOTAL"
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
 * Every first-run string in one place, in the app's terse voice and with no em dash anywhere.
 * English only at this stage; the French and Spanish passes land with the localization work.
 */
object FirstRunCopy {
    const val PRODUCT_NAME = "Turn Translate"

    const val WELCOME_TAGLINE = "Two people, two languages, one phone."
    const val WELCOME_PRIVACY = "Speech and translation run on this phone. Nothing is sent to a server."
    const val WELCOME_ACTION = "Get started"

    const val PRIMING_TITLE = "Microphone and speech"
    const val PRIMING_MICROPHONE = "Microphone: to hear whoever is holding a button."
    const val PRIMING_SPEECH = "Speech recognition: to turn that audio into text."
    const val PRIMING_PRIVACY = "Both run on this phone. No audio and no text leave the device."
    const val PRIMING_NEXT = "Android asks for the microphone next."
    const val PRIMING_ACTION = "Continue"
    const val PRIMING_DECLINE = "Not now"

    const val CONSENT_TITLE = "Download the translation model"
    const val CONSENT_SIZE = "The translation model is ${ModelDownloadSize.APPROXIMATE}."
    const val CONSENT_ONCE = "It downloads once, then it stays on this phone."
    const val CONSENT_CELLULAR = "You are not on Wi-Fi. A download this large is better on Wi-Fi."
    const val CONSENT_ACTION = "Download now"
    const val CONSENT_DECLINE = "Not now"
}

// endregion
