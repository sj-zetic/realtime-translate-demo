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
    displayName = name ?? fallbackName ?? AppText.productName
    version = info?["CFBundleShortVersionString"] as? String ?? "1.0"
    build = info?["CFBundleVersion"] as? String ?? "1"
  }

  static var main: AppInfo { AppInfo(info: Bundle.main.infoDictionary) }

  /// One terse line for the About block: `Version 1.0 (1)`.
  var versionLine: String {
    String(localized: "about.versionLine", defaultValue: "Version \(version) (\(build))",
           comment: "About block. %1$@ is the marketing version, %2$@ the build number")
  }
}

/// Drawer state and the two side effects its rows perform. Kept out of the view so the
/// clipboard copy and the toast can be exercised without driving the UI.
@MainActor
final class SettingsDrawerModel: ObservableObject {
  /// An address and a URL, so neither is a catalog entry.
  static let contactEmail = "contact@zetic.ai"
  static let website = URL(string: "https://zetic.ai")!

  static var copyConfirmation: String {
    String(localized: "Email address copied",
           comment: "Toast after the Contact us row copies the address")
  }
  static var privacyLine: String {
    String(localized: "Speech, translation, everything stays on this phone.",
           comment: "Settings drawer About block, body text")
  }
  static var clearConversationTitle: String {
    String(localized: "Clear conversation", comment: "Settings drawer row title")
  }
  static var clearConversationSubtitle: String {
    String(localized: "Keeps the session and the languages",
           comment: "Settings drawer row subtitle under Clear conversation")
  }
  static var clearConversationConfirmation: String {
    String(localized: "Conversation cleared", comment: "Toast after the transcript is emptied")
  }

  /// The drawer's language row, spelled out here so the accessibility label and the visible row
  /// can never disagree about the fixed words between them.
  static func clearConversationAccessibilityLabel(isEnabled: Bool) -> String {
    isEnabled
      ? String(localized: "settings.clearConversation.accessibility.available",
               defaultValue: "\(clearConversationTitle), keeps the session and the languages",
               comment: "Accessibility label for the Clear conversation row. %@ is the row title")
      : String(localized: "settings.clearConversation.accessibility.unavailable",
               defaultValue: "\(clearConversationTitle), unavailable, there is nothing to clear",
               comment: "Accessibility label for the disabled Clear conversation row. %@ is the row title")
  }

  @Published private(set) var isOpen = false

  let appInfo: AppInfo
  /// The drawer shares the app's one toast behaviour rather than owning a second one.
  let toasts: ToastCenter

  var toast: String? { toasts.message }

  private let pasteboard: SettingsPasteboard
  private let openURL: (URL) -> Void
  /// Where the app-language override is written. Injected so a test never touches the preferences
  /// the host app and the UI tests are running out of.
  private let languageDefaults: UserDefaults

  init(
    appInfo: AppInfo = .main,
    pasteboard: SettingsPasteboard = SystemPasteboard(),
    toastDuration: TimeInterval = ToastCenter.defaultDuration,
    openURL: @escaping (URL) -> Void = { UIApplication.shared.open($0) },
    announce: @escaping (String) -> Void = {
      UIAccessibility.post(notification: .announcement, argument: $0)
    },
    languageDefaults: UserDefaults = .standard
  ) {
    self.appInfo = appInfo
    self.pasteboard = pasteboard
    self.openURL = openURL
    self.languageDefaults = languageDefaults
    toasts = ToastCenter(duration: toastDuration, announce: announce)
  }

  func open() { isOpen = true }

  func close() { isOpen = false }

  // MARK: - App language

  /// What the language row shows right now.
  var appLanguage: AppLanguage { AppLanguageDefaults.stored(languageDefaults) }

  /// Records the choice, writes the `AppleLanguages` override iOS reads at launch, and says so.
  /// Choosing the language that is already selected is not a change, so it confirms nothing: a
  /// toast about reopening the app would be a lie about a tap that did nothing.
  ///
  /// The drawer deliberately stays open, unlike the clear row: the thing worth seeing afterwards is
  /// this row showing the new language, and the toast lives outside the panel either way.
  func selectAppLanguage(_ language: AppLanguage) {
    guard language != appLanguage else { return }
    AppLanguageDefaults.apply(language, to: languageDefaults)
    toasts.show(AppLanguageCopy.restartNotice)
  }

  func openWebsite() { openURL(Self.website) }

  /// Copies the contact address and confirms it with a self-dismissing toast.
  func copyContactEmail() {
    pasteboard.write(Self.contactEmail)
    toasts.show(Self.copyConfirmation)
  }

  /// Runs the caller's clear and confirms it the same way every other drawer action confirms.
  /// The drawer closes first, because the whole point of the row is to look at the emptied
  /// transcript; the toast lives outside the panel, so it survives the close.
  func clearConversation(_ clear: () -> Void) {
    clear()
    close()
    toasts.show(Self.clearConversationConfirmation)
  }
}
