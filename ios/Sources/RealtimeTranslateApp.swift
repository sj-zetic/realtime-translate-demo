import SwiftUI

@main
struct RealtimeTranslateApp: App {
  /// The first-run flags are forced before any view reads `@AppStorage`, so a UI test's very first
  /// render already sees the state it asked for.
  init() { FirstRunDefaults.applyLaunchArguments() }

  var body: some Scene {
    WindowGroup {
      RealtimeTranslateRootView(viewModel: .fromLaunchArguments())
    }
  }
}
