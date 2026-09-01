import SwiftUI

@main
struct RealtimeTranslateApp: App {
  var body: some Scene {
    WindowGroup {
      RealtimeTranslateRootView(viewModel: .fromLaunchArguments())
    }
  }
}
