import Foundation
import UIKit

/// Anything that can receive copied text. `UIPasteboard` in the app, a spy in tests.
protocol SettingsPasteboard {
  func write(_ text: String)
}

struct SystemPasteboard: SettingsPasteboard {
  func write(_ text: String) { UIPasteboard.general.string = text }
}

/// The About block's facts, read from the bundle so the drawer never hardcodes a version.
struct AppInfo: Equatable {
  let displayName: String
  let version: String
  let build: String

  /// Reads `CFBundleDisplayName`, falling back to `CFBundleName` and then the product name.
  init(info: [String: Any]?) {
    let name = info?["CFBundleDisplayName"] as? String
    let fallbackName = info?["CFBundleName"] as? String
    displayName = name ?? fallbackName ?? "Turn Translate"
    version = info?["CFBundleShortVersionString"] as? String ?? "1.0"
    build = info?["CFBundleVersion"] as? String ?? "1"
  }

  static var main: AppInfo { AppInfo(info: Bundle.main.infoDictionary) }

  /// One terse line for the About block: `Version 1.0 (1)`.
  var versionLine: String { "Version \(version) (\(build))" }
}

/// Drawer state and the two side effects its rows perform. Kept out of the view so the
/// clipboard copy and the toast can be exercised without driving the UI.
@MainActor
final class SettingsDrawerModel: ObservableObject {
  static let contactEmail = "contact@zetic.ai"
  static let website = URL(string: "https://zetic.ai")!
  static let copyConfirmation = "Email address copied"
  static let privacyLine = "Speech, translation, everything stays on this phone."

  @Published private(set) var isOpen = false
  @Published private(set) var toast: String?

  let appInfo: AppInfo

  private let pasteboard: SettingsPasteboard
  private let openURL: (URL) -> Void
  private let announce: (String) -> Void
  private let toastDuration: TimeInterval
  private var toastTask: Task<Void, Never>?

  init(
    appInfo: AppInfo = .main,
    pasteboard: SettingsPasteboard = SystemPasteboard(),
    toastDuration: TimeInterval = 2,
    openURL: @escaping (URL) -> Void = { UIApplication.shared.open($0) },
    announce: @escaping (String) -> Void = {
      UIAccessibility.post(notification: .announcement, argument: $0)
    }
  ) {
    self.appInfo = appInfo
    self.pasteboard = pasteboard
    self.toastDuration = toastDuration
    self.openURL = openURL
    self.announce = announce
  }

  func open() { isOpen = true }

  func close() { isOpen = false }

  func openWebsite() { openURL(Self.website) }

  /// Copies the contact address and confirms it with a self-dismissing toast.
  func copyContactEmail() {
    pasteboard.write(Self.contactEmail)
    showToast(Self.copyConfirmation)
  }

  private func showToast(_ message: String) {
    toastTask?.cancel()
    toast = message
    announce(message)
    let duration = toastDuration
    toastTask = Task { [weak self] in
      try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
      guard !Task.isCancelled else { return }
      self?.toast = nil
    }
  }
}
