import Foundation

/// Remembering each speaker's two language selections across launches, and the one rule that
/// decides what a stored pair actually restores to.
///
/// The pair is deliberately asymmetric. A reading language is only ever chosen by a person, so it
/// restores verbatim. A spoken (recognition) language is usually *derived* from the reading
/// language by the chip coupling, and only sometimes an explicit override, so it restores only
/// while the recognizer it names still exists on this device. A phone that lost a recognition
/// locale between launches re-derives rather than pinning a dead identifier and listening in the
/// wrong language.

// MARK: - Storage

/// Where the two selections are kept. Platform preferences in the app, an in-memory store in
/// tests, so a view model under test is exactly the one the test constructed.
protocol LanguagePreferenceStoring: AnyObject {
  func readingCode(for speaker: Speaker) -> String?
  func spokenIdentifier(for speaker: Speaker) -> String?
  func setReadingCode(_ code: String, for speaker: Speaker)
  func setSpokenIdentifier(_ identifier: String, for speaker: Speaker)
}

/// The `UserDefaults` keys the language selections are remembered under. Separate keys per speaker
/// and per role, so a partially written store (a fresh install that has only ever changed A) still
/// restores everything it does know.
enum LanguagePreferenceDefaults {
  static func readingKey(for speaker: Speaker) -> String { "language.reading.\(speaker.rawValue)" }
  static func spokenKey(for speaker: Speaker) -> String { "language.spoken.\(speaker.rawValue)" }

  static var allKeys: [String] {
    Speaker.allCases.flatMap { [readingKey(for: $0), spokenKey(for: $0)] }
  }

  /// `-resetLanguages` clears the remembered selections before any view or view model reads them,
  /// the same way `-resetFirstRun` clears the first-run flags. UI tests pass it so a run never
  /// inherits whatever the simulator container happened to hold; production launches never do.
  static func applyLaunchArguments(_ arguments: [String] = ProcessInfo.processInfo.arguments,
                                   to defaults: UserDefaults = .standard) {
    guard arguments.contains("-resetLanguages") else { return }
    reset(defaults)
  }

  static func reset(_ defaults: UserDefaults = .standard) {
    for key in allKeys { defaults.removeObject(forKey: key) }
  }
}

/// The store the app runs on.
final class UserDefaultsLanguagePreferences: LanguagePreferenceStoring {
  private let defaults: UserDefaults

  init(defaults: UserDefaults = .standard) { self.defaults = defaults }

  func readingCode(for speaker: Speaker) -> String? {
    defaults.string(forKey: LanguagePreferenceDefaults.readingKey(for: speaker))
  }

  func spokenIdentifier(for speaker: Speaker) -> String? {
    defaults.string(forKey: LanguagePreferenceDefaults.spokenKey(for: speaker))
  }

  func setReadingCode(_ code: String, for speaker: Speaker) {
    defaults.set(code, forKey: LanguagePreferenceDefaults.readingKey(for: speaker))
  }

  func setSpokenIdentifier(_ identifier: String, for speaker: Speaker) {
    defaults.set(identifier, forKey: LanguagePreferenceDefaults.spokenKey(for: speaker))
  }
}

/// A store that remembers nothing beyond its own lifetime. The view model's default, so a plain
/// `RealtimeTranslateViewModel(...)` in a test is unaffected by whatever the host app last wrote,
/// and a round trip is expressed by handing two view models the same instance.
final class EphemeralLanguagePreferences: LanguagePreferenceStoring {
  private var reading: [String: String] = [:]
  private var spoken: [String: String] = [:]

  init() {}

  func readingCode(for speaker: Speaker) -> String? { reading[speaker.rawValue] }
  func spokenIdentifier(for speaker: Speaker) -> String? { spoken[speaker.rawValue] }
  func setReadingCode(_ code: String, for speaker: Speaker) { reading[speaker.rawValue] = code }
  func setSpokenIdentifier(_ identifier: String, for speaker: Speaker) {
    spoken[speaker.rawValue] = identifier
  }
}

// MARK: - Restoring

/// One speaker's pair of languages.
struct LanguageSelection: Equatable {
  let reading: TargetLanguage
  let spoken: SpeechSourceLanguage
}

extension TargetLanguage {
  /// The catalogue entry for a stored code, or nil for a code this build no longer offers.
  static func hyMT2Candidate(code: String) -> TargetLanguage? {
    hyMT2Candidates.first { $0.code == code }
  }
}

@MainActor
enum LanguageRestore {
  /// The single resolver both a fresh launch and a restoring launch go through.
  ///
  /// Reading language first: a stored code wins, an unknown or absent one falls back. The spoken
  /// language is then requested (stored identifier, else the caller's own default) and honoured
  /// only while it names a recognizer this device still has and is not `Automatic`. Everything
  /// else derives from the reading language through the chip coupling, which is what makes an
  /// explicit override survive a relaunch while a derived default re-derives.
  static func selection(storedReading: String?, storedSpoken: String?,
                        fallbackReading: TargetLanguage, fallbackSpoken: SpeechSourceLanguage,
                        available: [SpeechSourceLanguage]) -> LanguageSelection {
    let reading = storedReading.flatMap(TargetLanguage.hyMT2Candidate(code:)) ?? fallbackReading
    let requested = storedSpoken.flatMap { identifier in
      available.first { $0.identifier == identifier }
    } ?? fallbackSpoken
    let honoured = available.contains(requested) ? requested : .automatic
    guard honoured == .automatic else { return LanguageSelection(reading: reading, spoken: honoured) }
    let derived = RealtimeTranslateViewModel.matchedSourceLanguage(for: reading, in: available)
    return LanguageSelection(reading: reading, spoken: derived ?? .automatic)
  }
}
