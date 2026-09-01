package ai.zetic.realtimetranslate

import org.junit.Assert.assertEquals
import org.junit.Test

/**
 * Reading the platform's per-app locale back into the row's value. The write side is
 * `AppCompatDelegate`, which needs a real application, so it is exercised on a device.
 */
class AppLanguageTest {

    @Test fun `no override reads as System`() {
        assertEquals(AppLanguage.System, AppLanguage.forLanguageTags(null))
        assertEquals(AppLanguage.System, AppLanguage.forLanguageTags(""))
    }

    @Test fun `a region qualified tag still reads as the language this build offers`() {
        assertEquals(AppLanguage.French, AppLanguage.forLanguageTags("fr-FR"))
        assertEquals(AppLanguage.Spanish, AppLanguage.forLanguageTags("es-419"))
        assertEquals(AppLanguage.English, AppLanguage.forLanguageTags("en-US"))
    }

    @Test fun `only the first of a stored list decides, because that is the one in force`() {
        assertEquals(AppLanguage.French, AppLanguage.forLanguageTags("fr,en-US"))
    }

    @Test fun `a language this build no longer offers falls back to System`() {
        assertEquals(AppLanguage.System, AppLanguage.forLanguageTags("de-DE"))
    }

    @Test fun `the three concrete languages are named in their own language, never translated`() {
        assertEquals(UiText.raw("English"), AppLanguage.English.label)
        assertEquals(UiText.raw("Français"), AppLanguage.French.label)
        assertEquals(UiText.raw("Español"), AppLanguage.Spanish.label)
        assertEquals(UiText.res(R.string.app_language_system), AppLanguage.System.label)
    }
}
