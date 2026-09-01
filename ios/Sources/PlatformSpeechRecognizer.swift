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

/// The one thing the microphone tap writes to, so the recognition request underneath a running
/// audio engine can be swapped out between segments without the engine, the tap, or the audio
/// session noticing.
///
/// Lock guarded rather than actor isolated because the tap is called on the audio render thread,
/// which cannot await anything, while the swap happens on the main actor.
final class RecognitionRequestSink: @unchecked Sendable {
  private let lock = NSLock()
  private var request: SFSpeechAudioBufferRecognitionRequest?

  /// Points the tap at a new request and closes the one it was feeding.
  func use(_ next: SFSpeechAudioBufferRecognitionRequest?) {
    lock.lock()
    let previous = request
    request = next
    lock.unlock()
    previous?.endAudio()
  }

  func append(_ buffer: AVAudioPCMBuffer) {
    lock.lock()
    let current = request
    lock.unlock()
    current?.append(buffer)
  }

  /// Ends the audio of whatever is in flight and stops feeding anything further.
  func finish() { use(nil) }
}

@MainActor
final class PlatformSpeechRecognizer: NSObject, SpeechRecognizing {
  /// Shared by every recognizer this launch builds, because the answer is the device's, not any
  /// one recognizer's.
  static let languageCache = SourceLanguageCache()

  /// How many segments in a row may fail to produce anything before the turn is given up on.
  ///
  /// A restart is the answer to a segment that ended, however it ended. A restart that immediately
  /// fails the same way is a recognizer that is not going to work again this turn, and retrying it
  /// forever would spin a callback loop instead of handing the words back.
  static let segmentRestartLimit = 3

  private var audioEngine: AVAudioEngine?
  private let requestSink = RecognitionRequestSink()
  private var recognitionTask: SFSpeechRecognitionTask?
  /// Held across segments: a restart needs the same recognizer, and building a second one costs
  /// the locale enumeration again.
  private var recognizer: SFSpeechRecognizer?
  /// The words so far. The button owns where an utterance ends, so a final that arrives before the
  /// release only ends a segment. See `UtteranceAccumulator`.
  private var accumulator = UtteranceAccumulator()
  private var partialHandler: ((String) -> Void)?
  private var finalHandler: ((String) -> Void)?
  /// Whether `finish()` has been called: the difference between a final that ends a segment and a
  /// final that ends the turn.
  private var isFinishing = false
  /// Exactly one `onFinal` per turn reaches the caller, whatever the segments underneath did.
  private var hasDeliveredFinal = false
  private var consecutiveSegmentFailures = 0

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
    self.recognizer = recognizer
    partialHandler = onPartial
    finalHandler = onFinal
    accumulator = UtteranceAccumulator()
    isFinishing = false
    hasDeliveredFinal = false
    consecutiveSegmentFailures = 0

    // The engine and its tap are installed once for the whole turn and feed the sink, not any one
    // request. That is what lets a segment be replaced mid-utterance without the microphone or the
    // audio session being torn down and rebuilt in front of someone who is still talking.
    let engine = AVAudioEngine()
    let inputNode = engine.inputNode
    let inputFormat = inputNode.outputFormat(forBus: 0)
    let sink = requestSink
    inputNode.installTap(onBus: 0, bufferSize: 1_024, format: inputFormat) { buffer, _ in
      sink.append(buffer)
    }
    audioEngine = engine
    beginSegment()
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

  /// Opens a recognition request on the already-running engine and points the tap at it.
  ///
  /// Used for the first segment of a turn and for every restart after it, which is the whole of
  /// the difference between them: nothing about the engine, the tap, or the audio session is
  /// touched here. The few milliseconds of audio between one segment's final and this request
  /// being installed are lost, which is the pause itself.
  @discardableResult
  private func beginSegment() -> Bool {
    guard let recognizer else { return false }
    let request = SFSpeechAudioBufferRecognitionRequest()
    Self.configure(request)
    requestSink.use(request)
    recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
      guard let self else { return }
      if let result {
        receive(result.bestTranscription.formattedString, isFinal: result.isFinal)
        // A final and an error delivered together is the error reporting the same segment ending
        // that the final already described, and the final is the half carrying the words. Taking
        // both would bank the segment and then immediately restart the segment that banking just
        // opened.
        if result.isFinal { return }
      }
      if let error, !Self.isCancellation(error) {
        receiveSegmentFailure()
      }
    }
    return true
  }

  /// One result from the segment in flight.
  ///
  /// The only interesting case is a final that arrives while the control is still held, which is
  /// what a pause mid-sentence produces: the recognizer has decided the utterance is over and the
  /// button says otherwise. The button wins. The segment is banked, a new one opens on the same
  /// audio, and the partial the caller sees is every word so far rather than only the new ones.
  private func receive(_ transcript: String, isFinal: Bool) {
    guard !hasDeliveredFinal else { return }
    consecutiveSegmentFailures = 0
    guard isFinal else {
      partialHandler?(accumulator.receivePartial(transcript))
      return
    }
    guard !isFinishing else {
      deliverFinal(concludingWith: transcript)
      return
    }
    let text = accumulator.commitSegment(transcript)
    recognitionTask = nil
    if beginSegment() {
      partialHandler?(text)
    } else {
      deliverFinal()
    }
  }

  /// A segment that ended in a recognition failure rather than a result.
  ///
  /// Mid-hold this is treated as one more reason to start a new segment, not as the end of the
  /// turn: a failure arriving after two sentences have already been recognized must not throw
  /// those two sentences away. A turn-level failure is surfaced only once restarting has stopped
  /// working, and then it carries whatever was accumulated, which for a turn that never recognized
  /// anything is the empty final this class has always synthesized.
  private func receiveSegmentFailure() {
    guard !hasDeliveredFinal else { return }
    recognitionTask = nil
    guard !isFinishing else {
      deliverFinal()
      return
    }
    accumulator.commitSegment()
    consecutiveSegmentFailures += 1
    guard consecutiveSegmentFailures < Self.segmentRestartLimit, beginSegment() else {
      deliverFinal()
      return
    }
    partialHandler?(accumulator.text)
  }

  /// The one `onFinal` a turn is allowed, carrying the whole utterance.
  private func deliverFinal(concludingWith transcript: String? = nil) {
    guard !hasDeliveredFinal else { return }
    hasDeliveredFinal = true
    let text = accumulator.concluded(with: transcript)
    let handler = finalHandler
    releaseRecognition()
    handler?(text)
  }

  func stop() {
    // Nothing further may be delivered for this turn, including by a callback already in flight.
    hasDeliveredFinal = true
    isFinishing = false
    consecutiveSegmentFailures = 0
    accumulator = UtteranceAccumulator()
    releaseRecognition()
  }

  /// Stops feeding the recognizer and waits for the segment in flight to have its last word, which
  /// then concludes the whole utterance. A turn with no segment left to answer, because restarting
  /// stopped working, concludes here instead of waiting for a callback that is not coming.
  func finish() {
    guard !hasDeliveredFinal else { return }
    isFinishing = true
    audioEngine?.inputNode.removeTap(onBus: 0)
    audioEngine?.stop()
    audioEngine = nil
    requestSink.finish()
    try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    if recognitionTask == nil { deliverFinal() }
  }

  private func releaseRecognition() {
    audioEngine?.inputNode.removeTap(onBus: 0)
    audioEngine?.stop()
    requestSink.finish()
    recognitionTask?.cancel()
    recognitionTask = nil
    audioEngine = nil
    recognizer = nil
    partialHandler = nil
    finalHandler = nil
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
