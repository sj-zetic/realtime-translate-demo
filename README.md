# Turn Translate

Turn Translate is an on-device, two-speaker push-to-talk translation app for Android and iOS.

Each person selects their utterance with the A or B button. The app recognizes the selected person's source text with platform on-device STT, then translates only finalized text into the other person's reading language with `SJ_zetic/Hy-MT2-1.8B`. Automatic speaker separation and simultaneous speech recognition are not supported.

Both apps follow the same conversation flow and design tokens while using native platform UI. Everything lives on one screen: a per-speaker language chip bar at the top, a chat transcript with speaker A on the left and speaker B on the right, the A and B push-to-talk buttons at the bottom, and an inline banner for permissions, model loading, and errors. A session still follows `setup` -> `model loading` -> `ready` -> `end and unload` -> `setup`; those states are now regions of the same screen rather than separate destinations.

The visual system is ZETIC minimal: white surfaces, `#0A0A0A` text, `#6B6B6B` supporting text, `#E8E8E8` hairline dividers, and the teal brand accent `#2DBDB2` on the start action and model-load progress. On top of that, each speaker owns one muted family drawn from the same brand system — speaker A teal (`#2DBDB2` / `#17877D` / `#E9F7F5` / `#BFE7E2`), speaker B ink (`#0A0A0A` / `#F0F0F0` / `#E8E8E8`) — applied consistently to that speaker's language chip, chat bubbles, and push-to-talk button. Color is always redundant with the speaker labels and left/right alignment. The header carries the official ZETIC logo lockup as a bundled image asset on both platforms.

## Documentation

- [MVP plan](docs/mvp-plan.md)
- [Shared UX and design specification](docs/shared-ux-spec.md)
- [Hy-MT2 translation reference](docs/hy-mt2-integration-reference.md)

## Implementation directories

- `android/`: Kotlin and Jetpack Compose app
- `ios/`: Swift and SwiftUI app

STT uses Android and iOS on-device speech recognition. A speaker can choose `Automatic` or an OS-derived on-device recognition language; the app does not impose a source-language list, download speech models, or fall back to network STT. Android API 33 and later lists installed on-device locales, Android API 31-32 offers `Automatic`, and iOS lists only supported locales that are on-device capable. The reading-language chip uses the 38 official Hy-MT2 entries documented in `docs/hy-mt2-integration-reference.md`.

Each speaker has one chip in the top language bar, showing `<speaker> · <reading language>`; one tap opens a menu with a `Reading language` section and a secondary `Spoken language` section. Languages can be changed before, between, and during a session without reloading the model: a reading-language change affects future translation prompts only, and a recognition-language change applies at the next utterance start. Both speakers' chips are locked while an utterance is recording, finalizing, or translating. Defaults are `Automatic` recognition with English for A and Korean for B, so a first session costs one tap when permissions are granted.

At session start, both apps load `SJ_zetic/Hy-MT2-1.8B` with Melange SDK `1.10.0`. Model loading exposes progress, failure, and retry states inline on the main screen; the PTT controls become available only after the model is ready. Finalized source text is translated serially through the loaded model. Ending a session waits for model cleanup and close, then clears the prior conversation and returns the same screen to its idle state.

The Melange personal key is supplied from the build environment as `MELANGE_PERSONAL_KEY`. It is absent from source control and logs, but is embedded in a development app binary to initialize the SDK. That approach is not appropriate for production distribution; production requires rotatable credential provisioning. Do not commit the key, model artifacts, or other credentials. The existing Android application ID, iOS bundle ID, and iOS signing configuration remain unchanged.
