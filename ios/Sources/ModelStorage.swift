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
  static let title = "Storage"
  static let empty = "No model downloaded"
  static let deleteAction = "Delete downloaded model"
  static let keepAction = "Keep it"
  static let confirmationTitle = "Delete the downloaded model?"
  static let sessionLive = "End the session first"
  static let deleted = "Model deleted"

  /// The one place a byte count becomes words, so the row, the confirmation, and the accessibility
  /// label can never disagree about how big the model is.
  static func size(bytes: Int64) -> String {
    ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
  }

  static func onThisPhone(_ size: String) -> String { "\(size) on this phone" }

  /// Says what is reclaimed and what it costs, because the cost is the part someone deleting a
  /// model at the airport needs to hear before they tap.
  static func confirmationMessage(_ size: String) -> String {
    "This frees \(size). The next session downloads the model again."
  }
}

// MARK: - The row

/// What the storage row shows and whether it can be tapped. A pure function of two facts, so the
/// three states (nothing downloaded, downloaded but in use, downloaded and idle) are a test table.
struct ModelStorageRow: Equatable {
  let subtitle: String
  let isEnabled: Bool
  let accessibilityLabel: String

  /// A model on disk with no session holding it in memory is the only state that can be deleted.
  /// The other two keep the row exactly where it is and say why, rather than hiding it: a row that
  /// comes and goes is a row nobody can find twice.
  static func row(footprint: LocalModelStore.Footprint, isSessionLive: Bool) -> ModelStorageRow {
    guard !footprint.isEmpty else {
      return ModelStorageRow(
        subtitle: ModelStorageCopy.empty, isEnabled: false,
        accessibilityLabel: "\(ModelStorageCopy.title), \(ModelStorageCopy.empty)"
      )
    }
    let occupies = ModelStorageCopy.onThisPhone(ModelStorageCopy.size(bytes: footprint.totalBytes))
    guard !isSessionLive else {
      return ModelStorageRow(
        subtitle: "\(occupies). \(ModelStorageCopy.sessionLive).", isEnabled: false,
        accessibilityLabel:
          "\(ModelStorageCopy.title), \(occupies), unavailable, \(ModelStorageCopy.sessionLive)"
      )
    }
    return ModelStorageRow(
      subtitle: occupies, isEnabled: true,
      accessibilityLabel: "\(ModelStorageCopy.title), \(occupies), \(ModelStorageCopy.deleteAction)"
    )
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
