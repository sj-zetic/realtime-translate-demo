# Android app

The Android implementation uses Kotlin and Jetpack Compose. Speech recognition uses the device's on-device recognizer with automatic language detection where the OS provides it; the app does not publish a fixed source-language list. Translation targets are the 38 languages listed by Hy-MT2. Screen state, design tokens, and accessibility rules follow the [shared UX and design specification](../docs/shared-ux-spec.md).

`RealtimeTranslateApp.kt` renders the whole product on one screen: a title and status strip, an inline session banner (permission, model progress, model-load failure and retry, unloading, runtime error), a `LazyColumn` of chat bubbles with speaker A left-aligned and speaker B right-aligned, and a bottom speaker bar with a `Speaks` chip, a `Reads` chip, and a push-to-talk control per speaker. `RealtimeTranslateTheme.kt` holds the ZETIC minimal tokens; the teal accent `#2DBDB2` is used only for the active recording control, the `Start conversation` action, and the model-load progress indicator.

`SessionViewModel` is unchanged by the redesign. The idle main screen is `SessionPhase.Ready` with `conversationStarted = false`, and the live main screen is `SessionPhase.Ready` with `conversationStarted = true`; the UI switches the session action and the push-to-talk lock on that flag rather than navigating.
