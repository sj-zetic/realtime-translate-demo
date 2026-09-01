import Foundation
import UIKit

@MainActor
final class RealtimeTranslateViewModel: ObservableObject {
  @Published private(set) var state: SessionState
  @Published var sourceLanguageA: SpeechSourceLanguage
  @Published var targetLanguageA: TargetLanguage {
    didSet { alignSpokenLanguage(with: targetLanguageA, for: .a) }
  }
  @Published var sourceLanguageB: SpeechSourceLanguage
  @Published var targetLanguageB: TargetLanguage {
    didSet { alignSpokenLanguage(with: targetLanguageB, for: .b) }
  }
  @Published private(set) var items: [ConversationItem]
  @Published private(set) var availableSourceLanguages: [SpeechSourceLanguage]
  /// Whether the microphone and speech-recognition prompts have already been answered with a yes.
  /// Drives the first-run priming step only; the session flow still keys off `state`.
  @Published private(set) var permissionGranted: Bool
  /// Whether spoken output is silenced. Seeded from the same preference key the toolbar toggle
  /// writes, so a launch that starts muted never speaks a first translation before the view
  /// appears.
  @Published private(set) var isMuted: Bool

  private let speechRecognizer: any SpeechRecognizing
  private let translationRuntime: any TranslationRuntime
  private let haptics: any HapticSink
  private let speechOutput: any SpeechOutput
  private var activeItemID: UUID?
  private var pendingFinalTranscript: String?
  private var sessionTask: Task<Void, Never>?
  private(set) var mostRecentTranslationRequest: HyMT2Request?

  // Defaults let a first session start in one tap: automatic recognition for both speakers and two
  // different reading languages (English for A, Korean for B), matching the Android defaults.
  init(state: SessionState = .permissionRequired, sourceLanguageA: SpeechSourceLanguage = .automatic,
       targetLanguageA: TargetLanguage = .hyMT2Candidates[1], sourceLanguageB: SpeechSourceLanguage = .automatic,
       targetLanguageB: TargetLanguage = .hyMT2Candidates[9], items: [ConversationItem] = [],
       speechRecognizer: (any SpeechRecognizing)? = nil,
       translationRuntime: (any TranslationRuntime)? = nil,
       haptics: (any HapticSink)? = nil,
       speechOutput: (any SpeechOutput)? = nil,
       isMuted: Bool = UserDefaults.standard.bool(forKey: SpeechOutputDefaults.mutedKey)) {
    let recognizer = speechRecognizer ?? PlatformSpeechRecognizer()
    let supported = [SpeechSourceLanguage.automatic] + recognizer.availableSourceLanguages()
    self.state = state
    // A speaker's chip language drives what the recognizer listens for: an unset (automatic)
    // spoken language follows the reading language whenever a matching recognizer exists, so
    // "B: Korean" never transcribes in the device locale.
    let resolvedA = supported.contains(sourceLanguageA) ? sourceLanguageA : .automatic
    self.sourceLanguageA = resolvedA == .automatic
      ? Self.matchedSourceLanguage(for: targetLanguageA, in: supported) ?? .automatic : resolvedA
    self.targetLanguageA = targetLanguageA
    let resolvedB = supported.contains(sourceLanguageB) ? sourceLanguageB : .automatic
    self.sourceLanguageB = resolvedB == .automatic
      ? Self.matchedSourceLanguage(for: targetLanguageB, in: supported) ?? .automatic : resolvedB
    self.targetLanguageB = targetLanguageB
    self.items = items
    self.speechRecognizer = recognizer
    self.translationRuntime = translationRuntime ?? MelangeTranslationRuntime()
    self.haptics = haptics ?? SystemHaptics()
    self.speechOutput = speechOutput ?? SystemSpeechOutput()
    self.isMuted = isMuted
    availableSourceLanguages = supported
    permissionGranted = recognizer.currentPermission() == .granted
  }

  static func fromLaunchArguments() -> RealtimeTranslateViewModel {
    let value = ProcessInfo.processInfo.arguments.drop { $0 != "-uiState" }.dropFirst().first
    switch value {
    case "listeningA": return RealtimeTranslateViewModel(state: .listening(.a), items: previewItems)
    case "finalizingA": return RealtimeTranslateViewModel(state: .finalizing(.a), items: previewItems)
    case "translationError": return RealtimeTranslateViewModel(state: .ready, items: failedPreviewItems)
    case "ended": return RealtimeTranslateViewModel(state: .ended, items: previewItems)
    case "loadingModel": return RealtimeTranslateViewModel(state: .loadingModel(0.5))
    case "modelLoadFailed": return RealtimeTranslateViewModel(state: .modelLoadFailed("Try again."))
    case "ready": return RealtimeTranslateViewModel(state: .ready)
    case "permissionRequired": return RealtimeTranslateViewModel(state: .permissionRequired)
    default: return RealtimeTranslateViewModel()
    }
  }

  func requestMicrophonePermission() {
    Task {
      let permission = await speechRecognizer.requestPermissions()
      refreshAvailableLanguages()
      permissionGranted = permission == .granted
      state = permission == .granted ? .setup : .permissionRequired
    }
  }

  /// The first-run priming step exists to explain the system prompts before they fire, so it has
  /// nothing to say once they have been answered.
  var needsPermissionPriming: Bool { !permissionGranted }

  /// Adopts a permission the system already holds, so a returning launch lands on the idle main
  /// screen instead of the permission banner. Never triggers a system prompt, and never disturbs a
  /// state the app has already moved past.
  func adoptExistingPermission() {
    permissionGranted = speechRecognizer.currentPermission() == .granted
    guard permissionGranted, state == .permissionRequired else { return }
    refreshAvailableLanguages()
    state = .setup
  }

  func openAppSettings() {
    guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
    UIApplication.shared.open(url)
  }

  func startSession() {
    guard state == .setup || state == .ended || isModelLoadFailure else { return }
    sessionTask?.cancel()
    state = .loadingModel(nil)
    sessionTask = Task { [weak self] in
      guard let self else { return }
      do {
        try await translationRuntime.load { [weak self] progress in
          Task { @MainActor [weak self] in
            guard let self, case .loadingModel = state else { return }
            state = .loadingModel(progress)
          }
        }
        guard !Task.isCancelled else { return }
        state = .ready
      } catch {
        guard !Task.isCancelled else { return }
        state = .modelLoadFailed(error.localizedDescription)
      }
    }
  }

  func beginTurn(_ speaker: Speaker) {
    guard state == .ready else { return }
    // Nothing is ever spoken while the microphone is open. Stopping here is synchronous, so the
    // audio session is handed back before the recognizer claims it one line further down.
    speechOutput.stop()
    let language = sourceLanguage(for: speaker)
    let item = ConversationItem(
      id: UUID(), speaker: speaker, transcript: "", targetLanguage: targetLanguage(for: speaker.counterpart),
      translation: nil, state: .partial
    )
    items.append(item)
    activeItemID = item.id
    pendingFinalTranscript = nil
    do {
      try speechRecognizer.start(
        source: language,
        onPartial: { [weak self] transcript in self?.receivePartial(transcript, speaker: speaker) },
        onFinal: { [weak self] transcript in self?.receiveFinal(transcript, speaker: speaker) }
      )
      state = .listening(speaker)
      haptics.play(.turnBegan)
    } catch {
      items.removeAll { $0.id == item.id }
      activeItemID = nil
      speechRecognizer.stop()
      state = .error(error.localizedDescription)
      haptics.play(.sessionError)
    }
  }

  func endTurn(_ speaker: Speaker) {
    guard state == .listening(speaker) else { return }
    state = .finalizing(speaker)
    haptics.play(.turnEnded)
    updateActiveItem { item in
      ConversationItem(id: item.id, speaker: item.speaker, transcript: item.transcript,
                       targetLanguage: item.targetLanguage, translation: nil, state: .finalizing)
    }
    speechRecognizer.finish()
    if let transcript = pendingFinalTranscript, state == .finalizing(speaker) {
      completeTurn(transcript, speaker: speaker)
    }
  }

  /// Ending a session clears the conversation but keeps the model resident, so the next
  /// `Start Session` reaches `.ready` without another load. The model unloads in `deinit`.
  func endSession() {
    sessionTask?.cancel()
    beginNewSession()
  }

  func beginNewSession() {
    speechRecognizer.stop()
    speechOutput.stop()
    activeItemID = nil
    pendingFinalTranscript = nil
    mostRecentTranslationRequest = nil
    items = []
    state = .setup
  }

  /// Language chips stay editable mid-session; only an in-flight utterance or a busy
  /// model lifecycle step locks them. A reading-language change affects future translation
  /// prompts, and a recognition-language change applies at the next utterance start.
  var canEditLanguages: Bool {
    switch state {
    case .loadingModel, .endingSession, .listening, .finalizing, .translating: false
    default: true
    }
  }

  /// The model is loaded, so the A/B controls and `End Session` belong on screen. The same flag
  /// decides whether the display stays awake (see `ScreenAwakePolicy`).
  var isSessionLive: Bool { state.isSessionLive }

  /// A single tap can start the first session once permissions are granted.
  var canStartSession: Bool {
    switch state {
    case .setup, .ended, .modelLoadFailed: true
    default: false
    }
  }

  // MARK: - Spoken output

  /// Adopts the toolbar toggle's stored preference. Muting also cuts whatever is being spoken
  /// right now, because the toggle is what someone reaches for to make the phone stop talking.
  func setMuted(_ muted: Bool) {
    guard muted != isMuted else { return }
    isMuted = muted
    if muted { speechOutput.stop() }
  }

  /// Replays one bubble's translation, from its speaker glyph. Same decision as the automatic
  /// announcement, so a muted app stays silent here too.
  func replay(_ item: ConversationItem) { speak(item) }

  private func speak(_ item: ConversationItem) {
    guard case let .speak(text, languageCode) = SpokenTranslation.decision(for: item, isMuted: isMuted)
    else { return }
    // Never over an open microphone: while a turn is being recorded or finalized the recognizer
    // owns the audio session.
    guard !state.isRecognizerLive else { return }
    speechOutput.stop()
    speechOutput.speak(text: text, languageCode: languageCode)
  }

  private func sourceLanguage(for speaker: Speaker) -> SpeechSourceLanguage {
    speaker == .a ? sourceLanguageA : sourceLanguageB
  }

  // Choosing a reading language re-aligns that speaker's spoken language, so the chip stays the
  // single source of truth. The spoken picker remains available as an explicit override until the
  // reading language changes again. No recognizer for the language means no change.
  private func alignSpokenLanguage(with target: TargetLanguage, for speaker: Speaker) {
    guard let match = Self.matchedSourceLanguage(for: target, in: availableSourceLanguages) else { return }
    switch speaker {
    case .a: if sourceLanguageA != match { sourceLanguageA = match }
    case .b: if sourceLanguageB != match { sourceLanguageB = match }
    }
  }

  /// The recognizer language matching a reading language: same language code, preferring the
  /// variant the code most likely implies (fr matches fr-FR over fr-BE, zh-Hant matches zh-TW).
  static func matchedSourceLanguage(
    for target: TargetLanguage, in languages: [SpeechSourceLanguage]
  ) -> SpeechSourceLanguage? {
    let targetLanguage = Locale.Language(identifier: target.code)
    guard let code = targetLanguage.languageCode?.identifier else { return nil }
    let matches = languages.filter { candidate in
      candidate != .automatic && candidate.locale.language.languageCode?.identifier == code
    }
    guard matches.count > 1 else { return matches.first }
    let implied = Set(
      targetLanguage.maximalIdentifier.replacingOccurrences(of: "_", with: "-")
        .split(separator: "-").map(String.init)
    ).subtracting([code])
    return matches.first { candidate in
      let parts = Set(
        candidate.locale.identifier.replacingOccurrences(of: "_", with: "-")
          .split(separator: "-").map(String.init)
      ).subtracting([code])
      return !parts.intersection(implied).isEmpty
    } ?? matches.first
  }

  private func targetLanguage(for speaker: Speaker) -> TargetLanguage {
    speaker == .a ? targetLanguageA : targetLanguageB
  }

  private func refreshAvailableLanguages() {
    availableSourceLanguages = [SpeechSourceLanguage.automatic] + speechRecognizer.availableSourceLanguages()
  }

  private func receivePartial(_ transcript: String, speaker: Speaker) {
    guard !transcript.isEmpty, state == .listening(speaker) else { return }
    updateActiveItem { item in
      ConversationItem(id: item.id, speaker: speaker, transcript: transcript,
                       targetLanguage: item.targetLanguage, translation: nil, state: .partial)
    }
  }

  private func receiveFinal(_ transcript: String, speaker: Speaker) {
    guard state == .listening(speaker) || state == .finalizing(speaker) else { return }
    guard !transcript.isEmpty else { return }
    pendingFinalTranscript = transcript
    guard state == .finalizing(speaker) else { return }
    completeTurn(transcript, speaker: speaker)
  }

  private func completeTurn(_ transcript: String, speaker: Speaker) {
    guard state == .finalizing(speaker) else { return }
    let target = targetLanguage(for: speaker.counterpart)
    updateActiveItem { item in
      ConversationItem(id: item.id, speaker: speaker, transcript: transcript,
                       targetLanguage: target, translation: nil, state: .finalizing)
    }
    state = .translating(speaker)
    speechRecognizer.stop()
    let request = HyMT2Request(sourceText: transcript, targetLanguage: target)
    mostRecentTranslationRequest = request
    let itemID = activeItemID
    activeItemID = nil
    pendingFinalTranscript = nil
    Task { [weak self] in
      guard let self else { return }
      do {
        let translation = try await translationRuntime.translate(prompt: request.flatPrompt)
        guard state == .translating(speaker), let itemID else { return }
        updateItem(id: itemID) { item in
          ConversationItem(id: item.id, speaker: item.speaker, transcript: item.transcript,
                           targetLanguage: item.targetLanguage, translation: translation, state: .translated)
        }
        haptics.play(.translationDelivered)
        // A finished translation is read aloud as it lands, which is also the moment the previous
        // one stops mattering: a conversation must not build a backlog of sentences to play.
        if let delivered = items.first(where: { $0.id == itemID }) { speak(delivered) }
      } catch {
        guard state == .translating(speaker), let itemID else { return }
        updateItem(id: itemID) { item in
          ConversationItem(id: item.id, speaker: item.speaker, transcript: item.transcript,
                           targetLanguage: item.targetLanguage, translation: nil,
                           state: .translationFailed(error.localizedDescription))
        }
      }
      guard state == .translating(speaker) else { return }
      state = .ready
    }
  }

  private func updateActiveItem(_ update: (ConversationItem) -> ConversationItem) {
    guard let id = activeItemID, let index = items.firstIndex(where: { $0.id == id }) else { return }
    items[index] = update(items[index])
  }

  private func updateItem(id: UUID, _ update: (ConversationItem) -> ConversationItem) {
    guard let index = items.firstIndex(where: { $0.id == id }) else { return }
    items[index] = update(items[index])
  }

  private var isModelLoadFailure: Bool {
    if case .modelLoadFailed = state { return true }
    return false
  }

  deinit {
    sessionTask?.cancel()
    Task { [translationRuntime] in await translationRuntime.close() }
  }

  private static let previewItems = [
    ConversationItem(
      id: UUID(), speaker: .a, transcript: "Hello.", targetLanguage: .hyMT2Candidates[2],
      translation: "Bonjour.", state: .translated
    )
  ]
  private static let failedPreviewItems = [
    ConversationItem(
      id: UUID(), speaker: .b, transcript: "Hello.", targetLanguage: .hyMT2Candidates[9], translation: nil,
      state: .translationFailed("The Hy-MT2 translation model could not complete this request.")
    )
  ]
}
