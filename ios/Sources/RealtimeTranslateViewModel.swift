import Foundation
import UIKit

@MainActor
final class RealtimeTranslateViewModel: ObservableObject {
  @Published private(set) var state: SessionState
  @Published var sourceLanguageA: SpeechSourceLanguage {
    didSet { preferences.setSpokenIdentifier(sourceLanguageA.identifier, for: .a) }
  }
  @Published var targetLanguageA: TargetLanguage {
    didSet {
      preferences.setReadingCode(targetLanguageA.code, for: .a)
      alignSpokenLanguage(with: targetLanguageA, for: .a)
    }
  }
  @Published var sourceLanguageB: SpeechSourceLanguage {
    didSet { preferences.setSpokenIdentifier(sourceLanguageB.identifier, for: .b) }
  }
  @Published var targetLanguageB: TargetLanguage {
    didSet {
      preferences.setReadingCode(targetLanguageB.code, for: .b)
      alignSpokenLanguage(with: targetLanguageB, for: .b)
    }
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
  /// One quiet line about something that happened to the session rather than to a bubble. Today
  /// that is only an audio interruption. It is not an error state: the session is live, the model
  /// is loaded, and the next push-to-talk clears it.
  @Published private(set) var notice: String?

  private let speechRecognizer: any SpeechRecognizing
  private let translationRuntime: any TranslationRuntime
  private let haptics: any HapticSink
  private let speechOutput: any SpeechOutput
  private let preferences: any LanguagePreferenceStoring
  private var audioInterruptions: any AudioInterruptionObserving
  private var activeItemID: UUID?
  private var pendingFinalTranscript: String?
  private var sessionTask: Task<Void, Never>?
  /// The one translation in flight. Held so ending a session can cancel it: a translation nobody
  /// is waiting for is a model still generating tokens on a phone whose session is over.
  private var translationTask: Task<Void, Never>?
  /// Whether this view model started the recognizer and has not released it yet. A typed turn
  /// travels the same finalized-transcript path without ever opening a microphone, so the release
  /// at the end of that path has to know whether there is anything to release: stopping a
  /// recognizer that never started tears down the audio session the spoken output is using.
  private var isRecognizerRunning = false
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
       isMuted: Bool = UserDefaults.standard.bool(forKey: SpeechOutputDefaults.mutedKey),
       preferences: (any LanguagePreferenceStoring)? = nil,
       audioInterruptions: (any AudioInterruptionObserving)? = nil) {
    let recognizer = speechRecognizer ?? PlatformSpeechRecognizer()
    let supported = [SpeechSourceLanguage.automatic] + recognizer.availableSourceLanguages()
    let store = preferences ?? EphemeralLanguagePreferences()
    self.state = state
    // A speaker's chip language drives what the recognizer listens for: an unset (automatic)
    // spoken language follows the reading language whenever a matching recognizer exists, so
    // "B: Korean" never transcribes in the device locale. A remembered pair enters through the
    // same resolver, so a restored launch and a fresh one agree by construction.
    let restoredA = LanguageRestore.selection(
      storedReading: store.readingCode(for: .a), storedSpoken: store.spokenIdentifier(for: .a),
      fallbackReading: targetLanguageA, fallbackSpoken: sourceLanguageA, available: supported
    )
    self.sourceLanguageA = restoredA.spoken
    self.targetLanguageA = restoredA.reading
    let restoredB = LanguageRestore.selection(
      storedReading: store.readingCode(for: .b), storedSpoken: store.spokenIdentifier(for: .b),
      fallbackReading: targetLanguageB, fallbackSpoken: sourceLanguageB, available: supported
    )
    self.sourceLanguageB = restoredB.spoken
    self.targetLanguageB = restoredB.reading
    self.items = items
    self.speechRecognizer = recognizer
    self.translationRuntime = translationRuntime ?? MelangeTranslationRuntime()
    self.haptics = haptics ?? SystemHaptics()
    self.speechOutput = speechOutput ?? SystemSpeechOutput()
    self.isMuted = isMuted
    self.preferences = store
    availableSourceLanguages = supported
    permissionGranted = recognizer.currentPermission() == .granted
    // Registered last, so the handler can never reach a half-built view model, and weakly, so the
    // notification center does not become the thing keeping a closed session alive.
    self.audioInterruptions = audioInterruptions ?? SystemAudioInterruptions()
    self.audioInterruptions.observe { [weak self] event in self?.handleAudioInterruption(event) }
    // Seeded above from whatever the recognizer already knows, which on a cold launch is nothing:
    // asking the platform costs about 280 ms and this runs before the first frame. The real list
    // arrives from off the main actor and re-runs the chip coupling if it changed anything.
    refreshAvailableLanguages()
  }

  /// The app's composition root, and the one place the persisting store is injected: everywhere
  /// else a view model remembers nothing, so a test is never reading what the host app last wrote.
  static func fromLaunchArguments() -> RealtimeTranslateViewModel {
    let value = ProcessInfo.processInfo.arguments.drop { $0 != "-uiState" }.dropFirst().first
    let store = UserDefaultsLanguagePreferences()
    switch value {
    case "listeningA":
      return RealtimeTranslateViewModel(state: .listening(.a), items: previewItems, preferences: store)
    case "finalizingA":
      return RealtimeTranslateViewModel(state: .finalizing(.a), items: previewItems, preferences: store)
    case "translationError":
      return RealtimeTranslateViewModel(state: .ready, items: failedPreviewItems, preferences: store)
    case "setup":
      return RealtimeTranslateViewModel(state: .setup, items: previewItems, preferences: store)
    case "loadingModel":
      return RealtimeTranslateViewModel(state: .loadingModel(0.5), preferences: store)
    case "modelLoadFailed":
      // The real copy for the real failure, rather than a placeholder sentence of its own: a UI
      // test driving this state should be reading what someone would actually see.
      return RealtimeTranslateViewModel(
        state: .modelLoadFailed(
          TranslationFailureCopy.message(for: TranslationRuntimeError.missingPersonalKey)
        ),
        preferences: store
      )
    case "ready": return RealtimeTranslateViewModel(state: .ready, preferences: store)
    case "permissionRequired":
      return RealtimeTranslateViewModel(state: .permissionRequired, preferences: store)
    default: return RealtimeTranslateViewModel(preferences: store)
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
        // Localized here rather than in the runtime: `MelangeTranslationRuntime` is shared with the
        // SDK integration and stays free of interface concerns, so the display site translates.
        state = .modelLoadFailed(TranslationFailureCopy.message(for: error))
      }
    }
  }

  func beginTurn(_ speaker: Speaker) {
    guard state == .ready else { return }
    // The notice says "tap to talk again", so this is the tap that answers it.
    notice = nil
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
      isRecognizerRunning = true
      state = .listening(speaker)
      haptics.play(.turnBegan)
    } catch {
      items.removeAll { $0.id == item.id }
      activeItemID = nil
      isRecognizerRunning = false
      speechRecognizer.stop()
      state = .error(SessionFailure.from(error))
      haptics.play(.sessionError)
    }
  }

  /// The one way out of `error`, and the reason the state carries a cause at all.
  ///
  /// A refused permission genuinely has to go back to the system prompts, which unavoidably drops
  /// the session to `setup`. Everything else, a recognizer that was busy or a microphone that
  /// would not start, only has to put the session back where it was: the model is still loaded and
  /// still in memory, and re-asking for a microphone the app already has answers nothing while
  /// costing the person their loaded session.
  func recoverFromError() {
    guard case let .error(failure) = state else { return }
    switch failure.cause {
    case .permission:
      requestMicrophonePermission()
    case .runtime:
      notice = nil
      state = .ready
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

  // MARK: - Typed turns

  /// A typed turn is gated exactly like a push-to-talk one: only an idle live session accepts a
  /// new utterance, so nothing can be typed over someone who is mid-sentence.
  var canSubmitTypedTranscript: Bool { state == .ready }

  /// Hands typed text to the same path a released push-to-talk hands a finalized transcript to.
  /// Everything after this line, target language included, is the speech flow untouched: the
  /// bubble is created already finalized because there was never a partial to show.
  func submitTypedTranscript(_ text: String, speaker: Speaker) {
    let transcript = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard canSubmitTypedTranscript, !transcript.isEmpty else { return }
    notice = nil
    // The same handoff a push-to-talk turn performs: nothing is left playing while a new utterance
    // is taken. A typed turn never opens the microphone, so this is the whole of its audio work.
    speechOutput.stop()
    let item = ConversationItem(
      id: UUID(), speaker: speaker, transcript: transcript,
      targetLanguage: targetLanguage(for: speaker.counterpart), translation: nil, state: .finalizing
    )
    items.append(item)
    activeItemID = item.id
    pendingFinalTranscript = nil
    state = .finalizing(speaker)
    haptics.play(.turnEnded)
    completeTurn(transcript, speaker: speaker)
  }

  // MARK: - Clearing the conversation

  /// Nothing is stored, so clearing asks nothing: it only has to be impossible mid-utterance,
  /// where it would strand the bubble a translation is about to land in, and pointless on an
  /// already empty transcript.
  var canClearConversation: Bool { !items.isEmpty && state.activeSpeaker == nil }

  /// Empties the transcript without touching the session: the model stays resident, the languages
  /// stay chosen, and the next turn starts straight away. Whatever was being read aloud belongs to
  /// a bubble that is going away, so it stops with it.
  func clearConversation() {
    guard canClearConversation else { return }
    speechOutput.stop()
    items = []
    mostRecentTranslationRequest = nil
    // The note belongs to the conversation that is going away, like every other entry point that
    // starts something new. Leaving it would strand "Tap to talk again" over an empty transcript.
    notice = nil
  }

  /// Ending a session clears the conversation but keeps the model resident, so the next
  /// `Start Session` reaches `.ready` without another load. The model unloads in `deinit`.
  ///
  /// It also stops the work the session started. Cancelling the task that was watching a load is
  /// not the same as stopping the load: without the second call the 1.9 GB transfer someone just
  /// declined keeps running on their cellular connection with nothing on screen to say so.
  func endSession() {
    sessionTask?.cancel()
    sessionTask = nil
    translationRuntime.cancelLoad()
    beginNewSession()
  }

  func beginNewSession() {
    translationTask?.cancel()
    translationTask = nil
    isRecognizerRunning = false
    speechRecognizer.stop()
    speechOutput.stop()
    activeItemID = nil
    pendingFinalTranscript = nil
    mostRecentTranslationRequest = nil
    notice = nil
    items = []
    state = .setup
  }

  // MARK: - Audio interruptions

  /// The one place an interruption changes anything. A phone call, Siri, or an alarm takes the
  /// audio session away, and the only question is what this app was using it for at that instant.
  /// The answer is a pure function, so the whole table is a unit test rather than a phone call.
  func handleAudioInterruption(_ event: AudioInterruptionEvent) {
    switch AudioInterruptionPolicy.response(to: event, state: state,
                                            isSpeaking: speechOutput.isSpeaking) {
    case .ignore:
      break
    case .stopSpeech:
      speechOutput.stop()
    case .abandonUtterance:
      abandonUtterance(AudioInterruptionCopy.notice)
    }
  }

  /// Discards the in-flight utterance exactly the way `beginTurn`'s failure path does: the
  /// recognizer is released, the bubble that was going to hold the utterance is removed rather
  /// than left half written, and the session returns to idle so the very next push-to-talk works.
  /// The recognizer reactivates its own audio session on every start, so nothing has to be
  /// rebuilt here for that next press to find a working microphone.
  ///
  /// Only the utterance dies. The model stays loaded, the languages stay chosen, and every earlier
  /// bubble stays where it is.
  private func abandonUtterance(_ note: String) {
    isRecognizerRunning = false
    speechRecognizer.stop()
    speechOutput.stop()
    if let id = activeItemID { items.removeAll { $0.id == id } }
    activeItemID = nil
    pendingFinalTranscript = nil
    state = .ready
    notice = note
  }

  /// Language chips stay editable mid-session; only an in-flight utterance or a busy
  /// model lifecycle step locks them. A reading-language change affects future translation
  /// prompts, and a recognition-language change applies at the next utterance start.
  var canEditLanguages: Bool {
    switch state {
    case .loadingModel, .listening, .finalizing, .translating: false
    default: true
    }
  }

  /// The model is loaded, so the A/B controls and `End Session` belong on screen. The same flag
  /// decides whether the display stays awake (see `ScreenAwakePolicy`).
  var isSessionLive: Bool { state.isSessionLive }

  /// Whether the model is in memory or on its way there, which is the only thing that makes
  /// deleting it from disk unsafe. Deliberately not `isSessionLive`: that answers a different
  /// question, and its two blind spots are the two states where a delete does the most damage.
  /// `loadingModel` is the file being mapped as it is removed, and the state after `End Session`
  /// is a model kept resident on purpose, where a delete would leave the app translating happily
  /// from memory and silently downloading 1.9 GB again on the next launch.
  var isModelHeld: Bool {
    if case .loadingModel = state { return true }
    return translationRuntime.isModelResident
  }

  /// What the settings drawer's storage row is allowed to offer, from the two facts only this view
  /// model has: whether a session is on screen to end, and whether the model is in memory.
  var modelHold: ModelStorageRow.Hold {
    if isSessionLive { return .session }
    return isModelHeld ? .memory : .free
  }

  /// Whether a bubble's replay glyph does anything if it is tapped. Muted it plays nothing, and
  /// while the recognizer holds the microphone `speak` refuses, so the control is disabled rather
  /// than left looking live and doing nothing.
  var canReplay: Bool { !isMuted && !state.isRecognizerLive }

  /// A single tap can start the first session once permissions are granted.
  var canStartSession: Bool {
    switch state {
    case .setup, .modelLoadFailed: true
    default: false
    }
  }

  /// Whether the session banner has anything to say right now. The root view needs to know
  /// before it lays the screen out, because a banner that has to be bounded at the accessibility
  /// sizes must not leave an empty bounded box behind in the states that have no banner.
  var hasSessionBanner: Bool {
    switch state {
    case .permissionRequired, .loadingModel, .modelLoadFailed, .error: return true
    default: return notice != nil
    }
  }

  /// Whether the model preparation on screen can still be called off. Both halves of it can: a
  /// download has a transfer to stop, and a local load has a map to abandon, and both land back on
  /// the same idle screen the start came from.
  var canCancelModelPreparation: Bool {
    if case .loadingModel = state { return true }
    return false
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

  /// Asks the platform for its recognition locales off the main actor and adopts the answer.
  /// Cheap to call again: the platform recognizer caches the list for the launch, so the second
  /// caller pays a hop rather than another enumeration.
  private func refreshAvailableLanguages() {
    let recognizer = speechRecognizer
    Task { [weak self] in
      let languages = await recognizer.loadAvailableSourceLanguages()
      self?.adoptAvailableLanguages(languages)
    }
  }

  /// Applies a freshly read locale list. A list that says what this view model already believed
  /// changes nothing, and a speaker whose spoken language has since been chosen by hand keeps it:
  /// only a chip still on `Automatic` re-derives from its reading language.
  private func adoptAvailableLanguages(_ languages: [SpeechSourceLanguage]) {
    let supported = [SpeechSourceLanguage.automatic] + languages
    guard supported != availableSourceLanguages else { return }
    availableSourceLanguages = supported
    if sourceLanguageA == .automatic { alignSpokenLanguage(with: targetLanguageA, for: .a) }
    if sourceLanguageB == .automatic { alignSpokenLanguage(with: targetLanguageB, for: .b) }
  }

  private func receivePartial(_ transcript: String, speaker: Speaker) {
    guard !transcript.isEmpty, state == .listening(speaker) else { return }
    updateActiveItem { item in
      ConversationItem(id: item.id, speaker: speaker, transcript: transcript,
                       targetLanguage: item.targetLanguage, translation: nil, state: .partial)
    }
  }

  /// The recognizer's last word on an utterance, which is sometimes that there were none.
  ///
  /// An empty final is realistic and not an error: a silent turn produces one, and the platform
  /// recognizer synthesizes one for any recognition failure that is not a cancellation. While the
  /// turn is still recording it means nothing yet, so it is dropped. Once the button is released
  /// it is the only answer that will ever come, and dropping it there leaves `finalizing` with no
  /// exit: every control blocked, and the only way out the one that wipes the conversation. So it
  /// ends the utterance the way an interruption does, with the bubble discarded and a quiet note.
  private func receiveFinal(_ transcript: String, speaker: Speaker) {
    guard state == .listening(speaker) || state == .finalizing(speaker) else { return }
    guard !transcript.isEmpty else {
      if state == .finalizing(speaker) { abandonUtterance(EmptyTurnCopy.notice) }
      return
    }
    pendingFinalTranscript = transcript
    guard state == .finalizing(speaker) else { return }
    completeTurn(transcript, speaker: speaker)
  }

  /// The one path a finalized transcript takes, whatever produced it: a released push-to-talk or
  /// a typed message. It resolves the counterpart's reading language, releases the recognizer
  /// (already idle for a typed turn), issues exactly one Hy-MT2 request, and speaks the result.
  private func completeTurn(_ transcript: String, speaker: Speaker) {
    guard state == .finalizing(speaker) else { return }
    let target = targetLanguage(for: speaker.counterpart)
    updateActiveItem { item in
      ConversationItem(id: item.id, speaker: speaker, transcript: transcript,
                       targetLanguage: target, translation: nil, state: .finalizing)
    }
    state = .translating(speaker)
    // Only when there is one to release. A typed turn reaches here with the microphone closed, and
    // stopping the recognizer would deactivate the audio session out from under the spoken output.
    if isRecognizerRunning {
      isRecognizerRunning = false
      speechRecognizer.stop()
    }
    let itemID = activeItemID
    activeItemID = nil
    pendingFinalTranscript = nil
    startTranslation(itemID: itemID, transcript: transcript, target: target, speaker: speaker)
  }

  /// Whether a bubble whose translation failed can be handed back to the model right now. The same
  /// gate a new utterance passes: an idle live session, so a retry can never land on top of
  /// someone who is mid-sentence.
  var canRetryTranslation: Bool { state == .ready }

  /// Runs the failed bubble's translation again, from its own transcript and its own reading
  /// language, so a retry re-sends the turn that failed rather than the turn's languages as they
  /// stand now. The bubble goes back to `Translation pending` in place, which is the same shape it
  /// had the first time, and lands back in the same three outcomes.
  func retryTranslation(_ item: ConversationItem) {
    guard canRetryTranslation, case .translationFailed = item.state,
          items.contains(where: { $0.id == item.id }) else { return }
    notice = nil
    let speaker = item.speaker
    updateItem(id: item.id) { existing in
      ConversationItem(id: existing.id, speaker: existing.speaker, transcript: existing.transcript,
                       targetLanguage: existing.targetLanguage, translation: nil, state: .finalizing)
    }
    state = .translating(speaker)
    startTranslation(itemID: item.id, transcript: item.transcript,
                     target: item.targetLanguage, speaker: speaker)
  }

  /// The one Hy-MT2 round trip, shared by a finished turn and by a retry of one that failed. Both
  /// arrive with the bubble already in its pending shape and the session already in `translating`,
  /// so this owns only the request, the three outcomes, and the return to idle.
  private func startTranslation(itemID: UUID?, transcript: String, target: TargetLanguage,
                                speaker: Speaker) {
    let request = HyMT2Request(sourceText: transcript, targetLanguage: target)
    mostRecentTranslationRequest = request
    translationTask?.cancel()
    translationTask = Task { [weak self] in
      guard let self else { return }
      do {
        let translation = try await translationRuntime.translate(prompt: request.flatPrompt)
        guard !Task.isCancelled, state == .translating(speaker), let itemID else { return }
        updateItem(id: itemID) { item in
          ConversationItem(id: item.id, speaker: item.speaker, transcript: item.transcript,
                           targetLanguage: item.targetLanguage, translation: translation, state: .translated)
        }
        haptics.play(.translationDelivered)
        // A finished translation is read aloud as it lands, which is also the moment the previous
        // one stops mattering: a conversation must not build a backlog of sentences to play.
        if let delivered = items.first(where: { $0.id == itemID }) { speak(delivered) }
      } catch {
        guard !Task.isCancelled, state == .translating(speaker), let itemID else { return }
        updateItem(id: itemID) { item in
          ConversationItem(id: item.id, speaker: item.speaker, transcript: item.transcript,
                           targetLanguage: item.targetLanguage, translation: nil,
                           state: .translationFailed(TranslationFailureCopy.message(for: error)))
        }
      }
      guard !Task.isCancelled, state == .translating(speaker) else { return }
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
    translationTask?.cancel()
    Task { [translationRuntime] in await translationRuntime.close() }
  }

  private static let previewItems = [
    ConversationItem(
      id: UUID(), speaker: .a, transcript: "Hello.", targetLanguage: .hyMT2Candidates[2],
      translation: "Bonjour.", state: .translated
    )
  ]
  private static var failedPreviewItems: [ConversationItem] {
    [
      ConversationItem(
        id: UUID(), speaker: .b, transcript: "Hello.", targetLanguage: .hyMT2Candidates[9],
        translation: nil,
        state: .translationFailed(TranslationFailureCopy.message(for: TranslationRuntimeError.generationFailed(3)))
      )
    ]
  }
}
