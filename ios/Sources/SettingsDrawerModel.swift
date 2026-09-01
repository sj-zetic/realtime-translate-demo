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
  static let clearConversationTitle = "Clear conversation"
  static let clearConversationSubtitle = "Keeps the session and the languages"
  static let clearConversationConfirmation = "Conversation cleared"

  @Published private(set) var isOpen = false
  /// What the model occupies right now. Re-read every time the drawer opens and again after a
  /// delete, so the row is never quoting a size from three sessions ago.
  @Published private(set) var storage: LocalModelStore.Footprint = .none
  /// Drives the app's one `confirmationDialog`. A `var` because the dialog binds to it and closes
  /// itself by writing false.
  @Published var isConfirmingDelete = false

  let appInfo: AppInfo
  /// The drawer shares the app's one toast behaviour rather than owning a second one.
  let toasts: ToastCenter

  var toast: String? { toasts.message }

  private let pasteboard: SettingsPasteboard
  private let openURL: (URL) -> Void
  private let modelStorage: any ModelStorageManaging

  init(
    appInfo: AppInfo = .main,
    pasteboard: SettingsPasteboard = SystemPasteboard(),
    toastDuration: TimeInterval = ToastCenter.defaultDuration,
    openURL: @escaping (URL) -> Void = { UIApplication.shared.open($0) },
    announce: @escaping (String) -> Void = {
      UIAccessibility.post(notification: .announcement, argument: $0)
    },
    modelStorage: (any ModelStorageManaging)? = nil
  ) {
    self.appInfo = appInfo
    self.pasteboard = pasteboard
    self.openURL = openURL
    self.modelStorage = modelStorage ?? LocalModelStorage()
    toasts = ToastCenter(duration: toastDuration, announce: announce)
  }

  /// The app's composition root for the drawer. Only the storage seam is forced from the command
  /// line, so a UI test can drive the row and its confirmation without a 1.9 GB model.
  static func fromLaunchArguments(
    _ arguments: [String] = ProcessInfo.processInfo.arguments
  ) -> SettingsDrawerModel {
    SettingsDrawerModel(modelStorage: FixedModelStorage.fromLaunchArguments(arguments))
  }

  /// Opening re-reads the disk, because the drawer is the only place that number is shown and a
  /// download may have finished since the last look.
  func open() {
    refreshStorage()
    isOpen = true
  }

  func close() { isOpen = false }

  // MARK: - Model storage

  func refreshStorage() { storage = modelStorage.footprint() }

  func storageRow(isSessionLive: Bool) -> ModelStorageRow {
    ModelStorageRow.row(footprint: storage, isSessionLive: isSessionLive)
  }

  /// The row does not delete. It asks, and the dialog deletes: this is the only destructive action
  /// in the app and the only one that cannot be undone from inside it.
  func confirmDeleteModel() { isConfirmingDelete = true }

  /// Deletes and re-reads, so the row itself becomes the confirmation. The drawer stays open on
  /// purpose, unlike the clear row: the thing worth seeing afterwards is this row saying the model
  /// is gone, not the screen behind it.
  func deleteModel() {
    isConfirmingDelete = false
    let outcome = modelStorage.deleteModel()
    refreshStorage()
    guard outcome == .deleted else { return }
    toasts.show(ModelStorageCopy.deleted)
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
