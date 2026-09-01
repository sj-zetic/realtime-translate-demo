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

    @Test fun `no first-run string contains an em dash or an en dash`() {
        val strings = listOf(
            FirstRunCopy.PRODUCT_NAME, FirstRunCopy.WELCOME_TAGLINE, FirstRunCopy.WELCOME_PRIVACY,
            FirstRunCopy.WELCOME_ACTION, FirstRunCopy.PRIMING_TITLE, FirstRunCopy.PRIMING_MICROPHONE,
            FirstRunCopy.PRIMING_SPEECH, FirstRunCopy.PRIMING_PRIVACY, FirstRunCopy.PRIMING_NEXT,
            FirstRunCopy.PRIMING_ACTION, FirstRunCopy.PRIMING_DECLINE, FirstRunCopy.CONSENT_TITLE,
            FirstRunCopy.CONSENT_SIZE, FirstRunCopy.CONSENT_ONCE, FirstRunCopy.CONSENT_CELLULAR,
            FirstRunCopy.CONSENT_ACTION, FirstRunCopy.CONSENT_DECLINE,
            SettingsDrawerCopy.TITLE, SettingsDrawerCopy.CLOSE, SettingsDrawerCopy.CLEAR_TITLE,
            SettingsDrawerCopy.CLEAR_SUBTITLE, SettingsDrawerCopy.CLEAR_CONFIRMATION,
            SettingsDrawerCopy.WEBSITE_TITLE, SettingsDrawerCopy.CONTACT_TITLE,
            SettingsDrawerCopy.COPY_CONFIRMATION, SettingsDrawerCopy.BUBBLE_COPY_ACTION,
            SettingsDrawerCopy.BUBBLE_COPY_CONFIRMATION, SettingsDrawerCopy.ABOUT_TITLE,
            SettingsDrawerCopy.PRIVACY_LINE, SettingsDrawerCopy.WEBSITE_ACCESSIBILITY,
            SettingsDrawerCopy.CONTACT_ACCESSIBILITY,
            SettingsDrawerCopy.clearAccessibilityLabel(true), SettingsDrawerCopy.clearAccessibilityLabel(false),
        )

        strings.forEach { value ->
            assertFalse("`$value` contains an em dash", value.contains('—'))
            assertFalse("`$value` contains an en dash", value.contains('–'))
        }
    }

    @Test fun `about 1_9 GB is the only size wording`() {
        assertEquals("about 1.9 GB", ModelDownloadSize.APPROXIMATE)
        assertTrue(FirstRunCopy.CONSENT_SIZE.contains("about 1.9 GB"))
    }

    @Test fun `the About block reads the version pair as one terse line`() {
        assertEquals("Version 0.1.0 (1)", AppInfo("Turn Translate", "0.1.0", "1").versionLine)
    }

    // endregion
}
