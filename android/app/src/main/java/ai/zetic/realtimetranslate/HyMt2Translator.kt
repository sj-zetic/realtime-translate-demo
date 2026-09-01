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
            val loadedModel = checkNotNull(model) { "Translation model is not loaded." }
            try {
                check(loadedModel.run(prompt).status == 0) { "The translation model could not start." }
                buildString {
                    while (true) {
                        val token = loadedModel.waitForNextToken()
                        check(token.status == 0) { "The translation model stopped unexpectedly." }
                        append(token.token)
                        if (token.isFinal || token.token.isEmpty()) break
                    }
                }.trim().ifEmpty { error("The translation model returned no text.") }
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
