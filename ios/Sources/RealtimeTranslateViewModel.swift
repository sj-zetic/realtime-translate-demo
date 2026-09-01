import Foundation
import UIKit

@MainActor
final class RealtimeTranslateViewModel: ObservableObject {
  @Published private(set) var state: SessionState
  @Published var sourceLanguageA: SpeechSourceLanguage
  @Published var targetLanguageA: TargetLanguage
  @Published var sourceLanguageB: SpeechSourceLanguage
  @Published var targetLanguageB: TargetLanguage
  @Published private(set) var items: [ConversationItem]
  @Published private(set) var availableSourceLanguages: [SpeechSourceLanguage]

  private let speechRecognizer: any SpeechRecognizing
  private let translationRuntime: any TranslationRuntime
  private var activeItemID: UUID?
  private var pendingFinalTranscript: String?
  private var sessionTask: Task<Void, Never>?
  private(set) var mostRecentTranslationRequest: HyMT2Request?

  init(state: SessionState = .permissionRequired, sourceLanguageA: SpeechSourceLanguage = .automatic,
       targetLanguageA: TargetLanguage = .hyMT2Candidates[0], sourceLanguageB: SpeechSourceLanguage = .automatic,
       targetLanguageB: TargetLanguage = .hyMT2Candidates[9], items: [ConversationItem] = [],
       speechRecognizer: (any SpeechRecognizing)? = nil,
       translationRuntime: (any TranslationRuntime)? = nil) {
    let recognizer = speechRecognizer ?? PlatformSpeechRecognizer()
    let supported = [SpeechSourceLanguage.automatic] + recognizer.availableSourceLanguages()
    self.state = state
    self.sourceLanguageA = supported.contains(sourceLanguageA) ? sourceLanguageA : .automatic
    self.targetLanguageA = targetLanguageA
    self.sourceLanguageB = supported.contains(sourceLanguageB) ? sourceLanguageB : .automatic
    self.targetLanguageB = targetLanguageB
    self.items = items
    self.speechRecognizer = recognizer
    self.translationRuntime = translationRuntime ?? MelangeTranslationRuntime()
    availableSourceLanguages = supported
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
      state = permission == .granted ? .setup : .permissionRequired
    }
  }

  func openAppSettings() {
    guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
    UIApplication.shared.open(url)
  }

  func startSession() {
    guard state == .setup || isModelLoadFailure else { return }
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
    } catch {
      items.removeAll { $0.id == item.id }
      activeItemID = nil
      speechRecognizer.stop()
      state = .error(error.localizedDescription)
    }
  }

  func endTurn(_ speaker: Speaker) {
    guard state == .listening(speaker) else { return }
    state = .finalizing(speaker)
    updateActiveItem { item in
      ConversationItem(id: item.id, speaker: item.speaker, transcript: item.transcript,
                       targetLanguage: item.targetLanguage, translation: nil, state: .finalizing)
    }
    speechRecognizer.finish()
    if let transcript = pendingFinalTranscript, state == .finalizing(speaker) {
      completeTurn(transcript, speaker: speaker)
    }
  }

  func endSession() {
    speechRecognizer.stop()
    activeItemID = nil
    pendingFinalTranscript = nil
    mostRecentTranslationRequest = nil
    sessionTask?.cancel()
    state = .endingSession
    sessionTask = Task { [weak self, translationRuntime] in
      await translationRuntime.close()
      guard let self, state == .endingSession else { return }
      items = []
      activeItemID = nil
      pendingFinalTranscript = nil
      mostRecentTranslationRequest = nil
      state = .setup
    }
  }

  func beginNewSession() {
    speechRecognizer.stop()
    activeItemID = nil
    pendingFinalTranscript = nil
    mostRecentTranslationRequest = nil
    items = []
    state = .setup
  }

  var canEditSessionSettings: Bool {
    switch state {
    case .loadingModel, .endingSession: false
    default: true
    }
  }

  private func sourceLanguage(for speaker: Speaker) -> SpeechSourceLanguage {
    speaker == .a ? sourceLanguageA : sourceLanguageB
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
