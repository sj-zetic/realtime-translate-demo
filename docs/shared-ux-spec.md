# Shared Android/iOS UX and Design Specification

## Consistency principles

Both platforms use idiomatic Jetpack Compose and SwiftUI controls while preserving the same information architecture, A/B meaning, state transitions, terminology, message semantics, and token values. Platform-native navigation, permission guidance, haptics, and safe-area behavior follow OS conventions.

## Screen structure

Turn Translate is a single screen. Setup, model loading, conversation, and error guidance are regions of that one screen instead of separate destinations, so a first session costs one tap when permissions are granted and the default languages are acceptable.

1. **Header**: The app name `Turn Translate` on the leading edge and the `ZETIC` wordmark on the trailing edge of the same row, with the current session state as text below. Android renders both in a header row; iOS puts the title and the wordmark in the navigation bar. The wordmark is the official ZETIC logo lockup, shipped as `res/drawable-nodpi/zetic_logo.png` on Android and the `ZeticLogo` image set in `Sources/Assets.xcassets` on iOS, rendered at 16 dp/pt tall.
2. **Language bar**: One compact chip per speaker directly under the status strip. Speaker A's chip is left-aligned and speaker B's chip is right-aligned, mirroring the side that speaker's chat bubbles appear on. Each chip reads `<speaker> · <reading language>`. Choosing a reading language also re-aligns that speaker's spoken (recognition) language to the matching recognizer when one exists, so the chip is the single source of truth: a speaker shown as Korean is listened to in Korean. The spoken-language picker stays available as an explicit override until the reading language changes again.
3. **Session banner**: An inline region that appears only when the session needs attention: permission request, model-loading progress, model-load failure and retry, session unloading, or a runtime error with its recovery action. Push-to-talk stays unavailable until `SJ_zetic/Hy-MT2-1.8B` is ready.
4. **Conversation**: Chronologically ordered chat bubbles. Speaker A is left-aligned and speaker B is right-aligned. The newest bubble is scrolled into view.
5. **Push-to-talk row**: The A and B controls side by side at the bottom, A on the left and B on the right. The controls carry the A/B identity; there are no separate speaker labels or chips down here.
6. **Session action**: `Start conversation` before the model is loaded, `End session` while a session is live.

### Screen layout

```text
Turn Translate                              ZETIC
Conversation ready
------------------------------------
 [ A · English ]              [ B · Korean ]
------------------------------------
[ inline banner: permission / model progress / failure + retry / error ]
------------------------------------
 Speaker A
 Hello
 --------------
 To B - English
 Hello
                            Speaker B
                            Bonjour
                            --------------
                            To A - Korean
                            Bonjour
------------------------------------
 [ A - hold to talk  ]        [ B - hold to talk  ]
 Hold a button to talk, or tap once to start and again to stop.
 [ End session ]
```

- A bubbles and the A chip and control create only A utterances; B bubbles and the B chip and control create only B utterances.
- Alignment plus the `Speaker A` / `Speaker B` label carries the A/B distinction; the per-speaker tint (A teal `#E9F7F5`, B ink `#F0F0F0`) and the colored mini-label are redundant reinforcement, never the only signal.
- An A bubble identifies `To B - <B reading language>`; a B bubble identifies `To A - <A reading language>`.
- The active utterance's partial source text updates only its existing active bubble. Partial text is never translated.
- While A or B is active, the opposite button is disabled with a textual explanation. Simultaneous recording is not supported.
- Android applies safe-content insets and iOS uses a bottom safe-area inset so the status strip, bubbles, and push-to-talk row avoid system bars and gesture areas.

## Language selection on the main screen

- Each speaker has exactly one chip in the top language bar. One tap opens that speaker's menu, which carries two sections: `Reading language` (the 38 Hy-MT2 entries, the primary list) and `Spoken language` (`Automatic` plus the OS-derived on-device recognition locales). Android renders the sections as labelled groups separated by a divider in a `DropdownMenu`; iOS renders two inline `Picker`s inside one `Menu`.
- The chip face shows only the reading language, because that is the setting people actually change. The `A ·` / `B ·` prefix is tinted in that speaker's deep color and the chip border uses that speaker's border token. The recognition language stays reachable in the same menu and is announced in the chip's accessibility label.
- Chips render `Automatic` in short form; the menu entries keep the platform's full display name (Android shows `Automatic (device recognizer)` there).
- Languages can be changed before, between, and during a session without reloading the model. A reading-language change affects future translation prompts only. A recognition-language change applies at the next utterance start.
- Both speakers' chips are locked while any utterance is recording, finalizing, or translating, and while the model is loading or unloading. Locking both, rather than only the active speaker's, keeps an in-flight utterance's target language stable.
- Defaults are English and Korean reading languages with recognition aligned to each (falling back to `Automatic` when no matching recognizer exists), so the first session needs no language taps.

## Shared state transitions

The `setup` and `ready` states now render on the same screen: `setup` is the idle main screen with push-to-talk locked and `Start conversation` offered, and `ready` is the live main screen with push-to-talk unlocked and `End session` offered. No state was removed or merged.

| State | Display on the main screen | Allowed actions | Next state |
| --- | --- | --- | --- |
| `permissionRequired` | Permission banner; push-to-talk locked | Request permission, open settings, change languages | `setup`, `error` |
| `setup` | Idle screen; `Start conversation`; push-to-talk locked | Start session, change language | `modelLoading`, `permissionRequired`, `error` |
| `modelLoading` | Progress banner; push-to-talk and chips locked | Wait | `ready`, `modelLoadFailed` |
| `ready` | Live screen; A/B controls available; `End session` | Start A or B, end session, change language | `listeningA`, `listeningB`, `modelUnloading` |
| `listeningA` | `Speaker A is speaking`, active A bubble, accent-filled A control | Stop A | `finalizingA`, `error` |
| `listeningB` | `Speaker B is speaking`, active B bubble, accent-filled B control | Stop B | `finalizingB`, `error` |
| `finalizingA` / `finalizingB` | `Finalizing speaker A/B transcript` | Wait for completion | `translatingA`, `translatingB`, `error` |
| `translatingA` / `translatingB` | `Translating for speaker B/A` | Wait for completion | `ready`, `error` |
| `modelUnloading` | Unloading banner | Wait | Clear the prior conversation after cleanup and close, then enter `setup` on the same screen |
| `modelLoadFailed` | Failure banner with `Retry model load` | Retry model load | `modelLoading` |
| `error` | Error banner with the cause and a recovery action; existing bubbles remain | Retry, open settings, end session | `ready`, `setup`, `permissionRequired` |

If platform STT reports a final result before the user stops an utterance, the app stores it only as the active bubble's pending transcript. The app leaves `listening*` for `finalizing*` and starts finalization and translation only after a button release or tap-toggle stop. If there is no finalized source text, no bubble completes and the app returns to `ready`. A translation error leaves the finalized source bubble visible and shows an error state in the translation area.

## A/B input and accessibility

- The primary action is push-to-talk: recording lasts while the user holds a button and stops when it is released.
- The same control supports tap-to-start and tap-to-stop as an accessibility alternative. The current interaction is shown as text.
- Accessibility labels include the current action and speaker, such as `Start speaker A` / `Start A Turn`, `Stop speaker A` / `End A Turn`, and the B equivalents.
- A disabled opposite control exposes equivalent explanatory text, such as `Speaker B cannot start while speaker A is active`. A control disabled because no model is loaded explains that instead.
- Every language chip announces both selections for its speaker, such as `Speaker A languages: reads English, speaks Automatic`.
- No decorative icons are used. State, speaker, and errors are carried by text, alignment, and layout, so the single accent color is never the only signal.

## On-device STT prerequisites

- The source-language selector is not limited by an app-defined whitelist.
- Android API 33 and later lists installed on-device recognition locales. Android API 31-32 offers `Automatic` because installed-locale discovery is unavailable.
- iOS lists only `SFSpeechRecognizer` supported locales that are on-device capable.
- Android and iOS use on-device recognition only. The app does not download speech models, preflight source-language compatibility, or fall back to online STT. If the platform cannot start recognition, it enters `error` with guidance.

## Translation execution

- The `Reading language` section of each speaker's chip menu shows all 38 options from the [Hy-MT2 translation reference](hy-mt2-integration-reference.md).
- Starting a session asynchronously downloads and loads `SJ_zetic/Hy-MT2-1.8B` through Melange SDK `1.10.0`. Loading failure reports a retryable error and never enables PTT.
- Translation runs only for finalized source text: A translates to B's reading language and B translates to A's reading language.
- The translation request uses the documented flat one-user-message Hy-MT2 prompt, including its blank line and Hy control tokens. Melange accepts that rendered request as a `String`; the app manually renders the required flat template rather than passing a chat-message object. If inference fails, the app preserves the source bubble and shows an error and recovery action instead of an invented translation or an empty translation bubble.
- Hy-MT2 requests are serial. A queued bubble displays the recipient and `Translation pending`.
- Changing a reading language never reloads or reinitializes the model; the next prompt simply renders the new target language.
- Ending a session waits for the loaded model to clean up and close, clears the prior conversation, and returns the same screen to its idle state. View-model teardown also releases the model.
- `MELANGE_PERSONAL_KEY` is supplied through the build environment and must not appear in source control or logs. Development builds embed it for SDK initialization; production distribution requires rotatable credential provisioning.

## Design tokens

The palette is the ZETIC minimal system: white surfaces, near-black text, gray supporting text, thin dividers, and a single teal accent, plus two muted per-speaker families drawn from the same two hues.

| Token | Value | Usage |
| --- | --- | --- |
| `color.accent` | `#2DBDB2` | Brand accent, reserved for two product-level emphasis uses: the `Start conversation` action and the model-load progress indicator |
| `color.surface` | `#FFFFFF` | Default background, chips, and idle controls |
| `color.surfaceSubtle` | `#F0F0F0` | Inline banners and disabled controls |
| `color.divider` | `#E8E8E8` | Hairline dividers and neutral control borders |
| `color.textPrimary` | `#0A0A0A` | Body text |
| `color.textSecondary` | `#6B6B6B` | Supporting, meta, and status text |
| `color.error` | `#C92A2A` | Errors |
| `space.1/2/3/4` | `4/8/12/16 dp/pt` | Shared spacing |
| `radius.message` | `16 dp/pt` | Chat bubbles |
| `radius.control` | `20 dp/pt` | A/B PTT controls, language chips, session actions |
| `type.body` | `16 sp/pt` | Source and translated text |
| `type.meta` | `12 sp/pt` | Speaker, status, chip, and target-language text |
| `logo.wordmark` | official ZETIC logo lockup, `16 dp/pt` tall | The ZETIC logo in the header |

### Per-speaker identity families

Each speaker owns one muted family, both derived from the brand system. No hue outside these two families is introduced.

| Token | Speaker A (teal) | Speaker B (ink) | Usage |
| --- | --- | --- | --- |
| `color.accentX` | `#2DBDB2` | `#0A0A0A` | Fill of that speaker's PTT control while recording, with white label text |
| `color.deepX` | `#17877D` | `#0A0A0A` | The `Speaker A` / `Speaker B` mini-label in a bubble, and the `A ·` / `B ·` prefix on the chip and idle PTT label |
| `color.tintX` | `#E9F7F5` | `#F0F0F0` | Chat-bubble fill; bubbles carry no border |
| `color.borderX` | `#BFE7E2` | `#E8E8E8` | Hairline border of that speaker's language chip and idle PTT control |

The two-use accent cap applies to the product chrome only. The per-speaker identity system is a deliberate exception: it reuses the same teal and ink values as a consistent, muted signal across a speaker's three touchpoints (language chip, chat bubbles, PTT control). Color is never the only distinguisher — the `Speaker A` / `Speaker B` labels, the `A ·` / `B ·` prefixes, and the left/right alignment carry the same information without it. Android uses dp/sp and iOS uses pt with Dynamic Type while maintaining the visual size and hierarchy in the table. System dark-mode support is outside MVP scope; do not add forced theme switching.

## Android/iOS parity criteria

| Scenario | Same result on both platforms |
| --- | --- |
| Cold start with permissions granted | The top language bar shows one chip per speaker, A left and B right, plus a single `Start conversation` / `Start Session` action |
| Start session | The banner reports model progress on the same screen; PTT and chips stay locked until the model is ready |
| Start A | A partial bubble on the left and active-A state; B control disabled with explanatory text |
| Start B | B partial bubble on the right and active-B state; A control disabled with explanatory text |
| Release or tap stop | Final result received before stopping stays pending; after stopping, source text finalizes and translation queues for the other speaker's language |
| Translation succeeds | Source text, target language, and translated text appear in one bubble |
| Change a reading language mid-session | The chip updates, the model is not reloaded, and only later utterances use the new target |
| Change a recognition language mid-session | The `Spoken language` section updates and the new language is used from the next utterance start |
| Change a language during an utterance | Both speakers' chips are disabled until the utterance finishes translating |
| STT unsupported or permission denied | Do not start; show cause and recovery action inline; do not switch to network recognition |
| Model loading or translation fails | Preserve source text when available; do not invent a translation; show a retryable error in place |
| End session | Wait for model cleanup and close, clear the prior conversation, then return the same screen to its idle state |

## Verification

- Every control has an equivalent accessibility label.
- Body text and state text do not clip or overlap at larger text sizes and Dynamic Type sizes; the language bar keeps both chips reachable rather than overlapping them.
- A/B active state, processing, and errors are distinguished with text, alignment, and layout in addition to color; removing all color leaves the screen fully usable.
- The `ZETIC` wordmark exposes a `ZETIC` accessibility label and is decorative brand exposure only, never a control.
- Android and iOS capture and compare the parity-table scenarios plus the idle, live, and error variants of the single screen using the same inputs.
