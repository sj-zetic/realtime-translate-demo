import Foundation

/// The settings drawer's storage row: how much of this phone the translation model is using, and
/// the one destructive action the app has.
///
/// A 1.9 GB model is the largest thing this app ever puts on someone's phone, and until now the
/// only way to get it back was to delete the app. So the drawer says how much it is holding and
/// offers to give it back, behind a confirmation, and never while a session has that model loaded
/// in memory. Everything except the confirmation dialog itself lives here, so the copy, the
/// enablement, and the delete are exercised without driving the UI.

// MARK: - Copy

enum ModelStorageCopy {
  static var title: String {
    String(localized: "Storage", comment: "Settings drawer row title for the downloaded model")
  }
  static var empty: String {
    String(localized: "No model downloaded", comment: "Storage row subtitle when nothing is on disk")
  }
  static var deleteAction: String {
    String(localized: "Delete downloaded model", comment: "Destructive button in the delete confirmation")
  }
  static var keepAction: String {
    String(localized: "Keep it", comment: "Cancel button in the delete confirmation")
  }
  static var confirmationTitle: String {
    String(localized: "Delete the downloaded model?", comment: "Delete confirmation dialog title")
  }
  static var sessionLive: String {
    String(localized: "End the session first",
           comment: "Storage row subtitle while a session holds the model in memory")
  }
  /// The other way the model is held: loaded, or being loaded, with no session on screen to end.
  /// It stays in memory after `End Session` so the next start is instant, and deleting the files
  /// under it is exactly the state that leaves the app translating from a model it no longer has.
  static var modelInMemory: String {
    String(localized: "The app is using it right now",
           comment: "Storage row subtitle while the model is in memory outside a live session")
  }
  static var deleted: String {
    String(localized: "Model deleted", comment: "Toast after the model is removed from disk")
  }

  /// The one place in the whole app a byte count becomes words: this row, its confirmation, its
  /// accessibility label, the download consent card, and the transfer line under the progress bar.
  /// `ByteCountFormatter` localizes the unit and the decimal separator on its own, so nothing here
  /// has to.
  ///
  /// `.file` is decimal, which is what iOS itself, the App Store, and Finder all count in, so the
  /// figure here is the figure someone will see in Settings for the same file. It used to be one
  /// of two: the row formatted the real bytes while the consent card carried a hand-written
  /// `1.9 GB`, and the same model introduced itself as one size and then took up another.
  static func size(bytes: Int64) -> String {
    ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
  }

  static func onThisPhone(_ size: String) -> String {
    String(localized: "storage.onThisPhone", defaultValue: "\(size) on this phone",
           comment: "Storage row subtitle. %@ is a formatted size such as 1.9 GB")
  }

  /// Says what is reclaimed and what it costs, because the cost is the part someone deleting a
  /// model at the airport needs to hear before they tap.
  static func confirmationMessage(_ size: String) -> String {
    String(localized: "storage.confirmationMessage",
           defaultValue: "This frees \(size). The next session downloads the model again.",
           comment: "Delete confirmation body. %@ is a formatted size such as 1.9 GB")
  }

  /// The disabled row's accessibility label. The only one of the three that contains fixed words
  /// of its own; the other two are commas between pieces that are already translated.
  static func lockedAccessibilityLabel(occupies: String, reason: String) -> String {
    String(localized: "storage.accessibility.locked",
           defaultValue: "\(title), \(occupies), unavailable, \(reason)",
           comment: "Locked Storage row accessibility label. %1$@ row title, %2$@ size, %3$@ reason")
  }
}

// MARK: - The row

/// What the storage row shows and whether it can be tapped. A pure function of two facts, so the
/// three states (nothing downloaded, downloaded but in use, downloaded and idle) are a test table.
struct ModelStorageRow: Equatable {
  /// What is holding the model, which is the only thing that decides whether it can be deleted.
  ///
  /// Two held states rather than one, because they have different remedies and only one of them
  /// is a session. `session` is a live session the person can end from the screen behind the
  /// drawer. `memory` is the model loading, or still resident after `End Session`, where there is
  /// nothing on screen to end and the row can only say that the app is still holding it.
  enum Hold: Equatable {
    case free
    case session
    case memory
  }

  let subtitle: String
  let isEnabled: Bool
  let accessibilityLabel: String

  /// A model on disk that nothing is holding is the only state that can be deleted. The others
  /// keep the row exactly where it is and say why, rather than hiding it: a row that comes and
  /// goes is a row nobody can find twice.
  static func row(footprint: LocalModelStore.Footprint, hold: Hold) -> ModelStorageRow {
    guard !footprint.isEmpty else {
      return ModelStorageRow(
        subtitle: ModelStorageCopy.empty, isEnabled: false,
        accessibilityLabel: "\(ModelStorageCopy.title), \(ModelStorageCopy.empty)"
      )
    }
    let occupies = ModelStorageCopy.onThisPhone(ModelStorageCopy.size(bytes: footprint.totalBytes))
    switch hold {
    case .free:
      return ModelStorageRow(
        subtitle: occupies, isEnabled: true,
        accessibilityLabel: "\(ModelStorageCopy.title), \(occupies), \(ModelStorageCopy.deleteAction)"
      )
    case .session, .memory:
      let reason = hold == .session ? ModelStorageCopy.sessionLive : ModelStorageCopy.modelInMemory
      return ModelStorageRow(
        subtitle: "\(occupies). \(reason).", isEnabled: false,
        accessibilityLabel: ModelStorageCopy.lockedAccessibilityLabel(occupies: occupies, reason: reason)
      )
    }
  }
}

// MARK: - The seam

/// Anything that can report and remove this app's model. `LocalModelStore` in the app, a fixture
/// in tests and under the `-modelStorage` launch argument, so the row and its confirmation can be
/// driven without a real 1.9 GB download sitting on the simulator.
@MainActor
protocol ModelStorageManaging: AnyObject {
  func footprint() -> LocalModelStore.Footprint
  func deleteModel() -> LocalModelStore.Deletion
}

@MainActor
final class LocalModelStorage: ModelStorageManaging {
  private let modelName: String

  init(modelName: String = FirstRunModel.modelName) {
    self.modelName = modelName
  }

  func footprint() -> LocalModelStore.Footprint {
    LocalModelStore.footprint(forModelName: modelName)
  }

  func deleteModel() -> LocalModelStore.Deletion {
    LocalModelStore.deleteModel(forModelName: modelName)
  }
}

/// A fixed reading that forgets its model when it is told to. Deletion here is the same state
/// change the real store performs, which is what lets a UI test watch the row go from a size to
/// "No model downloaded" without any of it being real.
@MainActor
final class FixedModelStorage: ModelStorageManaging {
  private(set) var deletions = 0
  private var stored: LocalModelStore.Footprint
  private let outcome: LocalModelStore.Deletion

  init(_ stored: LocalModelStore.Footprint, outcome: LocalModelStore.Deletion = .deleted) {
    self.stored = stored
    self.outcome = outcome
  }

  /// `-modelStorage <bytes>` puts a model of that size on the row. Absent, the drawer reads the
  /// real cache, which on a device is the whole point and on a test simulator is empty.
  static func fromLaunchArguments(
    _ arguments: [String] = ProcessInfo.processInfo.arguments
  ) -> (any ModelStorageManaging)? {
    guard let value = FirstRunDefaults.value(named: "-modelStorage", in: arguments),
          let bytes = Int64(value) else { return nil }
    return FixedModelStorage(LocalModelStore.Footprint(archiveBytes: bytes, moduleBytes: 0,
                                                       totalBytes: bytes))
  }

  func footprint() -> LocalModelStore.Footprint { stored }

  func deleteModel() -> LocalModelStore.Deletion {
    deletions += 1
    if outcome == .deleted { stored = .none }
    return outcome
  }
}
