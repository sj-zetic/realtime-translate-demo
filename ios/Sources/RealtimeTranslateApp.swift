import SwiftUI

@main
struct RealtimeTranslateApp: App {
  /// The first-run flags and the remembered languages are forced before any view or view model
  /// reads them, so a UI test's very first render already sees the state it asked for.
  init() {
    FirstRunDefaults.applyLaunchArguments()
    LanguagePreferenceDefaults.applyLaunchArguments()
  }

  var body: some Scene {
    WindowGroup {
      RealtimeTranslateRootView(viewModel: .fromLaunchArguments())
    }
  }
}
