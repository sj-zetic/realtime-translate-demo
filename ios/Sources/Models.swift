import Foundation

// swiftlint:disable identifier_name
enum Speaker: String, CaseIterable, Identifiable {
  case a = "A"
  case b = "B"

  var id: String { rawValue }
  var counterpart: Speaker { self == .a ? .b : .a }
}
// swiftlint:enable identifier_name

enum SessionState: Equatable {
  case permissionRequired
  case setup
  case loadingModel(Double?)
  case modelLoadFailed(String)
  case endingSession
  case ready
  case listening(Speaker)
  case finalizing(Speaker)
  case translating(Speaker)
  case ended
  case error(String)

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
  var title: String {
    switch self {
    case .permissionRequired:
      String(localized: "Microphone Permission Required",
             comment: "Status strip: the microphone and speech prompts are unanswered")
    case .setup:
      String(localized: "Ready to Start", comment: "Status strip: idle, before a session starts")
    case .loadingModel:
      String(localized: "Preparing Translation", comment: "Status strip: the model is loading")
    case .modelLoadFailed:
      String(localized: "Translation Model Unavailable", comment: "Status strip: the model failed to load")
    case .endingSession:
      String(localized: "Closing Translation Session", comment: "Status strip: the session is unwinding")
    case .ready:
      String(localized: "Ready to Talk", comment: "Status strip: the model is loaded and idle")
    case let .listening(speaker):
      String(localized: "status.listening", defaultValue: "\(speaker.rawValue) is speaking",
             comment: "Status strip: %@ is the speaker label, A or B")
    case let .finalizing(speaker):
      String(localized: "status.finalizing", defaultValue: "Finalizing \(speaker.rawValue)'s transcript",
             comment: "Status strip: %@ is the speaker label, A or B")
    case let .translating(speaker):
      String(localized: "status.translating",
             defaultValue: "Translating for \(speaker.counterpart.rawValue)",
             comment: "Status strip: %@ is the receiving speaker's label, A or B")
    case .ended:
      String(localized: "Session Ended", comment: "Status strip: the session has finished")
    case .error:
      String(localized: "Unable to Process", comment: "Status strip: the session hit an error")
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
/// stay in English whatever language the interface is in. Giving the picker translated names means
/// a second, display-only name, which is a change to the model catalogue rather than to the
/// localization plumbing, so it is left to the language passes that follow.
struct TargetLanguage: Identifiable, Hashable {
  let code: String
  /// The English name, used both in the picker and in the Hy-MT2 instruction. See above.
  let name: String
  var id: String { code }

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
