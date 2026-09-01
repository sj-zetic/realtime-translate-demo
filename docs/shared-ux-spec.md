# Shared Android/iOS UX and Design Specification

## Consistency principles

Both platforms use idiomatic Jetpack Compose and SwiftUI controls while preserving the same information architecture, A/B meaning, state transitions, terminology, message semantics, and token values. Platform-native navigation, permission guidance, haptics, and safe-area behavior follow OS conventions.

## Screen structure

1. **Speaker setup**: `Automatic` or an OS-derived on-device recognition language and a reading language for A and B, microphone and speech-recognition permission state, and a `Start session` button.
2. **Model loading**: A model-loading state with progress, failure, and retry. Push-to-talk remains unavailable until `SJ_zetic/Hy-MT2-1.8B` is ready.
3. **Conversation**: A state header, chronologically ordered utterance cards, and A/B push-to-talk buttons at the bottom.
4. **Error guidance**: The affected speaker, language, and cause, with `Try again` or `Open settings` actions.

### Conversation layout

```text
Status header: "Loading model" | "Conversation ready" | "A is speaking" | "Translating"

[ A - Automatic ]              [ B - Device language ]
  Hello                         Hello
  To B: Hello                   To A: Hello

------------------------------------
[ Hold A to talk ] [ Hold B to talk ]
```

- A cards and controls create only A utterances; B cards and controls create only B utterances.
- An A source text identifies `To B: <B reading language>`; a B source text identifies `To A: <A reading language>`.
- The active utterance's partial source text updates only its existing active card. Partial text is never translated.
- While A or B is active, the opposite button is disabled with a textual explanation. Simultaneous recording is not supported.
- Android applies safe-content insets so the header, cards, and PTT controls avoid system bars and gesture areas.

## Shared state transitions

| State | Display | Allowed actions | Next state |
| --- | --- | --- | --- |
| `permissionRequired` | Permission needed | Request permission, open settings | `setup`, `error` |
| `setup` | Language selections and session start | Start session, change language | `modelLoading`, `permissionRequired`, `error` |
| `modelLoading` | Model download and load progress | Wait | `ready`, `modelLoadFailed` |
| `ready` | A/B controls available | Start A or B, end session | `listeningA`, `listeningB`, `modelUnloading` |
| `listeningA` | `A is speaking` and A partial card | Stop A | `finalizingA`, `error` |
| `listeningB` | `B is speaking` and B partial card | Stop B | `finalizingB`, `error` |
| `finalizingA` / `finalizingB` | `Finalizing A/B source text` | Wait for completion | `translatingA`, `translatingB`, `error` |
| `translatingA` / `translatingB` | `Translating for B/A` | Wait for completion | `ready`, `error` |
| `modelUnloading` | Ending session | Wait | Clear the prior conversation after cleanup and close, then enter `setup` |
| `modelLoadFailed` | Model-load failure and retry action | Retry model load | `modelLoading` |
| `error` | Failure cause and recovery action; existing cards remain | Retry, open settings, end session | `ready`, `setup`, `permissionRequired` |

If platform STT reports a final result before the user stops an utterance, the app stores it only as the active card's pending transcript. The app leaves `listening*` for `finalizing*` and starts finalization and translation only after a button release or tap-toggle stop. If there is no finalized source text, no card completes and the app returns to `ready`. A translation error leaves the finalized source card visible and shows an error state in the translation area.

## A/B input and accessibility

- The primary action is push-to-talk: recording lasts while the user holds a button and stops when it is released.
- The same control supports tap-to-start and tap-to-stop as an accessibility alternative. The current interaction is shown as text.
- Accessibility labels include the current action and speaker, such as `Start A utterance`, `Stop A utterance`, `Start B utterance`, and `Stop B utterance`.
- A disabled opposite control exposes equivalent explanatory text, such as `Cannot start B utterance while A utterance is active`.

## On-device STT prerequisites

- The source-language selector is not limited by an app-defined whitelist.
- Android API 33 and later lists installed on-device recognition locales. Android API 31-32 offers `Automatic` because installed-locale discovery is unavailable.
- iOS lists only `SFSpeechRecognizer` supported locales that are on-device capable.
- Android and iOS use on-device recognition only. The app does not download speech models, preflight source-language compatibility, or fall back to online STT. If the platform cannot start recognition, it enters `error` with guidance.

## Translation execution

- A and B reading-language selectors show all 38 options from the [Hy-MT2 translation reference](hy-mt2-integration-reference.md).
- Starting a session asynchronously downloads and loads `SJ_zetic/Hy-MT2-1.8B` through Melange SDK `1.10.0`. Loading failure reports a retryable error and never enables PTT.
- Translation runs only for finalized source text: A translates to B's reading language and B translates to A's reading language.
- The translation request uses the documented flat one-user-message Hy-MT2 prompt, including its blank line and Hy control tokens. Melange accepts that rendered request as a `String`; the app manually renders the required flat template rather than passing a chat-message object. If inference fails, the app preserves the source card and shows an error and recovery action instead of an invented translation or an empty translation bubble.
- Hy-MT2 requests are serial. A queued card displays the recipient and `Translation pending`.
- Ending a session waits for the loaded model to clean up and close, clears the prior conversation, and then returns to target-language setup. View-model teardown also releases the model.
- `MELANGE_PERSONAL_KEY` is supplied through the build environment and must not appear in source control or logs. Development builds embed it for SDK initialization; production distribution requires rotatable credential provisioning.

## Design tokens

| Token | Value | Usage |
| --- | --- | --- |
| `color.primary` | `#3B5BDB` | Primary action and active A button |
| `color.secondary` | `#0B7285` | Active B button |
| `color.surface` | `#FFFFFF` | Default background |
| `color.surfaceMuted` | `#F1F3F5` | Disabled controls and queued cards |
| `color.textPrimary` | `#1F2937` | Body text |
| `color.textSecondary` | `#6B7280` | Supporting text |
| `color.error` | `#C92A2A` | Errors |
| `space.1/2/3/4` | `4/8/12/16 dp/pt` | Shared spacing |
| `radius.message` | `16 dp/pt` | Chat cards |
| `radius.control` | `20 dp/pt` | A/B PTT controls |
| `type.body` | `16 sp/pt` | Source and translated text |
| `type.meta` | `12 sp/pt` | Speaker, status, and target-language text |

Android uses dp/sp and iOS uses pt with Dynamic Type while maintaining the visual size and hierarchy in the table. System dark-mode support is outside MVP scope; do not add forced theme switching.

## Android/iOS parity criteria

| Scenario | Same result on both platforms |
| --- | --- |
| Start A | A partial card and active-A state; B control disabled |
| Start B | B partial card and active-B state; A control disabled |
| Start session | Model progress is visible; PTT remains disabled until model ready |
| Release or tap stop | Final result received before stopping stays pending; after stopping, source text finalizes and translation queues for the other speaker's language |
| Translation succeeds | Source text, target language, and translated text appear in one card |
| STT unsupported or permission denied | Do not start; show cause and recovery action; do not switch to network recognition |
| Model loading or translation fails | Preserve source text when available; do not invent a translation; show a retryable error |
| End session | Wait for model cleanup and close, clear the prior conversation, then return to target-language setup |

## Verification

- Every control has an equivalent accessibility label.
- Body text and state text do not clip or overlap at larger text sizes.
- A/B active state, processing, and errors are distinguished with text and icons in addition to color.
- Android and iOS capture and compare the parity-table scenarios plus setup, conversation, and error screens using the same inputs.
