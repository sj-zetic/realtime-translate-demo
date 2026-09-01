# Shared Android/iOS UX and Design Specification

## Consistency principles

Both platforms use idiomatic Jetpack Compose and SwiftUI controls while preserving the same information architecture, A/B meaning, state transitions, terminology, message semantics, and token values. Platform-native navigation, permission guidance, haptics, and safe-area behavior follow OS conventions.

## Screen structure

Turn Translate is a single screen. Setup, model loading, conversation, and error guidance are regions of that one screen instead of separate destinations, so a first session costs one tap when permissions are granted and the default languages are acceptable.

1. **Header**: The app name `Turn Translate` on the leading edge and the `ZETIC` wordmark on the trailing edge of the same row, with the current session state as text below. Android renders both in a header row; iOS puts the title and the wordmark in the navigation bar. The wordmark is the official ZETIC logo lockup, shipped as `res/drawable-nodpi/zetic_logo.png` on Android and the `ZeticLogo` image set in `Sources/Assets.xcassets` on iOS, rendered at 16 dp/pt tall. The wordmark is a control: tapping it opens the [settings drawer](#settings-drawer). A small chevron in `color.textSecondary` sits immediately after the lockup as the only affordance that says the lockup is tappable, and the control carries the accessibility label `ZETIC, opens settings`. Implemented on both platforms. Android renders the lockup and a `KeyboardArrowDown` chevron as one clickable row whose descendants are merged behind that label.
2. **Language bar**: One compact chip per speaker directly under the status strip. Speaker A's chip is left-aligned and speaker B's chip is right-aligned, mirroring the side that speaker's chat bubbles appear on. Each chip reads `<speaker> · <reading language>`. Choosing a reading language also re-aligns that speaker's spoken (recognition) language to the matching recognizer when one exists, so the chip is the single source of truth: a speaker shown as Korean is listened to in Korean. The spoken-language picker stays available as an explicit override until the reading language changes again.
3. **Sound toggle**: The trailing end of the status-strip row carries the one spoken-output control, a speaker glyph that crosses out when muted. See [spoken translation](#spoken-translation).
4. **Session banner**: An inline region that appears only when the session needs attention: permission request, model-loading progress, model-load failure and retry, session unloading, or a runtime error with its recovery action. Push-to-talk stays unavailable until `SJ_zetic/Hy-MT2-1.8B` is ready.
5. **Conversation**: Chronologically ordered chat bubbles. Speaker A is left-aligned and speaker B is right-aligned. The newest bubble is scrolled into view.
6. **Push-to-talk row**: The A and B controls side by side at the bottom, A on the left and B on the right. The controls carry the A/B identity; there are no separate speaker labels or chips down here.
7. **Session action**: `Start conversation` before the model is loaded, `End session` while a session is live.

The bottom bar's contract is those two controls, the hint, and the session action. The hint row's empty trailing half carries the one [typed-input](#typed-input) affordance; nothing else is added down here.

### Launch

Cold launch shows the official ZETIC logo lockup centered on `color.surface`, so the first frame is the app's own background rather than a blank white flash, and the transition into the header is a continuation of the same surface. iOS declares this with the image-based `UILaunchScreen` in `Sources/Info.plist` (`UIImageName` = `LaunchLogo`, `UIColorName` = `LaunchBackground`); there is no storyboard. `LaunchLogo` is a 240 pt wide render of the lockup at 1x/2x/3x, roughly 60% of the screen width, because the launch screen draws the image at its natural size instead of scaling it to fit. Android parity is pending.

The app icon is the ZETIC Z monogram, teal `color.accent` on a near-black field, shipped as the single 1024x1024 universal entry in `Sources/Assets.xcassets/AppIcon.appiconset` on iOS. It is provisional and may be replaced.

### Screen layout

```text
Turn Translate                            ZETIC v
Conversation ready                              ((*
------------------------------------
 [ A · English ]              [ B · Korean ]
------------------------------------
[ inline banner: permission / model progress / failure + retry / error ]
------------------------------------
 Speaker A
 Hello
 --------------
 To B - English
 Hello                                       ((*
                            Speaker B
                            Bonjour
                            --------------
                            To A - Korean
                            Bonjour       ((*
------------------------------------
 [ A - hold to talk  ]        [ B - hold to talk  ]
 Hold a button to talk, or tap once to start and again to stop.  [keyb]
 [ End session ]
```

- A bubbles and the A chip and control create only A utterances; B bubbles and the B chip and control create only B utterances.
- Alignment plus the `Speaker A` / `Speaker B` label carries the A/B distinction; the per-speaker tint (A teal `#E9F7F5`, B ink `#F0F0F0`) and the colored mini-label are redundant reinforcement, never the only signal.
- An A bubble identifies `To B - <B reading language>`; a B bubble identifies `To A - <A reading language>`.
- The active utterance's partial source text updates only its existing active bubble. Partial text is never translated.
- While A or B is active, the opposite button is disabled with a textual explanation. Simultaneous recording is not supported.
- Android applies safe-content insets and iOS uses a bottom safe-area inset so the status strip, bubbles, and push-to-talk row avoid system bars and gesture areas.

## First run

Three steps stand between a brand-new install and a first translated turn, each shown at most once and each skipped silently when it has nothing to say. They are overlays above the single main screen, not separate destinations: the main screen is never rebuilt on the way in and there is no back stack to unwind. Implemented on both platforms. On Android the three surfaces are composed over the main screen in the same `Box`, so the screen and the Melange session behind them are untouched.

The first two steps are remembered in platform preferences (`@AppStorage` keys `firstRun.welcomeSeen` and `firstRun.permissionPrimingSeen` on iOS, the same two key names in the `turn-translate` `SharedPreferences` file on Android). The third is not remembered at all, because the model on disk already answers the question it asks.

### 1. Welcome

The very first launch opens on a full-surface welcome before anything else, in the same minimal chrome as the app: `color.surface` fill, the ZETIC lockup at the top so the launch screen flows into it, content leading-aligned, and one accent-filled action pinned at the bottom.

```text
 [ZETIC]

 Turn Translate
 Two people, two languages, one phone.
 ------------------------------------
 Speech and translation run on this phone. Nothing is sent to a server.


 [ Get started ]
```

- The tagline and the privacy line are the whole message: what it does, and where it runs.
- `Get started` is the only control. It is the accent-filled primary action, matching `Start conversation` on the main screen.
- Shown exactly once per install. Leaving it also settles the priming step for a returning user whose permissions are already granted.

### 2. Permission priming

After the welcome, and before either system prompt fires, a full-surface priming step explains what the microphone and speech recognition are for. The OS alert is never the first mention of the microphone.

```text
 Microphone and speech
 Microphone: to hear whoever is holding a button.
 ------------------------------------
 Speech recognition: to turn that audio into text.
 ------------------------------------
 Both run on this phone. No audio and no text leave the device.
 iOS asks for each one next.

 [ Continue ]
 [ Not now  ]
```

- `Continue` triggers the real system prompts. `Not now` dismisses the step and leaves the main screen's existing permission banner as the way back in. Both settle the step, so it is shown at most once either way.
- **Android parity note.** Android has one prompt to prime, not two: `RECORD_AUDIO` covers the on-device recognizer, so the last line reads `Android asks for the microphone next.` and the two explanatory lines above it are unchanged. The step is selected from the same `permissionNeeded` input, which on Android is the session being in `permissionRequired`.
- Skipped silently when the prompts have already been answered with a yes, so a returning user never sees it. The permission already held is adopted on appear, which also means a returning launch lands on the idle main screen rather than the permission banner.

### 3. Model download consent

Tapping `Start conversation` (or `Retry model load`) asks before it starts the one large transfer the app ever makes. The consent step is a card over the main screen, on the same `color.scrim` the settings drawer uses, because it interrupts one tap rather than the whole app.

```text
 Download the translation model
 The translation model is about 1.9 GB.
 It downloads once, then it stays on this phone.
 ------------------------------------
 You are not on Wi-Fi. A download this large is better on Wi-Fi.

 [ Download now ]
 [ Not now      ]
```

- Shown only when no complete local model exists. A complete extracted module or a complete archive for `SJ_zetic/Hy-MT2-1.8B` both mean the next start is a local load in seconds with no network at all, so consent is skipped entirely and the session starts on the tap.
- `about 1.9 GB` is the measured size of the archive and is the only size wording used.
- The Wi-Fi line appears only when the current network path is expensive or constrained (`NWPathMonitor` `isExpensive` / `isConstrained` on iOS). On an unrestricted path the card carries the size and the once-only line and nothing else.
- `Download now` proceeds into `modelLoading`. `Not now` and a tap on the scrim both dismiss the card and leave the screen idle; nothing is downloaded and the declined start is dropped rather than queued.
- Declining does not remember anything: the next `Start conversation` asks again, which is also how the Wi-Fi warning gets a second chance to appear.

**Android parity note.** Two inputs to the decision read differently on Android, and the decision itself is the same function.

- **"No model cached" is approximated, honestly.** The Melange Android SDK offers no read-only way to ask whether `SJ_zetic/Hy-MT2-1.8B` is already in its cache, and guessing at cache paths would be worse than admitting the gap. Android therefore gates on a `model.hasEverLoaded` preference written the first time a load succeeds. The one case it gets wrong is a user who clears app storage without uninstalling: they are asked to consent to a download that is genuinely about to happen, which is the safe direction to be wrong in. It becomes an exact answer when the SDK grows a cache query, which is also what the [`Storage` row](#model-storage) is waiting on.
- **One network reading, not two.** `ConnectivityManager.isActiveNetworkMetered` already folds cellular, metered Wi-Fi, and a metered hotspot into the single answer the card acts on, so Android has no equivalent of the `isExpensive` / `isConstrained` pair and needs none: the sentence shown is the same either way.

A build with no Melange personal key cannot download anything at all. The consent card is not shown there: offering `Download now` would promise a transfer that ends a frame later in the missing-key failure. The start runs instead, and that failure is reported where every other model failure is, in the session banner with its retry.

### Model preparation progress

The loading banner distinguishes a genuine download from a local load, because they feel completely different and only one of them has a size.

| Condition | Headline | Detail | Indicator |
| --- | --- | --- | --- |
| A progress callback reports a value strictly between 0 and 1 | `Downloading translation model <percent>%` | `<transferred> of 1.9 GB` | Determinate progress bar in `color.accent` |
| No progress reported, or exactly 0 or 1 | `Preparing translation model` | none | Indeterminate spinner in `color.accent` |

The progress callback is the whole rule: the local load path never reports progress, so an indeterminate banner never promises bytes that will not move. The transferred amount is rounded to tenths of a gigabyte, so half of the archive reads as `1.0 of 1.9 GB`. Both variants keep the existing `Speaker controls unlock when the model is ready.` line.

### Test hooks

The first-run states are forced through launch arguments so they can be exercised without depending on whatever a device or simulator container happens to hold. On iOS these are applied before any view reads its stored flags.

| Argument | Effect |
| --- | --- |
| `-resetFirstRun` | Clear both remembered flags |
| `-firstRun fresh` | Clear both flags and report no local model: welcome, then priming, then consent |
| `-firstRun returning` | Set both flags and report a local model present: no first-run surface at all |
| `-firstRun consentNeeded` | Set both flags and report no local model: the next `Start conversation` shows the consent card |
| `-firstRunCellular` | Report the current network path as expensive, so the Wi-Fi line appears |

## Settings drawer

The only secondary surface. It slides in from the trailing edge over the main screen, which stays mounted and untouched behind a dim scrim. Opening it never changes session state, so it can be opened at any state; the one row that changes anything, `Clear conversation`, empties the transcript and leaves the session, the model, and both language chips exactly as they were. Implemented on both platforms.

- **Opening**: tap the `ZETIC` wordmark in the header. **Closing**: the header's close control, a tap anywhere on the scrim outside the panel, or a swipe toward the trailing edge. There is no back stack entry and no navigation transition; the main screen never unloads.
- **Panel**: full height, 280 dp/pt wide at most, `color.surface` fill with a hairline `color.divider` on its leading edge, and hairline dividers between regions. Row labels are terse and left-aligned; each row's trailing icon is a quiet `color.textSecondary` glyph that repeats what the label already says.

```text
 Settings                    X
------------------------------
 Clear conversation          🗑
 Keeps the session and the languages
------------------------------
 App language                🌐
 System
------------------------------
 Storage                     ▤
 1.9 GB on this phone
------------------------------
 Visit zetic.ai              ↗
------------------------------
 Contact us                  ⧉
 contact@zetic.ai
------------------------------
 About
 Turn Translate
 Version 1.0 (1)
 Speech, translation, everything stays on this phone.
```

1. **Header**: the title `Settings` and a close control.
2. **Row list**: `Clear conversation` empties the transcript without ending the session, see [clear the conversation](#clear-the-conversation). `App language` chooses the language the interface itself is in, see [localization](#localization). `Storage` reports what the downloaded model occupies and is the way to give that space back, see [model storage](#model-storage). `Visit zetic.ai` opens `https://zetic.ai` in the system browser. `Contact us` shows `contact@zetic.ai` as its subtitle and copies that address to the system clipboard; it does not open a mail composer. The row list is the extension point for later settings rows.
3. **About**: the app display name, version, and build read from the platform bundle, plus one privacy line: `Speech, translation, everything stays on this phone.`

- **Android parity note.** Android renders the panel with `ModalNavigationDrawer`, which opens from the leading edge, so the layout direction is flipped for the drawer scaffold alone and restored inside both the sheet and the main screen: only the side and the swipe direction change. Drag-to-open is off and drag-to-close is on, because the wordmark is the only way in. The rows shipped are `Clear conversation`, `Visit zetic.ai`, `Contact us`, and the About block; `App language` waits on the localization pass and `Storage` waits on the same Melange cache query the [download consent](#3-model-download-consent) note describes, since a row that reports a footprint it cannot measure and deletes files it cannot enumerate would be worse than no row. Both are additions to the same row list, which is why the list is the extension point. About reads its version pair from `PackageInfo` rather than `BuildConfig`, so it reports what is actually installed.
- **Copy confirmation**: copying the address shows a toast centered at the bottom of the screen reading exactly `Email address copied`, in `color.textPrimary` fill with `color.surface` text at `radius.control`, which fades out after about two seconds. The toast is not interactive, the drawer stays open behind it, and the same text is posted as an accessibility announcement so it is not a visual-only confirmation.

## Session comfort

Three behaviors that only matter once two people are actually using one phone together. None of them adds a control or a setting, and none of them changes a state transition. Implemented on both platforms.

### Keeping the screen awake

While a session is live, the display does not dim or lock. A turn can be seconds of silence while someone thinks, and both people are reading the same screen, so the normal idle timeout is wrong for exactly the states where the A/B controls are on screen.

- The screen is held awake in exactly the states where push-to-talk is available: `ready`, `listeningA` / `listeningB`, `finalizingA` / `finalizingB`, `translatingA` / `translatingB`, and `error`. It is the same condition that decides whether the A/B controls and `End session` are shown, not a second rule that can drift from it.
- Every other state, `permissionRequired`, `setup`, `modelLoading`, `modelLoadFailed`, `modelUnloading`, and `ended`, uses the platform's normal idle behavior. A long model download does not hold the screen awake.
- Backgrounding the app releases the hold immediately, whatever the session state is, and so does leaving the screen. Returning to the foreground during a live session takes it again.
- iOS applies this through `UIApplication.isIdleTimerDisabled`, driven from the view layer by scene phase plus session state.
- Android applies it through `View.keepScreenOn` on the Compose root, driven by the lifecycle state plus session state, and hands it back on dispose. The Android form of "the model is loaded and the conversation screen is in use" is `conversationStarted` plus one of the eight live phases: the idle main screen is `Ready` with that flag false, so it is not a live session, and neither is a model download.

### Haptics

Push-to-talk is operated by feel, often without looking, so the two ends of a turn are confirmed physically. The vocabulary is four events and nothing else.

| Event | Feel | Why |
| --- | --- | --- |
| A push-to-talk control is pressed and recording starts | Medium impact | The one deliberate action, and the one worth confirming firmly |
| A push-to-talk control is released and the turn ends | Light impact | Symmetric with the press, quieter because the work is not done yet |
| A finalized transcript comes back as a translation | Soft impact | A tick that says the other speaker can read now, without demanding attention |
| A session error banner appears | Standard error notification | The one failure that takes over the screen |

- A failed translation is silent. The bubble already carries the failure, the session continues, and a buzz per failed turn would be noise.
- Nothing else vibrates: not model loading, not language changes, not opening the drawer, not copying.
- The mapping from event to sensation is a single table, so the vocabulary can be read in one place rather than inferred from call sites.
- **Android parity note.** The same four events map to `View.performHapticFeedback` constants rather than to the vibrator directly, so the phone's own haptic strength and the user's system-wide haptics setting are respected: `LONG_PRESS`, `KEYBOARD_TAP`, `CLOCK_TICK`, and `REJECT`. `REJECT` only exists from API 30 and the app runs from API 26, so the error buzz falls back to `LONG_PRESS` rather than silently doing nothing. Press and release are played at the control, which is enabled only when a turn can actually start, rather than waiting for the recognizer's callback.

### Copy a bubble

Long-pressing a chat bubble offers one action, `Copy`, which puts that bubble's text on the system clipboard.

- A translated bubble copies its translation, falling back to the source transcript if there is somehow no translated text. Every other bubble copies its source transcript. A bubble still showing `Listening...` has nothing to copy and offers no action.
- The gesture is a platform context menu with a single `Copy` item, not a bare long press that copies silently. Android uses `combinedClickable` with an `onLongClickLabel` of `Copy`, anchoring a one-item `DropdownMenu` on the bubble; the long-press gesture is disabled outright on a bubble with nothing to copy, so the menu can never open empty. The transcript scrolls, so a bare gesture fires on a slow drag; the menu also names the action before it happens and exposes it to the accessibility rotor.
- The confirmation is the same toast the settings drawer uses, reading exactly `Copied`: `color.textPrimary` fill, `color.surface` text, `radius.control`, non-interactive, fading out after about two seconds, and posted as an accessibility announcement as well as shown. It is anchored to the bottom of the transcript rather than the bottom of the screen, so it never covers the push-to-talk row or the session action.

## Spoken translation

A translation that arrives is read aloud, so the person it is for can listen instead of leaning over the phone. The voice is the platform's own speech synthesizer (`AVSpeechSynthesizer` on iOS); no model is downloaded and nothing is sent anywhere. Implemented on iOS; Android parity is pending.

### Speaking a translation

- A translation is spoken exactly once, at the moment its bubble reaches the translated state. Nothing else speaks: not a partial transcript, not the source text, not a failed translation, and not a bubble that arrives with no translated text.
- The voice language is that bubble's reading language, so an A turn is read in B's language and a B turn in A's.
- **Newest wins.** A translation that finishes while an earlier one is still being spoken cuts it off mid-sentence rather than queueing behind it. Two people talking must never build a backlog of sentences the phone still owes them.
- The voice is resolved from the reading language in three steps: an exact match for the code, then the variant that code implies (`zh-Hant` picks a `zh-TW` voice over a `zh-CN` one, `en` picks `en-US`), then any installed voice for the same language. A language with no installed voice on the device stays silent; it is never read out in another language's voice.

### Replaying a bubble

Every bubble with a finished translation carries a small speaker glyph in the bottom trailing corner of its translation region. Tapping it speaks that translation again, under the same rules as the automatic announcement, cutting off anything already being spoken.

- The control is absent, not disabled, on a bubble that is still recognizing, still translating, or whose translation failed: there is nothing there to play.
- It is present but disabled while sound is off, and while the recognizer holds the microphone (`listening*`, `finalizing*`), because nothing can be spoken over an open microphone. A control that answers a tap with silence reads as broken rather than busy.
- It carries the accessibility label `Play translation` and is a separate element from the bubble, so the bubble's combined label and its `Copy` long press are unchanged.

### The sound toggle

One toggle at the trailing end of the status strip: a speaker glyph when sound is on, a crossed-out speaker when it is off. The status strip is one short line of text with its whole trailing half empty, so the app's only always-present control lands there without crowding the header wordmark or adding a row of chrome.

- Default is sound **on**. The choice is remembered in platform preferences (`@AppStorage` key `speech.muted` on iOS), and the view model seeds itself from the same key, so a launch that starts muted never speaks before the screen appears.
- Muting suppresses the automatic announcement, disables every replay control, and stops whatever is being spoken at that moment: the toggle is what someone reaches for to make the phone stop talking.
- The toggle announces its state in words, `Spoken translation on` or `Spoken translation off`, because the glyph is its whole face.

### Recognition and playback handoff

Recognition runs the audio session as `.record` with `.measurement` mode, which cannot play anything, so speaking has to take the session over and hand it straight back.

- Speaking claims the session as `.playback` with `.spokenAudio` mode, ducking other audio, and releases it with `notifyOthersOnDeactivation` when speech ends, so whatever was playing before resumes and the next push-to-talk finds the session free.
- **Nothing is ever spoken while the microphone is open.** Beginning a turn stops speech synchronously before the recognizer starts, so a user who interrupts a sentence by pressing a control gets a recording, not a fight over the route. Ending a session stops speech too.
- The session is claimed and released once each, never per sentence: replacing one translation with a newer one is a cut, not a route change, and the delegate callback that reports the cancelled utterance cannot deactivate a session the recognizer has since claimed. A session that refuses to activate speaks nothing and is retried on the next translation.
- A session state machine (`SpeechAudioCoordinator` on iOS) owns that handoff over an injected session seam, so the ordering is unit tested even though the audio route itself is only verifiable on a device.

## Typed input

Speech is the primary way to take a turn, not the only one. A loud room, a quiet room, a proper noun the recognizer keeps mangling, or a speaker who would rather not talk at a stranger's phone all need the same turn produced by hand. Implemented on iOS; Android parity is pending.

Typed text is not a second kind of message. It is a finalized transcript, handed to the exact path a released push-to-talk control hands one to, so the target language, the Hy-MT2 request, the bubble, and the spoken translation are all unchanged. There is one translation pipeline and one entry point into it.

### The affordance

One shared control, a small keyboard glyph at the trailing end of the bottom bar's hint row. The bottom bar's contract stays the A and B controls, the hint, and the session action: a keyboard button beside each push-to-talk control would make that row four controls wide and crowd all three. The hint row is one short sentence with its trailing half empty, so the control lands there the same way the sound toggle lands on the status strip, without adding a row of chrome.

- It carries the accessibility label `Type a message` and, when it is locked, the hint `Typing unlocks once the translation model is ready.`
- It is enabled under exactly the push-to-talk rule: only an idle live session accepts a new utterance. Nothing can be typed before the model is ready, after the session ends, or while either speaker's utterance is recording, finalizing, or translating.

### The sheet

Tapping it opens a half-height sheet, which is the surface a screen reader already treats as modal:

```text
 Cancel            Type a message            Send
 [ Speaker A ][ Speaker B ]
 Speaker A types in English. It is translated into Korean for B.
 [ Good morning                                        ]
```

1. **Speaker**: a two-item segmented control. The A/B choice lives here rather than in the bottom bar, because there is room here to name both languages instead of implying them. The last speaker typed for is remembered across openings; the draft is not.
2. **Guidance**: one line naming both ends of the turn, because the sheet covers the language bar.
3. **Field**: a multi-line text field, focused on appearance, placeheld with `Type in <that speaker's reading language>`. Each speaker types in their own reading language, the same language their chip shows.
4. **Send**: disabled while the draft is empty or whitespace only, and while an utterance is in flight. Sending trims the text, dismisses the sheet, and produces that speaker's bubble already finalized, because there was never a partial to show. A committed typed turn plays the same light `turnEnded` tap a released push-to-talk control plays, and its delivered translation the same soft tick.

## Clear the conversation

One action, in the settings drawer's row list, that empties the transcript without ending the session: the model stays resident, both language chips stay as they are, and the next turn starts straight away. Implemented on both platforms. Android also stops nothing extra today, because spoken translation is not on Android yet; when it lands, the clear stops it the same way iOS does.

- The row reads `Clear conversation` with the subtitle `Keeps the session and the languages` and a quiet trash glyph. It is the first row, because it is the one row someone opens the drawer in order to use.
- No confirmation. Nothing was ever stored, so there is nothing to lose that a next turn does not replace.
- Disabled, not hidden, when the transcript is empty or an utterance is recording, finalizing, or translating, so the row never moves and never strands a bubble a translation is about to land in. Its accessibility label says which of the two it is.
- Clearing stops whatever is being spoken, because that sentence belongs to a bubble that is going away, and clears the session note with it: a `Tap to talk again.` line left standing over an empty transcript belongs to a conversation that is no longer there.
- The row is guarded twice on both platforms: the row is disabled, and the action itself refuses when the same rule says no, so a tap that lands as the rule changes cannot strand an in-flight bubble.
- The confirmation is the shared toast, reading exactly `Conversation cleared`, posted as an accessibility announcement as well as shown. The drawer closes first, so the emptied transcript is what the toast lands over.
- One obvious place only: the drawer row. There is no duplicate on the transcript, on the bottom bar, or in a bubble's context menu.

## Audio interruptions

A phone call, Siri, an alarm, or an unplugged headset takes the audio session away mid-sentence. There is no way to resume an utterance that lost its microphone halfway through, so the app does not pretend otherwise: the utterance dies, the session does not. Implemented on iOS; Android parity is pending.

- **What is lost**: exactly what was using audio at that instant, and nothing else. The model stays loaded, both language chips stay as they are, and every earlier bubble stays where it is.
- **Interrupted while recording or finalizing** (`listeningA` / `listeningB`, `finalizingA` / `finalizingB`): the recognizer is released, the half-written bubble is discarded the same way a failed turn start discards its bubble, and the session returns to `ready`.
- **Interrupted while a translation is being spoken**: the speech stops. The transcript is untouched, so the bubble and its replay control are still there for whoever wants to hear it again.
- **Interrupted while translating, loading, or idle with nothing playing**: nothing changes. The microphone was already handed back before the request went out, so a call arriving mid-translation costs the utterance nothing.
- **Route lost** (headphones unplugged, a Bluetooth headset disconnecting) is treated as an interruption, because to whoever is speaking it is one. A new device merely becoming available is not.
- **The note**: one quiet line in the inline session banner reading exactly `Interrupted. Tap to talk again.`, in `color.textSecondary` with no error color and no button. It is not an error state. It clears itself the moment the next turn starts, by push-to-talk or by typing.
- **The interruption ending never restarts anything.** The platform's "audio could resume now" hint is read and deliberately not acted on: resuming would mean opening the microphone with nobody holding a button, which is the one thing a push-to-talk app must never do. The next press starts a turn normally, because the recognizer claims and activates its own audio session on every start.

## Localization

The interface is translatable, and the app can be put into a language of its own without changing the phone's. This is separate from everything else on this screen that says "language": the two chips choose what is *translated*, and this chooses what the app is *written in*. Implemented on iOS in English, French, and Spanish: all three are shipped, all 126 keys translated in each. Android parity is pending.

### Shipped languages and their register

- **French (`fr`), shipped.** Vouvoiement throughout, no tutoiement anywhere: the phone is handed to a stranger, so the second person on screen is not the person who installed the app, and French iOS system UI next to it is uniformly vouvoyée. Buttons stay infinitive (`Continuer`, `Réessayer`), which is address-neutral and the French Apple convention. French typography is carried in the catalog as real code points: no-break space (U+00A0) before `:` and `%`, narrow no-break space (U+202F) before `?`, U+2019 for every apostrophe, and guillemets where a control name is quoted.
- **Spanish (`es`), shipped.** Tú throughout, which is what Apple's Spanish localizations use and what a two-people-one-phone consumer app calls for; controls stay infinitive (`Cancelar`, `Enviar`) per the same convention. Neutral international Spanish, so `mantén pulsado`, `Ajustes`, and `toca` rather than their regional alternatives. `Start Session` is `Empezar sesión`, never `Iniciar sesión`, which in Spanish means *log in*.

### Where the strings live

One String Catalog per platform holds every user-facing string. On iOS that is `ios/Sources/Localizable.xcstrings`, with `en` as the development language, `en`, `fr`, and `es` in the project's known regions and in `CFBundleLocalizations`, and the catalog compiled into the app bundle at build time. A build extracts the strings and `xcstringstool sync` merges them into the catalog, so the catalog is generated from the code rather than maintained beside it.

Strings reach the catalog by one of two routes, and the difference is visible to the user:

1. **Literals in views** (`Text("Settings")`) resolve against the environment locale. They repaint the moment the language changes.
2. **Strings built in models and copy constants** (`String(localized:)`) resolve against the bundle and the process locale, which the platform settles at launch. They change when the app is next opened.

That split is the whole reason the language row promises what it promises. It is not worked around: half the screen updating immediately and the rest updating on the next launch is standard platform behaviour, and pretending otherwise would mean rebuilding every model string on every locale change for no real gain.

### What is not translated

- **The product name** `Turn Translate`, the brand `ZETIC`, the domain `zetic.ai`, the address `contact@zetic.ai`, and the model name `Hy-MT2`. These are held as plain constants so nothing can translate them by accident.
- **The speaker labels** `A` and `B`, and size figures such as `1.9 GB`. Byte sizes are formatted by the platform, which localizes the unit on its own.
- **The 38 Hy-MT2 reading-language names.** That name is not only a label: it is the argument the Hy-MT2 prompt is built from (`Translate the following text into French`), and the instruction has to stay English whatever the interface is in. Translating the picker therefore means a second, display-only name on each entry, which is a change to the model catalogue rather than to the localization plumbing. Until then a French interface names the reading languages in English. The spoken-language list is unaffected: those names come from the platform and are already localized.
- **Log lines, launch-argument names, accessibility identifiers, and URLs**, none of which a person reads.

### The `App language` row

- **What it shows**: the row title `App language` with the language currently in force as its subtitle. The value is the point of the row: someone who has put the app into a language they cannot read has to be able to find their way back out by recognizing it.
- **The choices**: `System`, `English`, `Français`, `Español`. The three concrete languages are named in their own language, never translated; only `System` is.
- **The default is `System`**, which follows the order set in the platform's own settings. Choosing `System` again removes the override rather than pinning whatever the phone currently is, so a phone that changes its language later is followed instead of frozen.
- **Choosing a language** writes the platform's own language override (`AppleLanguages` on iOS) and confirms with the shared toast reading exactly `Language applies fully after reopening the app`. Everything the environment locale drives repaints immediately; the rest follows on the next launch. Choosing the language that is already selected changes nothing and shows no toast.
- **The drawer stays open**, unlike the clear row: the thing worth seeing afterwards is this row showing the new value.
- **Nothing else changes.** The session, the loaded model, the transcript, both language chips, and the sound toggle are untouched. The override is remembered across launches under its own key, alongside the other preferences.

### Fallback rules

- **A language with no translations falls back to the development language, string by string.** `fr` and `es` are populated, so this now covers only a language added to the project ahead of its pass: it gets an English interface, not a broken one, and gains its own strings when the pass lands, without any code change.
- **A key missing from a language falls back to English**, so a partly finished pass never shows a blank or a raw key.
- **A stored language this build no longer offers falls back to `System`**, the same tolerance the reading chips apply to a code that is no longer in the catalogue.
- **Formatting follows the chosen language**: sizes, numbers, and dates come from the platform's formatters rather than from hand-built strings, so they are already right in a language whose strings are not translated yet.
- **No user-facing string, in any language, contains an em dash or an en dash.** The rule is enforced across the whole catalog by a test that scans every value, not just the copy constants a person remembered to list.

## Model storage

The 1.9 GB translation model is the largest thing this app puts on a phone, and the settings drawer is where it can be given back. This is the app's only destructive action. Implemented on iOS; Android parity is pending.

- **The row** reads `Storage` with the on-device footprint as its subtitle, for example `1.9 GB on this phone`. The number is what a delete would actually reclaim: the whole model directory in the SDK's cache, counted once.
- **Nothing downloaded**: the subtitle reads `No model downloaded` and the row is disabled. It is disabled rather than hidden, so the row never moves.
- **The model is held**: it is in memory, or being mapped into it, so the row is disabled and the subtitle says which. A live session appends `End the session first.`, because that is an action on the screen behind the drawer. Anything else holding it, the model loading and the model still resident after `End session`, appends `The app is using it right now.` instead: there is no session to end, and the model is released when the app's screen goes away. The accessibility label says the same thing in words.
- **What "held" means** is the runtime's own answer, not the session state. The two are not the same question, and the states where they differ are exactly the ones where a delete does the most damage: `modelLoading` is the file being mapped as it is removed, and the state after `End session` is a model kept resident on purpose, where deleting the files leaves the app translating happily from memory and then silently downloading 1.9 GB again on the next launch.
- **Deleting asks first.** The row never deletes; it opens a confirmation titled `Delete the downloaded model?` whose message names the size and the cost (`This frees 1.9 GB. The next session downloads the model again.`), with one destructive action `Delete downloaded model` and one way out, `Keep it`. It is the only confirmation in the app, because it is the only thing here that cannot be undone from inside it.
- **What is deleted**: the model's own artifacts and nothing else. The archive and the extracted module, the directory holding them, and the cache-index records that name them. The SDK's backend-selection records and staging locks are never touched, and neither is any other model in the same cache. A cache whose index cannot be read is refused rather than swept, and a model key that is not a plain directory name inside the artifacts root is refused before any path is built from it. The index must also *name* this model: the guess that a cache holding exactly one model key must be holding ours is good enough to load with, where a wrong guess only costs a failed init, and not good enough to delete with, where it removes somebody else's model.
- **Order**: the rewritten index is written first and its write is checked. A write that fails refuses the whole delete with the model still on disk, rather than leaving an index that promises a model that is no longer there and a toast confirming a delete that only half happened.
- **Afterwards** the drawer stays open, the row reports `No model downloaded`, and the shared toast reads exactly `Model deleted`. The app is back in its pre-download state: the next `Start conversation` shows the [download consent](#3-model-download-consent) again, because there is genuinely a download to consent to.

## Language selection on the main screen

- Each speaker has exactly one chip in the top language bar. One tap opens that speaker's menu, which carries two sections: `Reading language` (the 38 Hy-MT2 entries, the primary list) and `Spoken language` (`Automatic` plus the OS-derived on-device recognition locales). Android renders the sections as labelled groups separated by a divider in a `DropdownMenu`; iOS renders two inline `Picker`s inside one `Menu`.
- The chip face shows only the reading language, because that is the setting people actually change. The `A ·` / `B ·` prefix is tinted in that speaker's deep color and the chip border uses that speaker's border token. The recognition language stays reachable in the same menu and is announced in the chip's accessibility label.
- Chips render `Automatic` in short form; the menu entries keep the platform's full display name (Android shows `Automatic (device recognizer)` there).
- Languages can be changed before, between, and during a session without reloading the model. A reading-language change affects future translation prompts only. A recognition-language change applies at the next utterance start.
- Both speakers' chips are locked while any utterance is recording, finalizing, or translating, and while the model is loading. Locking both, rather than only the active speaker's, keeps an in-flight utterance's target language stable.
- Defaults are English and Korean reading languages with recognition aligned to each (falling back to `Automatic` when no matching recognizer exists), so the first session needs no language taps.

### Remembering the selections

Both speakers' language selections survive a relaunch, so the pair who set up Korean and Japanese yesterday are not setting it up again today. They are kept in platform preferences alongside the sound toggle's `speech.muted` (iOS keys `language.reading.A` / `language.spoken.A` and the B pair), as codes and recognizer identifiers rather than as objects. Implemented on iOS; Android parity is pending.

The restore is not symmetric, because the two selections are not equally authored:

1. **Reading languages restore first, verbatim.** A reading language is only ever chosen by a person. A stored code this build no longer offers falls back to the default rather than leaving the chip blank.
2. **The spoken language then derives from the restored reading language**, through the same chip coupling a fresh launch uses.
3. **A stored spoken language is applied on top only when it differs from that derived value and still names a recognizer this device has.** So an explicit override survives a relaunch, while a value that was only ever the derived default re-derives. A device that lost a recognition locale between launches re-derives rather than pinning an identifier it can no longer listen with.

The mute preference already persists under its own key and is not duplicated here. Nothing else is remembered: no transcript, no session, no audio, no text.

## Shared state transitions

The `setup` and `ready` states now render on the same screen: `setup` is the idle main screen with push-to-talk locked and `Start conversation` offered, and `ready` is the live main screen with push-to-talk unlocked and `End session` offered. No state was removed or merged.

| State | Display on the main screen | Allowed actions | Next state |
| --- | --- | --- | --- |
| `permissionRequired` | Permission banner; push-to-talk locked | Request permission, open settings, change languages | `setup`, `error` |
| `setup` | Idle screen; `Start conversation`; push-to-talk locked | Start session, change language | `modelLoading`, `permissionRequired`, `error`; stays in `setup` while the [download consent card](#3-model-download-consent) is open and if it is declined |
| `modelLoading` | Progress banner, [downloading or preparing](#model-preparation-progress); push-to-talk and chips locked | Wait | `ready`, `modelLoadFailed` |
| `ready` | Live screen; A/B controls available; `End session` | Start A or B, end session, change language | `listeningA`, `listeningB`, `setup` |
| `listeningA` | `Speaker A is speaking`, active A bubble, accent-filled A control | Stop A | `finalizingA`, `error` |
| `listeningB` | `Speaker B is speaking`, active B bubble, accent-filled B control | Stop B | `finalizingB`, `error` |
| `finalizingA` / `finalizingB` | `Finalizing speaker A/B transcript` | Wait for completion | `translatingA`, `translatingB`, `error` |
| `translatingA` / `translatingB` | `Translating for speaker B/A` | Wait for completion | `ready`, `error` |
| `modelLoadFailed` | Failure banner with `Retry model load` | Retry model load | `modelLoading` |
| `error` | Error banner with the cause and a recovery action; existing bubbles remain | Retry, open settings, end session | `ready`, `setup`, `permissionRequired` |

If platform STT reports a final result before the user stops an utterance, the app stores it only as the active bubble's pending transcript. The app leaves `listening*` for `finalizing*` and starts finalization and translation only after a button release or tap-toggle stop. A translation error leaves the finalized source bubble visible and shows an error state in the translation area.

**A turn that recognizes nothing.** An empty final result is a real answer, not a missing one: a silent turn produces one, and the platform recognizer synthesizes one for any recognition failure that is not a cancellation. While the utterance is still recording it means nothing yet and is ignored. Once the control is released it is the only answer that will ever come, so the app takes the same exit an interruption takes: the recognizer is released, the bubble that was going to hold the utterance is discarded, the session returns to `ready`, and one quiet line reads exactly `No speech was recognized. Tap to talk again.` in the inline session banner. The model stays loaded, both chips stay as they are, every earlier bubble stays where it is, and the next push-to-talk clears the note. `finalizing*` has exactly one other exit, so without this a silent turn locks every control on the screen except the one that ends the session and wipes the conversation.

## A/B input and accessibility

- The primary action is push-to-talk: recording lasts while the user holds a button and stops when it is released. [Typed input](#typed-input) is the fallback for the same turn, under the same gate.
- The same control supports tap-to-start and tap-to-stop as an accessibility alternative. The current interaction is shown as text.
- Accessibility labels include the current action and speaker, such as `Start speaker A` / `Start A Turn`, `Stop speaker A` / `End A Turn`, and the B equivalents.
- A disabled opposite control exposes equivalent explanatory text, such as `Speaker B cannot start while speaker A is active`. A control disabled because no model is loaded explains that instead.
- Every language chip announces both selections for its speaker, such as `Speaker A languages: reads English, speaks Automatic`.
- The main screen uses no icons. State, speaker, and errors are carried by text, alignment, and layout, so the single accent color is never the only signal.
- The header wordmark, the settings drawer, the two spoken-output controls, and the typed-input control are the exceptions, and only for chrome, for sound, and for the keyboard: the wordmark's chevron, the external-link glyph on `Visit zetic.ai`, the copy glyph on `Contact us`, the trash glyph on `Clear conversation`, the status strip's speaker toggle, a bubble's replay glyph, and the bottom bar's keyboard glyph. The drawer's glyphs each sit next to a text label that already says what the control does. The two speaker glyphs and the keyboard glyph are the only places a glyph stands alone, because a speaker and a keyboard are the two icons that mean sound and typing in every app on the phone; all three announce their meaning, and the toggle its state, in words.
- The wordmark control announces `ZETIC, opens settings`; the drawer's rows announce their action and, for `Contact us`, the address being copied; the copy confirmation is posted as an accessibility announcement as well as shown.

## On-device STT prerequisites

- The source-language selector is not limited by an app-defined whitelist.
- Android API 33 and later lists installed on-device recognition locales. Android API 31-32 offers `Automatic` because installed-locale discovery is unavailable.
- iOS lists only `SFSpeechRecognizer` supported locales that are on-device capable.
- Android and iOS use on-device recognition only. The app does not download speech models, preflight source-language compatibility, or fall back to online STT. If the platform cannot start recognition, it enters `error` with guidance.

## Translation execution

- The `Reading language` section of each speaker's chip menu shows all 38 options from the [Hy-MT2 translation reference](hy-mt2-integration-reference.md).
- Starting a session asynchronously downloads and loads `SJ_zetic/Hy-MT2-1.8B` through Melange SDK `1.10.0`. Loading failure reports a retryable error and never enables PTT.
- The first download is consented to, not assumed: with no complete local model the session start opens the [download consent card](#3-model-download-consent) first, and with one present it starts straight into a local load.
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
| `color.accent` | `#2DBDB2` | Brand accent, reserved for product-level emphasis: the `Start conversation` action, the model-load progress indicator, and the single primary action on each first-run surface |
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
| `logo.wordmark` | official ZETIC logo lockup, `16 dp/pt` tall | The ZETIC logo in the header, tappable, followed by a `color.textSecondary` chevron |
| `color.scrim` | `#000000` at 16% | Dim behind the settings drawer; tapping it closes the drawer |

### Per-speaker identity families

Each speaker owns one muted family, both derived from the brand system. No hue outside these two families is introduced.

| Token | Speaker A (teal) | Speaker B (ink) | Usage |
| --- | --- | --- | --- |
| `color.accentX` | `#2DBDB2` | `#0A0A0A` | Fill of that speaker's PTT control while recording, with white label text |
| `color.deepX` | `#17877D` | `#0A0A0A` | The `Speaker A` / `Speaker B` mini-label in a bubble, and the `A ·` / `B ·` prefix on the chip and idle PTT label |
| `color.tintX` | `#E9F7F5` | `#F0F0F0` | Chat-bubble fill; bubbles carry no border |
| `color.borderX` | `#BFE7E2` | `#E8E8E8` | Hairline border of that speaker's language chip and idle PTT control |

The accent cap applies to the product chrome only, where the accent means "this is the way forward" and appears once per surface. The per-speaker identity system is a deliberate exception: it reuses the same teal and ink values as a consistent, muted signal across a speaker's three touchpoints (language chip, chat bubbles, PTT control). Color is never the only distinguisher: the `Speaker A` / `Speaker B` labels, the `A ·` / `B ·` prefixes, and the left/right alignment carry the same information without it. Android uses dp/sp and iOS uses pt with Dynamic Type while maintaining the visual size and hierarchy in the table.

### Appearance

The app is locked to the light appearance, explicitly: iOS declares `UIUserInterfaceStyle = Light` in `Info.plist`. This is a decision, not an omission. The token set above is a flat list of literal colors used for roles that invert under a dark palette rather than translate into one: `color.surface` is the page background in some places and the text drawn on top of `color.textPrimary` or `color.accent` in others (the toast, the `Start conversation` label, a recording PTT control). Swapping the token values would make those pairings white-on-white rather than correct them, so a dark variant is a redesign of the pairings and not a palette edit. Until that redesign happens, declaring the light appearance is the honest option: someone whose phone is in dark mode gets the design as drawn, instead of a screen that is illegible in the places nobody checked. Do not add a theme switcher.

### Dynamic Type

Every surface has to survive the accessibility text sizes, and the rule is the same everywhere: text wraps and containers scroll, text is not truncated or shrunk. Truncation is the failure mode that matters here, because these strings are short and load bearing: a status line reading `Translation Model Unavailable` cut to `Translation Model` says the opposite of what it means, and a chip reading `A · Traditional Chinese` cut to `A · Tradi…` names no language at all.

- **Wrapping**: every status line, banner line, settings row title and subtitle, hint, and toast wraps to as many lines as it needs.
- **Scrolling**: the settings drawer panel and the full-surface first-run steps scroll once their content outgrows the phone, and the consent card scrolls inside itself so its two actions are never pushed past the bottom edge. The first-run steps stay vertically centered while they fit and switch to scrolling only when they do not, so the default sizes look exactly as they did.
- **The one exception**: the language chips, which share one row, are allowed two lines and a small shrink. A chip is the one place where unlimited wrapping would turn the language bar into four rows and push the transcript off the screen.

## Android/iOS parity criteria

| Scenario | Same result on both platforms |
| --- | --- |
| Very first launch ever | The welcome appears before anything else, `Get started` leads into the permission priming, and neither is ever shown again |
| Cold start with permissions granted | No first-run surface appears; the top language bar shows one chip per speaker, A left and B right, plus a single `Start conversation` / `Start Session` action |
| Start session with no local model | The download consent card names `about 1.9 GB`, warns about Wi-Fi on a costly path, and starts nothing until `Download now`. Android reads "no local model" from `model.hasEverLoaded` and the path cost from `isActiveNetworkMetered` |
| Start session with the model already on disk | No consent step; the session loads locally and the banner shows `Preparing translation model` with an indeterminate spinner |
| Start session | The banner reports model progress on the same screen; a real download names its percent and approximate transferred amount; PTT and chips stay locked until the model is ready |
| Start A | A partial bubble on the left and active-A state; B control disabled with explanatory text |
| Start B | B partial bubble on the right and active-B state; A control disabled with explanatory text |
| Release or tap stop | Final result received before stopping stays pending; after stopping, source text finalizes and translation queues for the other speaker's language |
| Translation succeeds | Source text, target language, and translated text appear in one bubble |
| Change a reading language mid-session | The chip updates, that speaker's recognition language re-aligns to the matching recognizer when the device has one, the model is not reloaded, and only later utterances use the new target |
| Change a recognition language mid-session | The `Spoken language` section updates and the new language is used from the next utterance start |
| Change a language during an utterance | Both speakers' chips are disabled until the utterance finishes translating |
| STT unsupported or permission denied | Do not start; show cause and recovery action inline; do not switch to network recognition |
| Model loading or translation fails | Preserve source text when available; do not invent a translation; show a retryable error in place |
| End session | Stop recognition, stop the work the session started, and clear the prior conversation, then return the same screen to its idle state. The model stays resident, so the next `Start conversation` / `Start Session` reaches `ready` without loading again |
| End session while the model is downloading | The transfer stops, not just the screen watching it. Ending a session someone declined halfway through must not leave a 1.9 GB download running on their cellular connection with nothing on screen to say so. Any translation still in flight stops with it |
| Open the settings drawer from the wordmark | The drawer slides in over an unchanged main screen, offers `Visit zetic.ai`, `Contact us`, and the About block, and closes without touching session state |
| Leave a live session idle on screen | The display stays lit for as long as the A/B controls are on screen, and dims normally in every other state |
| Background the app mid-session | The screen hold is released immediately and taken again on return |
| Hold and release a push-to-talk control | A firm tap on press and a lighter one on release, with a soft tick when that turn's translation arrives |
| Long-press a chat bubble | One `Copy` action puts the translation, or the transcript when there is no translation yet, on the clipboard and shows the `Copied` toast |
| Translation succeeds with sound on | iOS only for now: the translation is spoken once in the recipient's reading language, cutting off any translation still being spoken. Android parity is pending |
| Translation succeeds with sound off | iOS only for now: nothing is spoken and every replay control is disabled; the bubble is unchanged. Android parity is pending |
| Tap a bubble's replay glyph | iOS only for now: that translation is spoken again; the glyph is absent on bubbles with no finished translation. Android parity is pending |
| Start a turn while a translation is being spoken | iOS only for now: speech stops immediately and the microphone opens; the audio session is never held by both. Android parity is pending |
| Relaunch after changing a reading language | iOS only for now: both chips come back as they were left, with the spoken language derived from the restored reading language. Android parity is pending |
| Relaunch after overriding a spoken language | iOS only for now: the override comes back; a stored recognizer the device no longer has re-derives from the reading chip instead. Android parity is pending |
| Type a message and send it | iOS only for now: the same bubble, target language, request, and spoken translation a released push-to-talk control would have produced. Android parity is pending |
| Open typed input while an utterance is in flight | iOS only for now: the keyboard control is disabled under exactly the push-to-talk rule, with the same explanatory text. Android parity is pending |
| Clear the conversation from the drawer | The transcript empties, the session, model, and both chips are untouched, and the `Conversation cleared` toast appears |
| A call arrives mid-utterance | iOS only for now: the in-flight bubble is discarded, the session returns to idle with the `Interrupted. Tap to talk again.` note, and the next push-to-talk records normally. Android parity is pending |
| Delete the downloaded model | iOS only for now: the confirmation names the size, the delete removes only that model's artifacts and index records, and the next `Start conversation` shows the download consent again. Android has no `Storage` row until the Melange Android SDK can be asked what is cached |
| Open the drawer and read the `App language` row | iOS only for now: the row names the language in force, defaulting to `System`. Android parity is pending |
| Choose an app language | iOS only for now: the choice is remembered, the toast says it applies fully after reopening the app, and the session, model, transcript, and both chips are untouched. Android parity is pending |
| Run the app on a phone set to French or Spanish | iOS only for now: the interface falls back to English string by string, because those languages are declared but not yet populated. Android parity is pending |

## Verification

- Every control has an equivalent accessibility label.
- Body text and state text do not clip or overlap at larger text sizes and Dynamic Type sizes; the language bar keeps both chips reachable rather than overlapping them.
- A/B active state, processing, and errors are distinguished with text, alignment, and layout in addition to color; removing all color leaves the screen fully usable.
- The `ZETIC` wordmark is the settings control, exposes the accessibility label `ZETIC, opens settings`, and reads as tappable through its chevron.
- Opening the drawer leaves the session state, the conversation, and both language chips untouched; closing it by scrim tap, close control, or trailing swipe returns to exactly the screen that was there before.
- Copying the contact address puts `contact@zetic.ai` on the system clipboard and shows the `Email address copied` toast, which disappears on its own.
- The welcome and the consent card are fully navigable with a screen reader: every control carries a label, and each surface is announced as modal so the screen behind it is not reachable while it is up.
- The welcome appears on a first-ever launch and never again after `Get started`, across a relaunch.
- With no local model, the first `Start conversation` shows the consent card and downloads nothing until `Download now`; with a local model present no consent card appears at all.
- No user-facing string in the first-run flow or the session-comfort behaviors contains an em dash.
- The keep-awake decision and the haptic vocabulary are covered by unit tests state by state and event by event on both platforms, even though the idle timer, the Taptic Engine, and Android's `performHapticFeedback` are only verifiable on a device. Android also unit tests the first-run step selection, the consent decision including its metered path, and the copyable-text rule; its Compose UI tests need an emulator and are not part of the JVM verification bar.
- Long-pressing a bubble and choosing `Copy` shows the `Copied` toast above the push-to-talk row, and the toast disappears on its own.
- A finished translation is spoken once, in the recipient's reading language; a newer one cuts off an older one; muting suppresses both the announcement and every replay; and beginning a turn stops speech before the microphone opens. The voice-matching chain and the audio-session handoff are covered by unit tests over injected seams, even though the voice and the audio route themselves are only verifiable on a device.
- No user-facing string in the spoken-output controls contains an em dash.
- Choosing a reading language re-aligns that speaker's recognition language to the matching installed recognizer, on both platforms, at first resolution and on every later change; a reading language the device has no recognizer for leaves the recognition language as it was, and an explicit recognition choice stands until that speaker's reading language changes again. The matcher and the coupling are covered by unit tests on both platforms, including the variant preference (`fr` over `fr-BE`, `zh-Hant` over `zh-CN`).
- Ending a session leaves the model resident on both platforms, so a second `Start conversation` / `Start Session` in the same launch loads nothing; the model is released only when the screen's owner goes away. Covered by unit tests on both platforms.
- Both speakers' language selections come back after a relaunch. An explicit spoken-language override survives; a spoken language that was only ever the derived default, and a stored recognizer identifier the device no longer offers, both re-derive from the restored reading language. The restore rule is covered by unit tests case by case, including the stale-identifier case.
- A typed message produces exactly the bubble, target language, Hy-MT2 request, and spoken translation the speech path produces for the same text; a unit test compares the two requests directly rather than trusting that they were written the same way. The typed control and the send action are locked under the same rule as push-to-talk.
- The typed-input sheet is fully navigable with a screen reader: the speaker control, the guidance line, the field, `Cancel`, and `Send` each carry a label, and the sheet is announced as modal.
- Clearing the conversation from the drawer empties the transcript, leaves the session state, the model, and both language chips untouched, and shows the `Conversation cleared` toast; the row is disabled with nothing to clear and while an utterance is in flight.
- No user-facing string in the typed-input sheet or the clear action contains an em dash.
- An interruption arriving while recording or finalizing discards the in-flight bubble, leaves every earlier bubble and the loaded model alone, shows the note, and leaves the next push-to-talk working. An interruption while a translation is being spoken stops only the speech. An interruption ending never starts listening. The whole decision table is covered by unit tests state by state over an injected interruption seam, even though the interruption itself is only verifiable on a device.
- The `Storage` row reports the model's footprint, is disabled with nothing downloaded and while a session holds the model, and deletes only behind its confirmation. The size reading, the deletion's containment rules (an unreadable index and a model key outside the artifacts root are both refused), the survival of the backend-selection records and staging locks, and the consent gate re-arming afterwards are covered by unit tests over a cache fixture.
- A turn the recognizer heard nothing in returns the session to `ready` with the `No speech was recognized. Tap to talk again.` note rather than leaving `finalizing*` with no exit, and the next push-to-talk works. Covered by a unit test that sends the empty final the platform recognizer synthesizes, both before and after the control is released.
- The `Storage` row is disabled in every state that holds the model, including the two a session-liveness flag misses: the model loading, and the model still resident after `End session`. Covered by a unit test that reads the row's state out of a real view model rather than passing the predicate in.
- Ending a session mid-download stops the transfer and any translation in flight, and a close arriving while the model is still being built releases that model rather than installing it into a runtime nobody wants. The close-during-load interleaving is covered by a unit test over an injected model factory; the deinit's non-blocking release is covered by a test that occupies the runtime's queue the way a load does.
- No user-facing string in the interruption note, the empty-turn note, or the storage row contains an em dash.
- Every user-facing string comes out of the String Catalog: a test resolves a sample of explicitly keyed entries and fails if a lookup falls through to its own key, which is what a missing or uncompiled catalog looks like. A second test checks the compiled catalog is actually in the app bundle.
- The whole catalog is scanned rather than sampled: every key and every value is free of em dashes and en dashes, every entry carries a translator comment, no entry is stale, and English is the only populated language until the French and Spanish passes land.
- The app-language override writes both halves that have to agree, the remembered value and the platform's `AppleLanguages` key, and choosing `System` removes the override rather than pinning the current device language. A stored language this build no longer offers falls back to `System`. All of it is covered by unit tests against a throwaway preferences domain, so no test can leave an override behind for the next run.
- UI tests force the app back to the device language on every launch, so the English strings they assert against are the ones that are actually rendered.
- Every surface is checked at the largest accessibility text size: nothing truncates, nothing overlaps, no action falls off the bottom edge, and no content rides up over the status bar.
- Android and iOS capture and compare the parity-table scenarios plus the idle, live, and error variants of the single screen using the same inputs.
