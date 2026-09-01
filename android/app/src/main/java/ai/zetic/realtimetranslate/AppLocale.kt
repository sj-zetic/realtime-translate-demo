package ai.zetic.realtimetranslate

import androidx.appcompat.app.AppCompatDelegate
import androidx.core.os.LocaleListCompat

/**
 * The app's own language, which is separate from everything else on this screen that says
 * "language": the two chips choose what is *translated*, this chooses what the app is *written in*.
 *
 * The three concrete languages are named in their own language and are never translated, so someone
 * who has put the app into a language they cannot read can still recognize their way back out.
 * Only `System` is a translated word.
 */
enum class AppLanguage(val tag: String?) {
    /** No override: follow the order set in the phone's own settings. */
    System(null),
    English("en"),
    French("fr"),
    Spanish("es");

    val label: UiText
        get() = when (this) {
            System -> UiText.res(R.string.app_language_system)
            English -> UiText.raw("English")
            French -> UiText.raw("Français")
            Spanish -> UiText.raw("Español")
        }

    companion object {
        /**
         * The language a stored per-app locale list means. Only the primary subtag is compared, so
         * a system that stored `fr-FR` still reads as French, and a language this build no longer
         * offers falls back to [System] rather than showing a code nobody chose.
         */
        fun forLanguageTags(tags: String?): AppLanguage {
            val primary = tags?.split(',')
                ?.firstOrNull()
                ?.substringBefore('-')
                ?.lowercase()
                ?.takeIf { it.isNotEmpty() }
                ?: return System
            return entries.firstOrNull { it.tag == primary } ?: System
        }
    }
}

/**
 * Reading and writing the platform's own per-app language.
 *
 * `AppCompatDelegate` rather than a private preference: from Android 13 this is the framework's
 * `LocaleManager`, which is what the phone's own Settings app shows and edits, and below 13 the
 * androidx backport stores and restores the same choice. Choosing `System` clears the override
 * rather than pinning whatever the phone currently is, so a phone that changes its language later
 * is followed instead of frozen.
 */
object AppLanguageStore {
    fun current(): AppLanguage =
        AppLanguage.forLanguageTags(AppCompatDelegate.getApplicationLocales().toLanguageTags())

    /**
     * @return whether anything changed. Choosing the language that is already in force changes
     * nothing and confirms nothing, so the toast never fires on a no-op tap.
     */
    fun apply(language: AppLanguage): Boolean {
        if (current() == language) return false
        AppCompatDelegate.setApplicationLocales(
            language.tag?.let(LocaleListCompat::forLanguageTags) ?: LocaleListCompat.getEmptyLocaleList(),
        )
        return true
    }
}
