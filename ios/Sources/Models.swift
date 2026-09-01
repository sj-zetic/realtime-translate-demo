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

  var title: String {
    switch self {
    case .permissionRequired: "Microphone Permission Required"
    case .setup: "Ready to Start"
    case .loadingModel: "Preparing Translation"
    case .modelLoadFailed: "Translation Model Unavailable"
    case .endingSession: "Closing Translation Session"
    case .ready: "Ready to Talk"
    case let .listening(speaker): "\(speaker.rawValue) is speaking"
    case let .finalizing(speaker): "Finalizing \(speaker.rawValue)'s transcript"
    case let .translating(speaker): "Translating for \(speaker.counterpart.rawValue)"
    case .ended: "Session Ended"
    case .error: "Unable to Process"
    }
  }
}

struct SpeechSourceLanguage: Identifiable, Hashable {
  static let automatic = SpeechSourceLanguage(identifier: "automatic", name: "Automatic")

  let identifier: String
  let name: String

  var id: String { identifier }
}

struct TargetLanguage: Identifiable, Hashable {
  let code: String
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
