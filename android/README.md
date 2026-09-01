# Android app

The Android implementation uses Kotlin and Jetpack Compose. Speech recognition uses the device's on-device recognizer with automatic language detection where the OS provides it; the app does not publish a fixed source-language list. Translation targets are the 38 languages listed by Hy-MT2. Screen state, design tokens, and accessibility rules follow the [shared UX and design specification](../docs/shared-ux-spec.md).
