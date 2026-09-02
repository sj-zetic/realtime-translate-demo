import AVFAudio
import Foundation
import Speech

enum SpeechPermission: Equatable {
  case granted
  case required
}

enum PlatformSpeechError: LocalizedError {
  case microphonePermissionRequired
  case speechPermissionRequired
  case unsupportedLanguage(String)
  case unavailable(String)

  /// These land in the session banner, so they are translated. The two cases carrying a `reason`
  /// were already localized where the reason was built, so they pass it through untouched.
  var errorDescription: String? {
    switch self {
    case .microphonePermissionRequired:
      String(localized: "Microphone permission is required.",
             comment: "Session banner error when the microphone prompt was refused")
    case .speechPermissionRequired:
      String(localized: "Speech recognition permission is required.",
             comment: "Session banner error when the speech recognition prompt was refused")
    case let .unsupportedLanguage(reason), let .unavailable(reason): reason
    }
  }
}

/// The reasons the two pass-through errors carry, localized where they are built.
enum PlatformSpeechCopy {
  static func recognitionUnavailable(language: String) -> String {
    String(localized: "speech.recognitionUnavailable",
           defaultValue: "\(language) speech recognition is unavailable on this device.",
           comment: "Session banner error. %@ is a spoken language name")
  }

  static func onDeviceUnsupported(language: String) -> String {
    String(localized: "speech.onDeviceUnsupported",
           defaultValue: "\(language) does not support on-device speech recognition on this device.",
           comment: "Session banner error. %@ is a spoken language name")
  }

  static func microphoneUnavailable(reason: String) -> String {
    String(localized: "speech.microphoneUnavailable",
           defaultValue: "Unable to start the microphone: \(reason)",
           comment: "Session banner error. %@ is the underlying system error, which iOS localizes")
  }
}

@MainActor
protocol SpeechRecognizing: AnyObject {
  func requestPermissions() async -> SpeechPermission
  /// The permission the system already holds, read without prompting for anything.
  func currentPermission() -> SpeechPermission
  /// The recognition locales already known, answered without asking the platform anything. On a
  /// launch that has not read them yet this is empty rather than slow.
  func availableSourceLanguages() -> [SpeechSourceLanguage]
  /// Reads them from the platform, off the main actor, and remembers the answer for the launch.
  /// `SFSpeechRecognizer` charges about 280 ms for the enumeration, which is a frame budget the
  /// screen this view model builds does not have.
  nonisolated func loadAvailableSourceLanguages() async -> [SpeechSourceLanguage]
  func start(
    source: SpeechSourceLanguage,
    onPartial: @escaping (String) -> Void,
    onFinal: @escaping (String) -> Void
  ) throws
  func finish()
  func stop()
}

/// The recognition locale list, read once per launch and shared by every reader afterwards.
///
/// It cannot change while the app is running (a locale is downloaded through Settings, which means
/// leaving), and it costs about 280 ms to produce, so a second reading is a second stall for an
/// answer that is already known. Lock guarded rather than actor isolated because the seed happens
/// during a view model's `init`, where there is nothing to await with.
final class SourceLanguageCache: @unchecked Sendable {
  private let lock = NSLock()
  private var languages: [SpeechSourceLanguage] = []

  var current: [SpeechSourceLanguage] {
    lock.lock()
    defer { lock.unlock() }
    return languages
  }

  /// The cached list, computing it exactly once. `compute` is not run at all once there is an
  /// answer, which is what keeps a permission grant from paying the enumeration a second time.
  @discardableResult
  func fill(_ compute: () -> [SpeechSourceLanguage]) -> [SpeechSourceLanguage] {
    let known = current
    guard known.isEmpty else { return known }
    let computed = compute()
    lock.lock()
    languages = computed
    lock.unlock()
    return computed
  }
}

@MainActor
final class PlatformSpeechRecognizer: NSObject, SpeechRecognizing {
  /// Shared by every recognizer this launch builds, because the answer is the device's, not any
  /// one recognizer's.
  static let languageCache = SourceLanguageCache()

  private var audioEngine: AVAudioEngine?
  private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
  private var recognitionTask: SFSpeechRecognitionTask?

  func requestPermissions() async -> SpeechPermission {
    let microphoneGranted = await requestMicrophonePermission()
    let speechGranted = await requestSpeechPermission()
    return microphoneGranted && speechGranted ? .granted : .required
  }

  /// Reads both authorization stores without asking for anything, so the first-run flow can tell a
  /// returning user (already granted) from someone the system prompts have never reached.
  func currentPermission() -> SpeechPermission {
    let microphoneGranted: Bool
    if #available(iOS 17.0, *) {
      microphoneGranted = AVAudioApplication.shared.recordPermission == .granted
    } else {
      microphoneGranted = AVAudioSession.sharedInstance().recordPermission == .granted
    }
    let speechGranted = SFSpeechRecognizer.authorizationStatus() == .authorized
    return microphoneGranted && speechGranted ? .granted : .required
  }

  func availableSourceLanguages() -> [SpeechSourceLanguage] { Self.languageCache.current }

  nonisolated func loadAvailableSourceLanguages() async -> [SpeechSourceLanguage] {
    await Task.detached(priority: .userInitiated) {
      Self.languageCache.fill(Self.platformSourceLanguages)
    }.value
  }

  /// The expensive part: one `SFSpeechRecognizer` per supported locale, each asked whether it can
  /// run on device. Never called on the main actor.
  private static func platformSourceLanguages() -> [SpeechSourceLanguage] {
    sourceLanguages(
      locales: Array(SFSpeechRecognizer.supportedLocales()),
      supportsOnDeviceRecognition: { locale in
        SFSpeechRecognizer(locale: locale)?.supportsOnDeviceRecognition == true
      },
      localizedName: { locale in locale.localizedString(forIdentifier: locale.identifier) }
    )
  }

  func start(
    source: SpeechSourceLanguage,
    onPartial: @escaping (String) -> Void,
    onFinal: @escaping (String) -> Void
  ) throws {
    stop()
    let session = AVAudioSession.sharedInstance()
    do {
      try session.setCategory(.record, mode: .measurement, options: [])
      try session.setActive(true, options: .notifyOthersOnDeactivation)
    } catch {
      throw PlatformSpeechError.unavailable(
        PlatformSpeechCopy.microphoneUnavailable(reason: error.localizedDescription)
      )
    }

    guard let recognizer = SFSpeechRecognizer(locale: source.locale) else {
      throw PlatformSpeechError.unsupportedLanguage(
        PlatformSpeechCopy.recognitionUnavailable(language: source.name)
      )
    }
    guard recognizer.supportsOnDeviceRecognition else {
      throw PlatformSpeechError.unsupportedLanguage(
        PlatformSpeechCopy.onDeviceUnsupported(language: source.name)
      )
    }
    let request = SFSpeechAudioBufferRecognitionRequest()
    Self.configure(request)
    let engine = AVAudioEngine()
    let inputNode = engine.inputNode
    let inputFormat = inputNode.outputFormat(forBus: 0)
    inputNode.installTap(onBus: 0, bufferSize: 1_024, format: inputFormat) { buffer, _ in
      request.append(buffer)
    }

    recognitionTask = recognizer.recognitionTask(with: request) { result, error in
      if let result {
        let transcript = result.bestTranscription.formattedString
        if result.isFinal {
          onFinal(transcript)
        } else {
          onPartial(transcript)
        }
      }
      if let error, !Self.isCancellation(error) {
        onFinal("")
      }
    }
    audioEngine = engine
    recognitionRequest = request
    do {
      engine.prepare()
      try engine.start()
    } catch {
      stop()
      throw PlatformSpeechError.unavailable(
        PlatformSpeechCopy.microphoneUnavailable(reason: error.localizedDescription)
      )
    }
  }

  func stop() {
    audioEngine?.inputNode.removeTap(onBus: 0)
    audioEngine?.stop()
    recognitionRequest?.endAudio()
    recognitionTask?.cancel()
    recognitionTask = nil
    recognitionRequest = nil
    audioEngine = nil
    try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
  }

  func finish() {
    audioEngine?.inputNode.removeTap(onBus: 0)
    audioEngine?.stop()
    recognitionRequest?.endAudio()
    audioEngine = nil
    recognitionRequest = nil
    try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
  }

  private func requestMicrophonePermission() async -> Bool {
    await withCheckedContinuation { continuation in
      AVAudioSession.sharedInstance().requestRecordPermission { granted in
        continuation.resume(returning: granted)
      }
    }
  }

  private func requestSpeechPermission() async -> Bool {
    await withCheckedContinuation { continuation in
      SFSpeechRecognizer.requestAuthorization { status in
        continuation.resume(returning: status == .authorized)
      }
    }
  }

  private static func isCancellation(_ error: Error) -> Bool {
    (error as NSError).code == 216
  }

  static func configure(_ request: SFSpeechAudioBufferRecognitionRequest) {
    request.requiresOnDeviceRecognition = true
    request.shouldReportPartialResults = true
  }

  static func sourceLanguages(
    locales: [Locale],
    supportsOnDeviceRecognition: (Locale) -> Bool,
    localizedName: (Locale) -> String?
  ) -> [SpeechSourceLanguage] {
    locales
      .filter(supportsOnDeviceRecognition)
      .map { locale in
        SpeechSourceLanguage(
          identifier: locale.identifier,
          name: localizedName(locale) ?? locale.identifier
        )
      }
      .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
  }
}

extension SpeechSourceLanguage {
  var locale: Locale {
    identifier == Self.automatic.identifier ? .current : Locale(identifier: identifier)
  }
}
