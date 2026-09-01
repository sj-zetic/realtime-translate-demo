# Hy-MT2 Translation Reference

## Source of truth

This reference follows Tencent's official [Hy-MT2-1.8B-GGUF model card](https://huggingface.co/tencent/Hy-MT2-1.8B-GGUF) and the official [Hy-MT2 chat template](https://huggingface.co/tencent/Hy-MT2-1.8B/blob/main/chat_template.jinja).

## Target languages

The A and B reading-language selectors use these 38 entries from the official Supported Languages table. The complete English language name is the value used in the translation prompt.

| Name | Code |
| --- | --- |
| Chinese | `zh` |
| English | `en` |
| French | `fr` |
| Portuguese | `pt` |
| Spanish | `es` |
| Japanese | `ja` |
| Turkish | `tr` |
| Russian | `ru` |
| Arabic | `ar` |
| Korean | `ko` |
| Thai | `th` |
| Italian | `it` |
| German | `de` |
| Vietnamese | `vi` |
| Malay | `ms` |
| Indonesian | `id` |
| Filipino | `tl` |
| Hindi | `hi` |
| Traditional Chinese | `zh-Hant` |
| Polish | `pl` |
| Czech | `cs` |
| Dutch | `nl` |
| Khmer | `km` |
| Burmese | `my` |
| Persian | `fa` |
| Gujarati | `gu` |
| Urdu | `ur` |
| Telugu | `te` |
| Marathi | `mr` |
| Hebrew | `he` |
| Bengali | `bn` |
| Tamil | `ta` |
| Ukrainian | `uk` |
| Tibetan | `bo` |
| Kazakh | `kk` |
| Mongolian | `mn` |
| Uyghur | `ug` |
| Cantonese | `yue` |

## Request contract

The official request is one plain-text `user` message with no system message. Replace `{target_lang}` with the target language's complete English name and `{source_text}` with the finalized STT transcript. The blank line before `{source_text}` is required.

```text
Translate the following text into {target_lang}. Note that you should only output the translated result without any additional explanation:

{source_text}
```

The official GGUF chat template emits a begin-of-sentence token, a user token, the user message, and an assistant generation token. The template can process a system message, but the model card states that the 1.8B model has no default system prompt; this app does not send one.

Turn Translate uses Melange SDK `1.10.0`, whose inference entry point accepts a `String`, not chat messages. The app therefore renders the exact flat prompt below and passes that string to `SJ_zetic/Hy-MT2-1.8B`. Android and iOS must produce byte-equivalent output.

```text
<｜hy_begin▁of▁sentence｜><｜hy_User｜>Translate the following text into {target_lang}. Note that you should only output the translated result without any additional explanation:

{source_text}<｜hy_Assistant｜>
```

## App integration

At session start, the app downloads and loads `SJ_zetic/Hy-MT2-1.8B` through Melange SDK `1.10.0`. A loading state reports progress; a loading or inference failure reports an error with retry and never fabricates a translation. The app serializes translation requests. At session end and view-model teardown, it releases the model with the SDK cleanup and close lifecycle before returning to setup.

`MELANGE_PERSONAL_KEY` is supplied from the build environment and must not appear in source control or logs. It is embedded into a development app binary for SDK initialization; this is unsuitable for production distribution, which requires rotatable credential provisioning. Model selection is fixed to `SJ_zetic/Hy-MT2-1.8B`; the app does not import models or select a GGUF quantization.
