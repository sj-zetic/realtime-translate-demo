package ai.zetic.realtimetranslate

object HyMt2TranslationRequestBuilder {
    fun build(sourceText: String, targetLanguage: TranslationLanguage): String {
        val instruction = "Translate the following text into ${targetLanguage.displayName}. Note that you should only output the translated result without any additional explanation:\n\n$sourceText"
        return "$BEGIN_OF_SENTENCE$USER$instruction$ASSISTANT"
    }

    private const val BEGIN_OF_SENTENCE = "<\uFF5Chy_begin\u2581of\u2581sentence\uFF5C>"
    private const val USER = "<\uFF5Chy_User\uFF5C>"
    private const val ASSISTANT = "<\uFF5Chy_Assistant\uFF5C>"
}
