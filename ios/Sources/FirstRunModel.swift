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
  /// The measured size of the Hy-MT2 archive, in bytes, as the one fact everything else is derived
  /// from. Nothing anywhere writes a size out by hand: the consent card, the progress line, and
  /// the settings drawer's storage row all format bytes through `ModelStorageCopy.size`, so the
  /// model can never introduce itself as one size and then occupy another.
  static let bytes: Int64 = 1_908_528_832
  static var total: String { ModelStorageCopy.size(bytes: bytes) }

  /// How much of it has arrived, at a download fraction, formatted the same way.
  static func transferred(fraction: Double) -> String {
    ModelStorageCopy.size(bytes: Int64((Double(bytes) * fraction).rounded()))
  }
}

/// Whether starting a session has to ask first. A model already on disk loads locally in seconds
/// with no network at all, so the consent step exists only for a genuine first download.
enum ModelDownloadConsent {
  enum Decision: Equatable {
    case startImmediately
    case ask(cellularWarning: Bool)
  }

  /// A build with no Melange personal key cannot download anything, so offering `Download now`
  /// promises a transfer that ends a frame later in `The Melange personal key is not configured in
  /// this app build.` The start runs instead, and the load reports that failure where every other
  /// model failure is reported: the session banner, with its retry.
  static func decision(hasLocalModel: Bool, cost: NetworkPathCost,
                       hasPersonalKey: Bool = true) -> Decision {
    guard !hasLocalModel, hasPersonalKey else { return .startImmediately }
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
    // Both halves through the same formatter, so the line cannot say "1.0 of 1.91 GB" and set two
    // different precisions against each other.
    let transferred = ModelDownloadSize.transferred(fraction: progress)
    let percent = Int((progress * 100).rounded())
    // Written out in full rather than composed from `downloadingModel` and a number: a catalog
    // entry that is only a placeholder and a percent sign gives a translator nothing to work with.
    return ModelPreparationStatus(
      headline: String(localized: "modelPreparation.downloading",
                       defaultValue: "Downloading translation model \(percent)%",
                       comment: "Model download headline. %lld is the percentage complete"),
      detail: String(localized: "modelPreparation.transferred",
                     defaultValue: "\(transferred) of \(ModelDownloadSize.total)",
                     comment: "Model download detail: %1$@ is the amount transferred, %2$@ the total"),
      progress: progress
    )
  }
}

// MARK: - Copy

/// Every first-run string in one place, in the app's terse voice and with no em dash anywhere.
///
/// Computed rather than stored, so each one is a catalog lookup at the moment it is read. The
/// welcome title is the exception: it is the product name, which is not translated.
enum FirstRunCopy {
  static let welcomeTitle = AppText.productName
  static var welcomeTagline: String {
    String(localized: "Two people, two languages, one phone.",
           comment: "Welcome screen tagline, body text")
  }
  static var welcomePrivacy: String {
    String(localized: "Speech and translation run on this phone. Nothing is sent to a server.",
           comment: "Welcome screen privacy line, body text")
  }
  static var welcomeAction: String {
    String(localized: "Get started", comment: "Welcome screen primary button")
  }

  static var primingTitle: String {
    String(localized: "Microphone and speech", comment: "Permission priming screen title")
  }
  static var primingMicrophone: String {
    String(localized: "Microphone: to hear whoever is holding a button.",
           comment: "Permission priming screen: what the microphone is for, body text")
  }
  static var primingSpeech: String {
    String(localized: "Speech recognition: to turn that audio into text.",
           comment: "Permission priming screen: what speech recognition is for, body text")
  }
  static var primingPrivacy: String {
    String(localized: "Both run on this phone. No audio and no text leave the device.",
           comment: "Permission priming screen privacy line, body text")
  }
  static var primingNext: String {
    String(localized: "iOS asks for each one next.",
           comment: "Permission priming screen: what happens after the button, body text")
  }
  static var primingAction: String {
    String(localized: "Continue", comment: "Permission priming screen primary button")
  }
  static var primingDecline: String {
    String(localized: "Not now", comment: "Secondary button that dismisses a first run step")
  }

  static var consentTitle: String {
    String(localized: "Download the translation model", comment: "Model download consent card title")
  }
  /// The real figure rather than a hedge. `about 1.9 GB` was a rounded guess sitting next to a
  /// storage row that reported the measured bytes, and the two disagreed on screen.
  static var consentSize: String {
    String(localized: "consent.size",
           defaultValue: "The translation model is \(ModelDownloadSize.total).",
           comment: "Consent card body text. %@ is a formatted size such as 1.91 GB")
  }
  static var consentOnce: String {
    String(localized: "It downloads once, then it stays on this phone.",
           comment: "Consent card body text")
  }
  static var consentCellular: String {
    String(localized: "You are not on Wi-Fi. A download this large is better on Wi-Fi.",
           comment: "Consent card warning shown on an expensive or constrained network")
  }
  static var consentAction: String {
    String(localized: "Download now", comment: "Consent card primary button")
  }
  static var consentDecline: String {
    String(localized: "Not now", comment: "Secondary button that dismisses a first run step")
  }

  static var preparingModel: String {
    String(localized: "Preparing translation model",
           comment: "Session banner headline while a local model loads")
  }
  static var downloadingModel: String {
    String(localized: "Downloading translation model",
           comment: "Session banner headline while the model downloads, without a percentage")
  }
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
  private let hasPersonalKey: () -> Bool
  private var pendingStart: (() -> Void)?

  /// Nonisolated so it can be a SwiftUI view's default argument, which is always evaluated outside
  /// the actor. It only stores its collaborators; nothing here touches published state.
  nonisolated init(path: any NetworkPathReporting = NetworkPathObserver(),
                   hasLocalModel: @escaping () -> Bool = FirstRunModel.localModelExists,
                   hasPersonalKey: @escaping () -> Bool = FirstRunModel.personalKeyConfigured) {
    self.path = path
    self.hasLocalModel = hasLocalModel
    self.hasPersonalKey = hasPersonalKey
  }

  nonisolated static func fromLaunchArguments(
    _ arguments: [String] = ProcessInfo.processInfo.arguments
  ) -> FirstRunModel {
    let localModel: () -> Bool
    // A forced first-run state also forces the key: `-firstRun` exists so a UI test can drive the
    // consent card, and a test build that happens to carry no key would otherwise skip it.
    var personalKey = FirstRunModel.personalKeyConfigured
    switch FirstRunDefaults.value(named: "-firstRun", in: arguments) {
    case "fresh", "consentNeeded": localModel = { false }; personalKey = { true }
    case "returning": localModel = { true }; personalKey = { true }
    default: localModel = FirstRunModel.localModelExists
    }
    let path: any NetworkPathReporting = arguments.contains("-firstRunCellular")
      ? FixedNetworkPath(.expensive) : NetworkPathObserver()
    return FirstRunModel(path: path, hasLocalModel: localModel, hasPersonalKey: personalKey)
  }

  /// Whether this build can download anything at all. The same reading the runtime does, so the
  /// consent card and the load can never disagree about whether a download is possible.
  nonisolated static func personalKeyConfigured() -> Bool {
    !MelangeCredential.value(from: Bundle.main.infoDictionary ?? [:]).isEmpty
  }

  /// A complete extracted module or a complete archive both mean the next start is a local load.
  nonisolated static func localModelExists() -> Bool {
    LocalModelStore.discoverExtractedModule(forModelName: modelName) != nil
      || LocalModelStore.discoverArchive(forModelName: modelName) != nil
  }

  /// Gates a session start. With the model already on disk the start runs straight through, so a
  /// returning user never sees a download step for a download that will not happen.
  func requestSessionStart(_ start: @escaping () -> Void) {
    switch ModelDownloadConsent.decision(hasLocalModel: hasLocalModel(), cost: path.currentCost,
                                        hasPersonalKey: hasPersonalKey()) {
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
