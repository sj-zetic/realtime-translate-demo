import Foundation

// swiftlint:disable identifier_name
enum Speaker: String, CaseIterable, Identifiable {
  case a = "A"
  case b = "B"

  var id: String { rawValue }
  var counterpart: Speaker { self == .a ? .b : .a }
}
// swiftlint:enable identifier_name

/// A session failure, and the one thing the banner has to know about it: whether the way out is a
/// permission the app does not have, or a piece of work that can simply be tried again.
///
/// The distinction is the whole point. Re-running the permission prompts for a microphone that was
/// already granted answers nothing, drops a live session back to `setup`, and throws the loaded
/// model's session away; a runtime failure only needs the session put back where it was.
struct SessionFailure: Equatable {
  enum Cause: Equatable {
    case permission
    case runtime
  }

  let message: String
  let cause: Cause

  /// The failures `beginTurn` can catch. Only the two permission cases send someone to the system
  /// prompts; everything else, an unavailable recognizer or a microphone that would not start, is
  /// a retry on the same screen.
  static func from(_ error: any Error) -> SessionFailure {
    let message = TranslationFailureCopy.message(for: error)
    switch error as? PlatformSpeechError {
    case .microphonePermissionRequired, .speechPermissionRequired:
      return SessionFailure(message: message, cause: .permission)
    default:
      return SessionFailure(message: message, cause: .runtime)
    }
  }

  /// A failure that is nobody's permission, for the states a test or a preview forces by hand.
  static func runtime(_ message: String) -> SessionFailure {
    SessionFailure(message: message, cause: .runtime)
  }
}

enum SessionState: Equatable {
  case permissionRequired
  case setup
  case loadingModel(Double?)
  case modelLoadFailed(String)
  case ready
  case listening(Speaker)
  case finalizing(Speaker)
  case translating(Speaker)
  case error(SessionFailure)

  /// The speaker whose utterance is currently recording, finalizing, or translating.
  var activeSpeaker: Speaker? {
    switch self {
    case let .listening(speaker): return speaker
    case let .finalizing(speaker): return speaker
    case let .translating(speaker): return speaker
    default: return nil
    }
  }

  /// The status strip's one line. Built through the catalog rather than from literals, because it
  /// is the most-read sentence in the app and the only running commentary a person gets.
  ///
  /// Sentence case throughout, and one name for a speaker: `Speaker A`, capitalized wherever it
  /// appears, because it is a label on two buttons rather than a common noun. The old mixture of
  /// Title Case for the fixed states and sentence case for the interpolated ones read as two
  /// different apps writing alternate lines of the same running commentary.
  var title: String {
    switch self {
    case .permissionRequired:
      String(localized: "Microphone permission required",
             comment: "Status strip: the microphone and speech prompts are unanswered")
    case .setup:
      String(localized: "Ready to start", comment: "Status strip: idle, before a session starts")
    case let .loadingModel(progress):
      // The same sentence the banner underneath is showing. Two lines of running commentary that
      // disagree ("Preparing Translation" over "Downloading 50%") make the screen look broken.
      ModelPreparationStatus.status(for: progress).headline
    case .modelLoadFailed:
      String(localized: "Translation model unavailable", comment: "Status strip: the model failed to load")
    case .ready:
      String(localized: "Ready to talk", comment: "Status strip: the model is loaded and idle")
    case let .listening(speaker):
      String(localized: "status.listening", defaultValue: "Speaker \(speaker.rawValue) is speaking",
             comment: "Status strip: %@ is the speaker label, A or B")
    case let .finalizing(speaker):
      String(localized: "status.finalizing",
             defaultValue: "Finalizing Speaker \(speaker.rawValue)'s transcript",
             comment: "Status strip: %@ is the speaker label, A or B")
    case let .translating(speaker):
      String(localized: "status.translating",
             defaultValue: "Translating for Speaker \(speaker.counterpart.rawValue)",
             comment: "Status strip: %@ is the receiving speaker's label, A or B")
    case .error:
      String(localized: "Unable to process", comment: "Status strip: the session hit an error")
    }
  }
}

/// The line an empty transcript shows, which is a different sentence in every state and no
/// sentence at all in the states where the banner above it is already explaining.
///
/// Keyed on the state rather than on "is a session live", which is what made a 1.9 GB download
/// tell someone to `Choose the languages above, then start the session.` over locked chips and a
/// session that had already started.
enum ConversationEmptyHint {
  static func text(for state: SessionState) -> String? {
    switch state {
    // The banner owns the explanation in all four: repeating it under an empty transcript is a
    // second voice saying the same thing one size smaller.
    case .permissionRequired, .loadingModel, .modelLoadFailed, .error:
      return nil
    case .setup:
      return String(localized: "Choose the languages above, then start the session.",
                    comment: "Empty transcript hint before a session starts")
    case .ready, .listening, .finalizing, .translating:
      return String(localized: "Speaker A or B can begin speaking.",
                    comment: "Empty transcript hint while a session is live")
    }
  }
}

/// The note a turn that produced no words leaves behind.
///
/// A silent turn is not a failure and not an interruption, so it borrows the interruption note's
/// shape rather than the error banner's: one quiet line, no color, no button, cleared by the next
/// turn. It has to exist at all because `finalizing` has exactly one exit, and a recognizer that
/// returns nothing would otherwise never take it.
enum EmptyTurnCopy {
  static var notice: String {
    String(localized: "No speech was recognized. Tap to talk again.",
           comment: "Session banner note after a turn the recognizer heard nothing in")
  }
}

struct SpeechSourceLanguage: Identifiable, Hashable {
  static let automatic = SpeechSourceLanguage(
    identifier: "automatic",
    name: String(localized: "Automatic",
                 comment: "Spoken language option: let iOS pick the recognition language")
  )

  let identifier: String
  let name: String

  var id: String { identifier }
}

/// One Hy-MT2 reading language.
///
/// `name` is deliberately not localized. It is not only a label: it is the argument the Hy-MT2
/// prompt is built from ("Translate the following text into French"), and that instruction has to
/// stay in English whatever language the interface is in. Everything a person reads goes through
/// `displayName` or `menuName` instead, which are the same name in the interface's own language.
/// Nothing on the display side may ever be handed to `HyMT2Request`.
struct TargetLanguage: Identifiable, Hashable {
  let code: String
  /// The English name, and the only thing the Hy-MT2 instruction is ever built from. See above.
  let name: String
  var id: String { code }

  /// The name for a person, in the interface's own language, as the locale API spells it: lower
  /// case in French and Spanish, which is what those languages do mid-sentence. Use it inside a
  /// sentence ("Speaker A types in Korean", "reads Korean").
  ///
  /// Two lookups rather than one, because the catalogue holds one code the language-code lookup
  /// gets wrong: `zh-Hant` is a language plus a script, and asking for its language code answers
  /// `Chinese`, which is already what `zh` is called. The identifier lookup keeps the script
  /// ("Chinese, Traditional", "chinois traditionnel"). Anything the platform cannot name at all
  /// falls back to the English name rather than to a raw code.
  var displayName: String {
    Self.localizedName(for: code, in: .current) ?? name
  }

  /// The same name where it stands on its own: a picker row, a language chip, the destination line
  /// on a bubble. Only the first character is raised, so `chinois traditionnel` becomes
  /// `Chinois traditionnel` rather than the every-word `Chinois Traditionnel`.
  var menuName: String { Self.sentenceCased(displayName) }

  static func localizedName(for code: String, in locale: Locale) -> String? {
    let name = code.contains("-")
      ? locale.localizedString(forIdentifier: code)
      : locale.localizedString(forLanguageCode: code)
    return name?.isEmpty == false ? name : nil
  }

  static func sentenceCased(_ value: String) -> String {
    guard let first = value.first else { return value }
    return String(first).localizedUppercase + value.dropFirst()
  }

  /// The order a speaker's reading-language menu offers 38 languages in.
  ///
  /// Catalogue order is the order the model card happens to list them in, which put Ukrainian at
  /// number 33 behind a menu that does not search. So: the languages this conversation is actually
  /// using, then the phone's own language, then everything else alphabetically by the name on
  /// screen. Sorted by `displayName`, not by `name`, because a French menu sorted by the English
  /// names is not sorted at all.
  static func menuOrder(pinning pinned: [TargetLanguage],
                        deviceLanguageCode: String? = Locale.current.language.languageCode?.identifier,
                        in candidates: [TargetLanguage] = hyMT2Candidates) -> [TargetLanguage] {
    var top: [TargetLanguage] = []
    for language in pinned + candidates.filter({ $0.code == deviceLanguageCode })
    where candidates.contains(language) && !top.contains(language) {
      top.append(language)
    }
    let rest = candidates.filter { !top.contains($0) }
      .sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
    return top + rest
  }

  static let hyMT2Candidates = [
    ("zh", "Chinese"), ("en", "English"), ("fr", "French"), ("pt", "Portuguese"),
    ("es", "Spanish"), ("ja", "Japanese"), ("tr", "Turkish"), ("ru", "Russian"),
    ("ar", "Arabic"), ("ko", "Korean"), ("th", "Thai"), ("it", "Italian"),
    ("de", "German"), ("vi", "Vietnamese"), ("ms", "Malay"), ("id", "Indonesian"),
    ("tl", "Filipino"), ("hi", "Hindi"), ("zh-Hant", "Traditional Chinese"), ("pl", "Polish"),
    ("cs", "Czech"), ("nl", "Dutch"), ("km", "Khmer"), ("my", "Burmese"),
    ("fa", "Persian"), ("gu", "Gujarati"), ("ur", "Urdu"), ("te", "Telugu"),
    ("mr", "Marathi"), ("he", "Hebrew"), ("bn", "Bengali"), ("ta", "Tamil"),
    ("uk", "Ukrainian"), ("bo", "Tibetan"), ("kk", "Kazakh"), ("mn", "Mongolian"),
    ("ug", "Uyghur"), ("yue", "Cantonese")
  ].map(TargetLanguage.init)
}

struct HyMT2Request: Equatable {
  let userMessage: String
  let flatPrompt: String

  init(sourceText: String, targetLanguage: TargetLanguage) {
    let instruction = "Translate the following text into \(targetLanguage.name). "
      + "Note that you should only output the translated result without any additional explanation:"
    userMessage = "\(instruction)\n\n\(sourceText)"
    flatPrompt = HyMT2Request.beginOfSentence + HyMT2Request.user + userMessage + HyMT2Request.assistant
  }

  private static let beginOfSentence = "<\u{FF5C}hy_begin\u{2581}of\u{2581}sentence\u{FF5C}>"
  private static let user = "<\u{FF5C}hy_User\u{FF5C}>"
  private static let assistant = "<\u{FF5C}hy_Assistant\u{FF5C}>"
}

extension TargetLanguage {
  init(_ value: (String, String)) {
    code = value.0
    name = value.1
  }
}

struct ConversationItem: Identifiable, Equatable {
  enum DeliveryState: Equatable { case partial, finalizing, translationFailed(String), translated }
  let id: UUID
  let speaker: Speaker
  let transcript: String
  let targetLanguage: TargetLanguage
  let translation: String?
  let state: DeliveryState
}
