import Foundation
import Network

/// Everything the first run of Turn Translate needs to decide what to show and when: the two
/// remembered flags, the step they imply, the model-download consent decision, and the copy the
/// first-run surfaces render. Kept out of the views so every decision is testable without UI.
///
/// The flow is three steps, each shown at most once and each skippable when it has nothing to say:
/// the welcome, the permission priming that precedes the system prompts, and the download consent
/// that precedes a genuine 1.9 GB transfer.

// MARK: - Remembered flags

/// The `@AppStorage` keys the first-run flow remembers, plus the launch-argument overrides UI tests
/// use to force each state instead of depending on whatever the simulator container happens to hold.
enum FirstRunDefaults {
  static let welcomeSeenKey = "firstRun.welcomeSeen"
  static let permissionPrimingSeenKey = "firstRun.permissionPrimingSeen"

  /// Applied before any view reads `@AppStorage`, so the very first render already sees the forced
  /// state. `-resetFirstRun` clears the flags on its own; `-firstRun` also selects the model
  /// presence the consent step keys off (see `FirstRunModel.fromLaunchArguments`).
  ///
  /// - `-resetFirstRun`: clear both flags.
  /// - `-firstRun fresh`: clear both flags, no local model.
  /// - `-firstRun returning`: set both flags, local model present.
  /// - `-firstRun consentNeeded`: set both flags, no local model.
  /// - `-firstRunCellular`: report the current network path as expensive.
  static func applyLaunchArguments(_ arguments: [String] = ProcessInfo.processInfo.arguments,
                                   to defaults: UserDefaults = .standard) {
    if arguments.contains("-resetFirstRun") { reset(defaults) }
    switch value(named: "-firstRun", in: arguments) {
    case "fresh": reset(defaults)
    case "returning", "consentNeeded": complete(defaults)
    default: break
    }
  }

  static func reset(_ defaults: UserDefaults = .standard) {
    defaults.set(false, forKey: welcomeSeenKey)
    defaults.set(false, forKey: permissionPrimingSeenKey)
  }

  static func complete(_ defaults: UserDefaults = .standard) {
    defaults.set(true, forKey: welcomeSeenKey)
    defaults.set(true, forKey: permissionPrimingSeenKey)
  }

  /// The value following `name` in a launch-argument list, or nil when the flag is absent or last.
  static func value(named name: String, in arguments: [String]) -> String? {
    arguments.drop { $0 != name }.dropFirst().first
  }
}

/// Which first-run surface belongs on screen before the main screen becomes usable.
enum FirstRunStep: Equatable {
  case none
  case welcome
  case permissionPriming

  /// The welcome always comes first. The priming follows only while the system prompts are still
  /// unanswered: a returning user who already granted access skips it silently.
  static func step(welcomeSeen: Bool, primingSeen: Bool, permissionNeeded: Bool) -> FirstRunStep {
    if !welcomeSeen { return .welcome }
    if !primingSeen, permissionNeeded { return .permissionPriming }
    return .none
  }
}

// MARK: - Network path

/// What the current network path costs. `NWPathMonitor` reports both flags and either one means a
/// 1.9 GB transfer is a poor idea right now, so the consent step suggests Wi-Fi instead.
struct NetworkPathCost: Equatable {
  var isExpensive: Bool
  var isConstrained: Bool

  var isCostly: Bool { isExpensive || isConstrained }

  static let unrestricted = NetworkPathCost(isExpensive: false, isConstrained: false)
  static let expensive = NetworkPathCost(isExpensive: true, isConstrained: false)
  static let constrained = NetworkPathCost(isExpensive: false, isConstrained: true)
}

protocol NetworkPathReporting: AnyObject {
  var currentCost: NetworkPathCost { get }
}

/// Live `NWPathMonitor` readings. The monitor delivers on its own queue, so the last reading is
/// held under a lock and read synchronously when the consent decision is made.
final class NetworkPathObserver: NetworkPathReporting, @unchecked Sendable {
  private let monitor = NWPathMonitor()
  private let lock = NSLock()
  private var cost: NetworkPathCost = .unrestricted

  var currentCost: NetworkPathCost {
    lock.lock()
    defer { lock.unlock() }
    return cost
  }

  init(queue: DispatchQueue = DispatchQueue(label: "ai.zetic.turntranslate.networkpath")) {
    monitor.pathUpdateHandler = { [weak self] path in
      guard let self else { return }
      lock.lock()
      cost = NetworkPathCost(isExpensive: path.isExpensive, isConstrained: path.isConstrained)
      lock.unlock()
    }
    monitor.start(queue: queue)
  }

  deinit { monitor.cancel() }
}

/// A fixed reading, for tests and for the `-firstRunCellular` launch argument.
final class FixedNetworkPath: NetworkPathReporting {
  let currentCost: NetworkPathCost
  init(_ cost: NetworkPathCost) { currentCost = cost }
}

// MARK: - Download size and consent

enum ModelDownloadSize {
  /// The measured size of the Hy-MT2 archive. User-facing copy always says "about 1.9 GB".
  /// Held in tenths because that is the unit the progress line is rounded to, and unlike 1.9 a
  /// whole number of tenths is exact in binary floating point.
  static let tenthsOfAGigabyte = 19
  static let total = "1.9 GB"
  static let approximate = "about 1.9 GB"
}

/// Whether starting a session has to ask first. A model already on disk loads locally in seconds
/// with no network at all, so the consent step exists only for a genuine first download.
enum ModelDownloadConsent {
  enum Decision: Equatable {
    case startImmediately
    case ask(cellularWarning: Bool)
  }

  static func decision(hasLocalModel: Bool, cost: NetworkPathCost) -> Decision {
    guard !hasLocalModel else { return .startImmediately }
    return .ask(cellularWarning: cost.isCostly)
  }
}

// MARK: - Model preparation progress

/// The two distinguishable model-preparation phases and the copy each one shows.
///
/// The distinguishing rule is the progress callback itself: the local load path never reports
/// progress, so only a value strictly between 0 and 1 proves bytes are moving over the network.
/// Anything else stays indeterminate and says "preparing" rather than promising a download.
struct ModelPreparationStatus: Equatable {
  let headline: String
  let detail: String?
  let progress: Double?

  var isDownloading: Bool { progress != nil }

  static func status(for progress: Double?) -> ModelPreparationStatus {
    guard let progress, progress > 0, progress < 1 else {
      return ModelPreparationStatus(headline: FirstRunCopy.preparingModel, detail: nil, progress: nil)
    }
    // Counted in whole tenths of a gigabyte, which are exact in binary, so half of a 1.9 GB archive
    // reads as the "1.0" a reader expects rather than the "0.9" that 0.5 * 1.9 formats to.
    let tenths = (progress * Double(ModelDownloadSize.tenthsOfAGigabyte)).rounded()
    let transferred = String(format: "%.1f", tenths / 10)
    return ModelPreparationStatus(
      headline: "\(FirstRunCopy.downloadingModel) \(Int((progress * 100).rounded()))%",
      detail: "\(transferred) of \(ModelDownloadSize.total)",
      progress: progress
    )
  }
}

// MARK: - Copy

/// Every first-run string in one place, in the app's terse voice and with no em dash anywhere.
enum FirstRunCopy {
  static let welcomeTitle = "Turn Translate"
  static let welcomeTagline = "Two people, two languages, one phone."
  static let welcomePrivacy = "Speech and translation run on this phone. Nothing is sent to a server."
  static let welcomeAction = "Get started"

  static let primingTitle = "Microphone and speech"
  static let primingMicrophone = "Microphone: to hear whoever is holding a button."
  static let primingSpeech = "Speech recognition: to turn that audio into text."
  static let primingPrivacy = "Both run on this phone. No audio and no text leave the device."
  static let primingNext = "iOS asks for each one next."
  static let primingAction = "Continue"
  static let primingDecline = "Not now"

  static let consentTitle = "Download the translation model"
  static let consentSize = "The translation model is \(ModelDownloadSize.approximate)."
  static let consentOnce = "It downloads once, then it stays on this phone."
  static let consentCellular = "You are not on Wi-Fi. A download this large is better on Wi-Fi."
  static let consentAction = "Download now"
  static let consentDecline = "Not now"

  static let preparingModel = "Preparing translation model"
  static let downloadingModel = "Downloading translation model"
}

// MARK: - Flow

/// Owns the one first-run decision that is not a remembered flag: whether this session start needs
/// download consent, and what the consent card should warn about. The welcome and priming flags
/// live in `@AppStorage` on the root view.
@MainActor
final class FirstRunModel: ObservableObject {
  struct ConsentPrompt: Equatable {
    let cellularWarning: Bool
  }

  /// Mirrors the model `MelangeTranslationRuntime` loads. Kept here so the consent decision can ask
  /// the read-only `LocalModelStore` about it without reaching into the runtime.
  static let modelName = "SJ_zetic/Hy-MT2-1.8B"

  @Published private(set) var consent: ConsentPrompt?

  private let path: any NetworkPathReporting
  private let hasLocalModel: () -> Bool
  private var pendingStart: (() -> Void)?

  /// Nonisolated so it can be a SwiftUI view's default argument, which is always evaluated outside
  /// the actor. It only stores its two collaborators; nothing here touches published state.
  nonisolated init(path: any NetworkPathReporting = NetworkPathObserver(),
                   hasLocalModel: @escaping () -> Bool = FirstRunModel.localModelExists) {
    self.path = path
    self.hasLocalModel = hasLocalModel
  }

  nonisolated static func fromLaunchArguments(
    _ arguments: [String] = ProcessInfo.processInfo.arguments
  ) -> FirstRunModel {
    let localModel: () -> Bool
    switch FirstRunDefaults.value(named: "-firstRun", in: arguments) {
    case "fresh", "consentNeeded": localModel = { false }
    case "returning": localModel = { true }
    default: localModel = FirstRunModel.localModelExists
    }
    let path: any NetworkPathReporting = arguments.contains("-firstRunCellular")
      ? FixedNetworkPath(.expensive) : NetworkPathObserver()
    return FirstRunModel(path: path, hasLocalModel: localModel)
  }

  /// A complete extracted module or a complete archive both mean the next start is a local load.
  nonisolated static func localModelExists() -> Bool {
    LocalModelStore.discoverExtractedModule(forModelName: modelName) != nil
      || LocalModelStore.discoverArchive(forModelName: modelName) != nil
  }

  /// Gates a session start. With the model already on disk the start runs straight through, so a
  /// returning user never sees a download step for a download that will not happen.
  func requestSessionStart(_ start: @escaping () -> Void) {
    switch ModelDownloadConsent.decision(hasLocalModel: hasLocalModel(), cost: path.currentCost) {
    case .startImmediately:
      start()
    case let .ask(cellularWarning):
      pendingStart = start
      consent = ConsentPrompt(cellularWarning: cellularWarning)
    }
  }

  func acceptConsent() {
    let start = pendingStart
    pendingStart = nil
    consent = nil
    start?()
  }

  func declineConsent() {
    pendingStart = nil
    consent = nil
  }
}
