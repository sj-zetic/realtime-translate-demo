package ai.zetic.realtimetranslate

import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.zeticai.mlange.core.model.llm.LLMModelMode
import com.zeticai.mlange.core.model.llm.ZeticMLangeLLMModel
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Assume.assumeTrue
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class MelangeHyMt2RuntimeTest {
    @Test fun loads_and_translates_with_the_configured_melange_model() {
        val personalKey = BuildConfig.MELANGE_PERSONAL_KEY
        assumeTrue("MELANGE_PERSONAL_KEY is required for this device-only test.", personalKey.isNotBlank())

        val model = ZeticMLangeLLMModel(
            context = ApplicationProvider.getApplicationContext(),
            personalKey = personalKey,
            name = MelangeHyMt2Translator.MODEL_NAME,
            version = null,
            modelMode = LLMModelMode.RUN_AUTO,
        )
        var primaryFailure: Throwable? = null
        try {
            val prompt = HyMt2TranslationRequestBuilder.build(
                sourceText = "Good morning.",
                targetLanguage = HyMt2Languages.all.first { it.code == "fr" },
            )
            assertTrue("Model run failed.", model.run(prompt).status == 0)
            var completed = false
            val translation = buildString {
                for (attempt in 0 until 256) {
                    val token = model.waitForNextToken()
                    assertTrue("Token generation failed.", token.status == 0)
                    if (token.token.isEmpty()) {
                        completed = true
                        break
                    }
                    append(token.token)
                    if (token.isFinal) {
                        completed = true
                        break
                    }
                }
            }.trim()
            assertTrue("Model did not finish within 256 tokens.", completed)
            assertFalse("Model returned an empty translation.", translation.isEmpty())
        } catch (error: Throwable) {
            primaryFailure = error
            throw error
        } finally {
            val cleanupFailure = runCatching { model.cleanUp() }.exceptionOrNull()
            val closeFailure = runCatching { model.close() }.exceptionOrNull()
            primaryFailure?.let { primary ->
                cleanupFailure?.let(primary::addSuppressed)
                closeFailure?.let(primary::addSuppressed)
            } ?: cleanupFailure?.let { cleanup ->
                closeFailure?.let(cleanup::addSuppressed)
                throw cleanup
            } ?: closeFailure?.let { throw it }
        }
    }
}
