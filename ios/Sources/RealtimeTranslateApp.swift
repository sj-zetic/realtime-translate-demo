import SwiftUI

@main
struct RealtimeTranslateApp: App {
  /// The first-run flags and the remembered languages are forced before any view or view model
  /// reads them, so a UI test's very first render already sees the state it asked for.
  init() {
    FirstRunDefaults.applyLaunchArguments()
    LanguagePreferenceDefaults.applyLaunchArguments()
    // `-resetAppLanguage` first, so a reset run cannot then re-apply the override it just cleared.
    // `applyStored` keeps `AppleLanguages` in step with the remembered choice; iOS has already read
    // that key for this launch, which is exactly why the row promises "after reopening the app".
    AppLanguageDefaults.applyLaunchArguments()
    AppLanguageDefaults.applyStored()
  }

  var body: some Scene {
    WindowGroup {
      RealtimeTranslateRootView(viewModel: .fromLaunchArguments())
    }
  }
}
