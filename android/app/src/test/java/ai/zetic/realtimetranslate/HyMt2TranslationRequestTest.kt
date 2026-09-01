package ai.zetic.realtimetranslate

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class HyMt2TranslationRequestTest {
    @Test
    fun `lists the 38 official target languages with Filipino`() {
        assertEquals(38, HyMt2Languages.all.size)
        assertEquals("Filipino", HyMt2Languages.all.first { it.code == "fil" }.displayName)
        assertTrue(HyMt2Languages.all.none { it.displayName == "Tagalog" })
    }

    @Test
    fun `uses the device recognizer without a fixed source language list`() {
        assertEquals("Automatic (device recognizer)", SpeechLanguage.Automatic.displayName)
    }

    @Test
    fun `maps installed language tags without a fixed whitelist`() {
        val languages = SpeechLanguageCatalogMapping.installed(listOf("fr-FR", "ko-KR", "fr-FR"))
        assertEquals(listOf("French (France)", "Korean (South Korea)"), languages.map { it.displayName })
    }

    @Test
    fun `renders the official one turn chat template`() {
        val prompt = HyMt2TranslationRequestBuilder.build(
            sourceText = "Good morning.",
            targetLanguage = HyMt2Languages.all.first { it.code == "fr" },
        )

        assertEquals("<\uFF5Chy_begin\u2581of\u2581sentence\uFF5C><\uFF5Chy_User\uFF5C>Translate the following text into French. Note that you should only output the translated result without any additional explanation:\n\nGood morning.<\uFF5Chy_Assistant\uFF5C>", prompt)
    }

    @Test
    fun `requires only an on-device recognizer and never creates an online fallback`() {
        assertTrue(OnDeviceRecognitionEligibility.failureFor(30, true, true)?.contains("API 31") == true)
        assertTrue(OnDeviceRecognitionEligibility.failureFor(31, false, true)?.contains("Microphone permission") == true)
        assertTrue(OnDeviceRecognitionEligibility.failureFor(31, true, false)?.contains("will not fall back to online recognition") == true)
        assertEquals(null, OnDeviceRecognitionEligibility.failureFor(31, true, true))
    }
}
