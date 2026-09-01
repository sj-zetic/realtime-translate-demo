# iOS app

The iOS implementation uses Swift and SwiftUI. Screen state, design tokens, and accessibility rules follow the [shared UX and design specification](../docs/shared-ux-spec.md).

For a device build, provide `MELANGE_PERSONAL_KEY` as an Xcode build environment variable. The value is expanded into the built app's `Info.plist` so the installed demo can load its model; it is not tracked in this repository. Treat that demo artifact as credential-bearing and do not distribute it.
