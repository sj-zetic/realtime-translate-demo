# Turn Translate MVP Plan

## Goal

Build native Android and iOS apps for one device, where two people explicitly assign their utterances with A or B controls. Each platform uses on-device STT, and Melange SDK `1.10.0` loads `SJ_zetic/Hy-MT2-1.8B` when a session starts to translate finalized source text into the other person's reading language in a chat bubble on a single screen.

## User flow

Everything happens on one screen. There is no separate speaker-setup destination.

1. The main screen opens with a top language bar holding one chip per speaker, a chat transcript area, and the A and B push-to-talk buttons at the bottom. An inline banner asks for microphone and speech-recognition permission when it is missing.
2. A chip shows `<speaker> · <reading language>` and opens in one tap onto a `Reading language` section plus a secondary `Spoken language` section. Defaults are `Automatic` recognition with English for A and Korean for B, so a first session needs one tap on `Start conversation`.
3. Starting the session loads `SJ_zetic/Hy-MT2-1.8B` through Melange SDK `1.10.0`. The same screen reports loading progress or a retryable error in the banner. PTT stays disabled until the model is ready.
4. A or B holds their own button. A tap starts recording and a second tap stops it as an accessibility alternative.
5. Only the active person's partial source text updates. The other button is disabled so exactly one on-device STT session is active.
6. Releasing the button or tapping to stop finalizes the STT source text.
7. A source text is translated serially into B's reading language; B source text is translated serially into A's reading language with Hy-MT2. The translation appears inside the same chat bubble, below a hairline divider.
8. Both languages can be changed mid-session from the same chip without reloading the model. A reading-language change affects future translation prompts only; a recognition-language change applies at the next utterance start. Both speakers' chips lock while an utterance is recording, finalizing, or translating.
9. Ending the session waits for model cleanup and close, clears the prior conversation, and returns the same screen to its idle state with the chips still available.
10. When loading or translation fails, the source text remains visible and the translation area shows an error and retry action instead of a fabricated result.

## Pipeline

`Idle main screen` -> `Load SJ_zetic/Hy-MT2-1.8B` -> `Ready` -> `User-selected A or B button` -> `Platform on-device STT using Automatic or an OS-derived recognition language` -> `Finalized source text` -> `Serial Hy-MT2 translation` -> `Chat bubble in the other person's reading language` -> `End, clean up, close, and clear` -> `Idle main screen`

| Stage | Component | Responsibility |
| --- | --- | --- |
| Speaker assignment | A/B push-to-talk controls | The user explicitly identifies the speaker. |
| Android STT | `SpeechRecognizer.createOnDeviceSpeechRecognizer()` | Produces partial and final on-device source text for the selected speaker. |
| iOS STT | `SFSpeechRecognizer` with `requiresOnDeviceRecognition = true` | Produces partial and final on-device source text for the selected speaker. |
| Translation | Melange SDK `1.10.0` and `SJ_zetic/Hy-MT2-1.8B` | Loads the model once per session and serially translates finalized source text into the other person's reading language. |

STT and Hy-MT2 inference run off the UI thread. Hy-MT2 uses a serial queue that processes one finalized utterance at a time. Session startup loads the model asynchronously and reports progress. If model loading or runtime execution fails, the app shows an error rather than producing a translation. Session end waits for model cleanup and close, then clears the conversation before setup; view-model teardown also releases the model.

## Language scope

- Speaking languages for A and B: `Automatic` or an OS-derived on-device recognition language. Android API 33 and later lists installed on-device recognition locales. Android API 31-32 offers `Automatic` because installed-locale discovery is unavailable. iOS lists only supported locales that are on-device capable. The app does not restrict the source-language list, download speech models, or request online recognition.
- Reading languages for A and B: the 38 official Hy-MT2 options in the [Hy-MT2 translation reference](hy-mt2-integration-reference.md).
- A source text translates only into B's reading language, and B source text translates only into A's reading language. Automatic language detection and special handling for same-language pairs are out of scope.

The app does not preflight or gate a source language. If the platform cannot start the requested on-device recognition session, the app reports the platform error. It never falls back to network STT or automatically downloads a speech model.

## Scope and constraints

- One device does not support simultaneous A/B speech or concurrent STT sessions. The opposite button is disabled while an utterance is active.
- Automatic speaker separation, separate voice models, additional audio fan-out, and persistent storage of audio or conversations are out of scope.
- Accounts, sign-in, cloud sync, export or sharing, and telephone-call recording are out of scope.
- The Melange personal key is supplied as `MELANGE_PERSONAL_KEY` through the build environment. It is absent from source control and logs, but embedded into a development app binary for SDK initialization. That approach is not suitable for production distribution, which requires rotatable credential provisioning. Application and bundle identifiers and iOS signing configuration remain unchanged.

## Completion criteria

- Android and iOS implement the same single-screen information architecture, model-loading gate, single-active PTT behavior, translation after source finalization, session-end unload, and error-recovery meaning.
- Each A/B utterance appears as a chat bubble, left-aligned for A and right-aligned for B, showing the speaker label, source text, target language for the other person, translated text, and processing or error state in chronological order.
- Hold-to-talk and tap-toggle provide the same start/stop outcome and have accessibility labels.
- The reading-language chip matches the 38 official Hy-MT2 entries, and the request builder uses the documented one-user-message prompt.
- Language chips are reachable in one tap from the main screen and can be changed mid-session without reloading the model.
- Starting a session loads `SJ_zetic/Hy-MT2-1.8B` with Melange SDK `1.10.0`; ending a session waits for cleanup and close, clears the prior conversation, and returns the same screen to its idle state.
