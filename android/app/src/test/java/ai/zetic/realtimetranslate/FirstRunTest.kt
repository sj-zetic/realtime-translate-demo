package ai.zetic.realtimetranslate

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/** The first-run decisions: which step belongs on screen, and whether a start has to ask first. */
class FirstRunTest {

    // region Step selection

    @Test fun `a brand new install opens on the welcome`() {
        assertEquals(
            FirstRunStep.Welcome,
            FirstRunStep.step(welcomeSeen = false, primingSeen = false, permissionNeeded = true),
        )
    }

    @Test fun `the welcome comes first even when permission is already granted`() {
        assertEquals(
            FirstRunStep.Welcome,
            FirstRunStep.step(welcomeSeen = false, primingSeen = false, permissionNeeded = false),
        )
    }

    @Test fun `the priming follows the welcome while the system prompt is unanswered`() {
        assertEquals(
            FirstRunStep.PermissionPriming,
            FirstRunStep.step(welcomeSeen = true, primingSeen = false, permissionNeeded = true),
        )
    }

    @Test fun `the priming is skipped silently when permission is already granted`() {
        assertEquals(
            FirstRunStep.None,
            FirstRunStep.step(welcomeSeen = true, primingSeen = false, permissionNeeded = false),
        )
    }

    @Test fun `a returning user sees no first-run surface at all`() {
        assertEquals(
            FirstRunStep.None,
            FirstRunStep.step(welcomeSeen = true, primingSeen = true, permissionNeeded = true),
        )
    }

    // endregion

    // region Download consent

    @Test fun `a first start with no model on this phone asks first`() {
        assertEquals(
            ModelDownloadConsent.Decision.Ask(cellularWarning = false),
            ModelDownloadConsent.decision(hasLocalModel = false, isMetered = false),
        )
    }

    @Test fun `a metered network adds the Wi-Fi warning to the same card`() {
        assertEquals(
            ModelDownloadConsent.Decision.Ask(cellularWarning = true),
            ModelDownloadConsent.decision(hasLocalModel = false, isMetered = true),
        )
    }

    @Test fun `a model already on this phone starts straight away, metered or not`() {
        assertEquals(
            ModelDownloadConsent.Decision.StartImmediately,
            ModelDownloadConsent.decision(hasLocalModel = true, isMetered = false),
        )
        assertEquals(
            ModelDownloadConsent.Decision.StartImmediately,
            ModelDownloadConsent.decision(hasLocalModel = true, isMetered = true),
        )
    }

    @Test fun `a build with no personal key never offers a download it cannot make`() {
        assertEquals(
            ModelDownloadConsent.Decision.StartImmediately,
            ModelDownloadConsent.decision(hasLocalModel = false, isMetered = true, hasPersonalKey = false),
        )
    }

    // endregion

    // region Copy

    // The em dash rule now covers every string in every language rather than the constants this
    // file used to list, and lives in LocalizationCatalogTest, which reads the catalog off disk.

    @Test fun `the words the app never translates stay constants rather than catalog entries`() {
        assertEquals("Turn Translate", FirstRunCopy.PRODUCT_NAME)
        assertEquals("contact@zetic.ai", SettingsDrawerCopy.CONTACT_EMAIL)
        assertEquals("https://zetic.ai", SettingsDrawerCopy.WEBSITE)
    }

    @Test fun `the size is hedged by a translated frame around one untranslated figure`() {
        assertEquals("1.9 GB", ModelDownloadSize.TOTAL)
        assertEquals(
            UiText.res(
                R.string.first_run_consent_size,
                UiText.res(R.string.model_size_approximate, ModelDownloadSize.TOTAL),
            ),
            ConsentSizeLine,
        )
    }

    @Test fun `the About block reads the version pair as one terse line`() {
        assertEquals(
            UiText.res(R.string.about_version_line, "0.1.0", "1"),
            AppInfo("Turn Translate", "0.1.0", "1").versionLine,
        )
    }

    @Test fun `the clear row's accessibility label is built from the row's own title`() {
        assertEquals(
            UiText.res(R.string.settings_clear_accessibility_available, UiText.res(R.string.settings_clear_title)),
            SettingsDrawerCopy.clearAccessibilityLabel(isEnabled = true),
        )
        assertEquals(
            UiText.res(R.string.settings_clear_accessibility_unavailable, UiText.res(R.string.settings_clear_title)),
            SettingsDrawerCopy.clearAccessibilityLabel(isEnabled = false),
        )
    }

    // endregion
}
