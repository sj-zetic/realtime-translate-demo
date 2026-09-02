import AVFAudio
import Foundation

/// Spoken translation output, and the decisions behind it.
///
/// Nothing here can be asserted by listening to a speaker, so the same split the session-comfort
/// work uses applies again: every decision is a pure function or a small state machine over an
/// injected sink, and the `AVSpeechSynthesizer` call is the thin shell around it. The tests
/// exercise the decisions; the sound itself is verified on device.

// MARK: - Copy

enum SpeechOutputCopy {
  static var replayAction: String {
    String(localized: "Play translation", comment: "Accessibility label for a bubble's replay control")
  }
  static var replayHint: String {
    String(localized: "Speaks this translation again.",
           comment: "Accessibility hint for a bubble's replay control")
  }
  static var soundOnLabel: String {
    String(localized: "Spoken translation on",
           comment: "Accessibility label for the sound toggle while it is unmuted")
  }
  static var soundOffLabel: String {
    String(localized: "Spoken translation off",
           comment: "Accessibility label for the sound toggle while it is muted")
  }
  static var soundOnHint: String {
    String(localized: "Turns spoken translation off.",
           comment: "Accessibility hint for the sound toggle while it is unmuted")
  }
  static var soundOffHint: String {
    String(localized: "Turns spoken translation on.",
           comment: "Accessibility hint for the sound toggle while it is muted")
  }
}

/// The mute preference lives in platform preferences under one key, written by the toolbar's
/// `@AppStorage` and read by the view model when it seeds itself, so the very first frame after a
/// launch already agrees with the toggle.
enum SpeechOutputDefaults {
  static let mutedKey = "speech.muted"
}

// MARK: - What gets spoken

extension SessionState {
  /// The states in which the microphone is open and the recognizer owns the audio session.
  /// Nothing is ever spoken in these; `translating` is not one of them, because the recognizer has
  /// already been stopped by the time a translation is under way.
  var isRecognizerLive: Bool {
    switch self {
    case .listening, .finalizing: true
    default: false
    }
  }
}

extension ConversationItem {
  /// The text this bubble can speak: a finished translation and nothing else. A bubble that is
  /// still recognizing, still translating, or whose translation failed has nothing to say, which
  /// is exactly when the replay control is hidden.
  var speakableTranslation: String? {
    guard case .translated = state, let translation else { return nil }
    return translation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : translation
  }
}

/// Whether a bubble speaks, and in which voice language. The one rule both the automatic
/// announcement and the replay button go through, so muting cannot suppress only one of them.
enum SpokenTranslation: Equatable {
  case speak(text: String, languageCode: String)
  case silent

  static func decision(for item: ConversationItem, isMuted: Bool) -> SpokenTranslation {
    guard !isMuted, let text = item.speakableTranslation else { return .silent }
    return .speak(text: text, languageCode: item.targetLanguage.code)
  }
}

// MARK: - Voice matching

/// Picking the voice a translation is read in. The reading language is a Hy-MT2 code such as `ko`
/// or `zh-Hant`, and the installed voices are concrete locales such as `ko-KR` or `zh-TW`, so the
/// two have to be matched rather than compared.
enum SpeechVoice {
  /// The best installed voice language for a target code: an exact match first, then the variant
  /// the code most likely implies (`zh-Hant` picks `zh-TW` over `zh-CN`), then any voice for the
  /// same language, and nil when the device has none at all. Nil means the translation stays
  /// silent rather than being read out in the wrong language.
  static func match(for code: String, in available: [String]) -> String? {
    let target = Locale.Language(identifier: code)
    guard let language = target.languageCode?.identifier else { return nil }
    if let exact = available.first(where: { $0.caseInsensitiveCompare(code) == .orderedSame }) {
      return exact
    }
    let candidates = available
      .filter { Locale.Language(identifier: $0).languageCode?.identifier == language }
      .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    guard candidates.count > 1 else { return candidates.first }
    let implied = subtags(of: target.maximalIdentifier).subtracting([language])
    return candidates.first { !subtags(of: $0).subtracting([language]).intersection(implied).isEmpty }
      ?? candidates.first
  }

  private static func subtags(of identifier: String) -> Set<String> {
    Set(
      identifier.replacingOccurrences(of: "_", with: "-")
        .split(separator: "-").map(String.init)
    )
  }
}

// MARK: - Audio session handoff

/// The audio session as the speech output needs it. `AVAudioSession` in the app, a spy in tests.
protocol SpeechAudioSession {
  func activatePlayback() throws
  func deactivate()
}

/// Speech recognition runs the session as `.record` with `.measurement` mode, which cannot play
/// anything, so speaking takes the session over as `.playback` and hands it straight back.
/// `.notifyOthersOnDeactivation` on the way out is what lets whatever was playing before resume,
/// and what leaves the session free for the next push-to-talk to claim as `.record` again.
struct SystemSpeechAudioSession: SpeechAudioSession {
  func activatePlayback() throws {
    let session = AVAudioSession.sharedInstance()
    try session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
    try session.setActive(true, options: [])
  }

  func deactivate() {
    try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
  }
}

/// Owns the record/playback handoff, and remembers which side currently holds the session.
///
/// The memory is the point. A translation that finishes while another is being spoken must not
/// tear the session down and rebuild it mid-sentence, and the delegate callback that says an
/// utterance ended arrives after the next push-to-talk may already have claimed the microphone.
/// Both are the same bug, and both are prevented by only ever writing a change: `endPlayback`
/// after the session was already handed back does nothing at all.
@MainActor
final class SpeechAudioCoordinator {
  private(set) var isPlaybackActive = false

  private let session: any SpeechAudioSession

  init(session: any SpeechAudioSession = SystemSpeechAudioSession()) {
    self.session = session
  }

  /// Claims the session for speech. Returns whether it is safe to speak: a session that refuses
  /// to activate stays unclaimed, so nothing is spoken into a route that is not there and the
  /// next attempt tries again from scratch.
  @discardableResult
  func beginPlayback() -> Bool {
    guard !isPlaybackActive else { return true }
    do {
      try session.activatePlayback()
      isPlaybackActive = true
    } catch {
      isPlaybackActive = false
    }
    return isPlaybackActive
  }

  /// Hands the session back, once. Called both when speech ends on its own and, synchronously,
  /// before a turn starts recording.
  func endPlayback() {
    guard isPlaybackActive else { return }
    isPlaybackActive = false
    session.deactivate()
  }
}

// MARK: - Speech output

/// Anything that can read a translation aloud. `AVSpeechSynthesizer` in the app, a fake in tests.
@MainActor
protocol SpeechOutput: AnyObject {
  /// Speaks `text` in the best available voice for `languageCode`, replacing anything already
  /// being spoken. A language with no installed voice speaks nothing.
  func speak(text: String, languageCode: String)
  /// Stops immediately and hands the audio session back, synchronously, so a push-to-talk that
  /// interrupts a sentence can claim the microphone on the very next line.
  func stop()
  var isSpeaking: Bool { get }
}

@MainActor
final class SystemSpeechOutput: NSObject, SpeechOutput, AVSpeechSynthesizerDelegate {
  private let synthesizer: AVSpeechSynthesizer
  private let audio: SpeechAudioCoordinator
  private let voiceLanguages: () -> [String]

  var isSpeaking: Bool { synthesizer.isSpeaking }

  init(synthesizer: AVSpeechSynthesizer = AVSpeechSynthesizer(),
       audio: SpeechAudioCoordinator? = nil,
       voiceLanguages: @escaping () -> [String] = {
         AVSpeechSynthesisVoice.speechVoices().map(\.language)
       }) {
    self.synthesizer = synthesizer
    self.audio = audio ?? SpeechAudioCoordinator()
    self.voiceLanguages = voiceLanguages
    super.init()
    synthesizer.delegate = self
  }

  func speak(text: String, languageCode: String) {
    guard let language = SpeechVoice.match(for: languageCode, in: voiceLanguages()),
          let voice = AVSpeechSynthesisVoice(language: language) else {
      // No voice for this language at all: say nothing rather than read it in another accent.
      stop()
      return
    }
    // The newest translation wins. The session is deliberately not released here, so replacing a
    // sentence is a cut rather than a route change the speaker can hear.
    if synthesizer.isSpeaking { synthesizer.stopSpeaking(at: .immediate) }
    guard audio.beginPlayback() else { return }
    let utterance = AVSpeechUtterance(string: text)
    utterance.voice = voice
    synthesizer.speak(utterance)
  }

  func stop() {
    if synthesizer.isSpeaking { synthesizer.stopSpeaking(at: .immediate) }
    audio.endPlayback()
  }

  nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                                     didFinish utterance: AVSpeechUtterance) {
    Task { @MainActor [weak self] in self?.utteranceEnded() }
  }

  nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer,
                                     didCancel utterance: AVSpeechUtterance) {
    Task { @MainActor [weak self] in self?.utteranceEnded() }
  }

  /// The end of one utterance is only the end of speech when nothing took its place, and never a
  /// reason to touch a session the recognizer has since claimed.
  private func utteranceEnded() {
    guard !synthesizer.isSpeaking else { return }
    audio.endPlayback()
  }
}
