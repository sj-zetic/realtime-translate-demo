package ai.zetic.realtimetranslate

import android.content.Context
import com.zeticai.mlange.core.model.llm.LLMModelMode
import com.zeticai.mlange.core.model.llm.LLMNextTokenResult
import com.zeticai.mlange.core.model.llm.LLMRunResult
import com.zeticai.mlange.core.model.llm.ZeticMLangeLLMModel
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext

/**
 * A translation that could not be produced, carrying the sentence the banner or the bubble shows.
 *
 * The runtime's own failures are the only user-facing strings the Melange boundary produces, so
 * they travel as [UiText] like every other one rather than as an English exception message the view
 * model would have to pass through untranslated.
 */
class TranslationFailure(val text: UiText) : IllegalStateException(text.toString())

interface HyMt2Translator {
    suspend fun load(context: Context, onProgress: (Float) -> Unit)
    suspend fun translate(prompt: String): String
    suspend fun unload() = close()
    fun close()
}

interface HyMt2ModelSession {
    fun run(prompt: String): LLMRunResult
    fun waitForNextToken(): LLMNextTokenResult
    fun cleanUp()
    fun close()
}

class MelangeHyMt2Translator(
    private val personalKey: String,
    private val createModel: (Context, (Float) -> Unit) -> HyMt2ModelSession = { context, onProgress ->
        ZeticHyMt2ModelSession(
            ZeticMLangeLLMModel(
                context = context,
                personalKey = personalKey,
                name = MODEL_NAME,
                version = null,
                modelMode = LLMModelMode.RUN_AUTO,
                onDownload = onProgress,
            ),
        )
    },
) : HyMt2Translator {
    private val inferenceMutex = Mutex()
    private var model: HyMt2ModelSession? = null

    override suspend fun load(context: Context, onProgress: (Float) -> Unit) = withContext(Dispatchers.IO) {
        inferenceMutex.withLock {
            if (model == null) model = createModel(context.applicationContext, onProgress)
        }
    }

    override suspend fun translate(prompt: String): String = withContext(Dispatchers.IO) {
        inferenceMutex.withLock {
            val loadedModel = model ?: throw TranslationFailure(UiText.res(R.string.error_model_not_loaded))
            try {
                if (loadedModel.run(prompt).status != 0) {
                    throw TranslationFailure(UiText.res(R.string.error_model_start_failed))
                }
                buildString {
                    while (true) {
                        val token = loadedModel.waitForNextToken()
                        if (token.status != 0) throw TranslationFailure(UiText.res(R.string.error_model_stopped))
                        append(token.token)
                        if (token.isFinal || token.token.isEmpty()) break
                    }
                }.trim().ifEmpty { throw TranslationFailure(UiText.res(R.string.error_model_empty_result)) }
            } finally {
                loadedModel.cleanUp()
            }
        }
    }

    override suspend fun unload() = withContext(Dispatchers.IO) {
        inferenceMutex.withLock { releaseLoadedModel() }
    }

    override fun close() = runBlocking {
        inferenceMutex.withLock { releaseLoadedModel() }
    }

    private fun releaseLoadedModel() {
        val loadedModel = model ?: return
        model = null
        try {
            runCatching { loadedModel.cleanUp() }
        } finally {
            loadedModel.close()
        }
    }

    companion object {
        const val MODEL_NAME = "SJ_zetic/Hy-MT2-1.8B"
    }
}

private class ZeticHyMt2ModelSession(private val model: ZeticMLangeLLMModel) : HyMt2ModelSession {
    override fun run(prompt: String) = model.run(prompt)
    override fun waitForNextToken() = model.waitForNextToken()
    override fun cleanUp() = model.cleanUp()
    override fun close() = model.close()
}
