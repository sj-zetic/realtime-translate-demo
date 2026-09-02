import Foundation

/// Localization plumbing: the one product name that is never translated, the in-app language
/// override, and the display-site wrapper for error text produced by code that must not be edited.
///
/// The app ships one String Catalog, `Localizable.xcstrings`, with English as the development
/// language. Everything a person can read comes out of it, by one of two routes:
///
/// 1. SwiftUI `Text("...")` with a literal, which resolves through `LocalizedStringKey` against the
///    environment locale. These re-render immediately when the root locale changes.
/// 2. `String(localized:)` in models, enums, and copy constants, which resolves against
///    `Bundle.main` and `Locale.current` at the moment the value is first read. These follow the
///    bundle's language, which iOS settles at launch, so they change on the next launch.
///
/// That split is why the language row says the choice applies fully after reopening the app: the
/// row writes `AppleLanguages`, which iOS reads when the bundle is built at launch, and the root
/// view also applies `\.environment(\.locale,)` so the first route updates straight away.

// MARK: - Text that is never translated

enum AppText {
  /// The product name. It is the same in every language, so it is a plain Swift constant rather
  /// than a catalog entry: nothing should ever be able to translate it.
  static let productName = "Turn Translate"
}

// MARK: - The in-app language override

/// The languages the app ships, plus the default that follows the phone.
///
/// The three concrete cases are named in their own language, which is what a language list is
/// expected to look like: someone who has the app in a language they cannot read has to be able to
/// find their way out of it.
enum AppLanguage: String, CaseIterable, Identifiable {
  case system
  case english
  case french
  case spanish

  var id: String { rawValue }

  /// The BCP 47 identifier written to `AppleLanguages`, or nil for the phone's own order.
  var localeIdentifier: String? {
    switch self {
    case .system: nil
    case .english: "en"
    case .french: "fr"
    case .spanish: "es"
    }
  }

  /// What the settings row shows. Only `System` is translated; the rest are endonyms.
  var displayName: String {
    switch self {
    case .system: AppLanguageCopy.system
    case .english: "English"
    case .french: "Fran\u{e7}ais"
    case .spanish: "Espa\u{f1}ol"
    }
  }

  /// The stored value, tolerant of a raw value this build no longer offers.
  static func named(_ rawValue: String?) -> AppLanguage {
    rawValue.flatMap(AppLanguage.init(rawValue:)) ?? .system
  }
}

/// Where the override is kept, and the one write that makes iOS act on it.
///
/// `AppleLanguages` is the standard iOS override: the app's own preferences domain shadows the
/// device language order, and `Bundle.main` reads it while it is being set up, which is why the
/// change is only complete on the next launch. Choosing `System` removes the key rather than
/// writing the current device language into it, so a phone that later changes its language is
/// followed rather than pinned.
enum AppLanguageDefaults {
  static let storageKey = "app.language"
  static let appleLanguagesKey = "AppleLanguages"

  static func stored(_ defaults: UserDefaults = .standard) -> AppLanguage {
    AppLanguage.named(defaults.string(forKey: storageKey))
  }

  /// Writes both halves of the choice: the app's own remembered value and the `AppleLanguages`
  /// override iOS reads at launch. Idempotent, so calling it again at every launch is free.
  static func apply(_ language: AppLanguage, to defaults: UserDefaults = .standard) {
    defaults.set(language.rawValue, forKey: storageKey)
    guard let identifier = language.localeIdentifier else {
      defaults.removeObject(forKey: appleLanguagesKey)
      return
    }
    defaults.set([identifier], forKey: appleLanguagesKey)
  }

  /// Re-applies whatever was remembered. Called at launch so a preference written by an older
  /// build, or cleared by a reset, and the `AppleLanguages` key can never disagree.
  static func applyStored(_ defaults: UserDefaults = .standard) {
    apply(stored(defaults), to: defaults)
  }

  /// `-resetAppLanguage` puts the app back on the device language before anything reads either
  /// key, the same way `-resetLanguages` clears the remembered chips. Production launches never
  /// pass it; UI tests do, so a run can never inherit an override from an earlier one.
  static func applyLaunchArguments(_ arguments: [String] = ProcessInfo.processInfo.arguments,
                                   to defaults: UserDefaults = .standard) {
    guard arguments.contains("-resetAppLanguage") else { return }
    reset(defaults)
  }

  static func reset(_ defaults: UserDefaults = .standard) {
    defaults.removeObject(forKey: storageKey)
    defaults.removeObject(forKey: appleLanguagesKey)
  }
}

enum AppLanguageCopy {
  static var title: String {
    String(localized: "App language", comment: "Settings drawer row: chooses the app's own language")
  }

  static var system: String {
    String(localized: "System",
           comment: "App language option: follow the language chosen in iOS Settings")
  }

  /// Shown after the choice changes. Says the honest thing: some of the screen changes now, the
  /// rest changes when the app is opened again.
  static var restartNotice: String {
    String(localized: "Language applies fully after reopening the app",
           comment: "Toast confirming an app language change")
  }
}

// MARK: - The one session action

/// The bottom bar's single slot, named once.
///
/// The name was `Start Session` in the app, `Start conversation` in the specification, and
/// `Start session` in half the prose about both. It is one action, so it has one name, in the
/// sentence case the rest of the interface uses.
enum SessionActionCopy {
  static var start: String {
    String(localized: "Start session", comment: "Bottom bar action that starts a session")
  }

  static var end: String {
    String(localized: "End session", comment: "Bottom bar action that ends a live session")
  }

  /// The same slot while the model is being prepared, which is the one moment the action is
  /// neither starting nor ending but calling off something already under way. Bare `Cancel`,
  /// because the banner directly above it is already naming what is being cancelled, and the two
  /// things it can be, a 1.9 GB transfer and a local load, have no honest shared noun.
  static var cancelPreparation: String {
    String(localized: "Cancel",
           comment: "Dismissal button: the typed input sheet, and the model preparation the bottom bar calls off")
  }
}

// MARK: - The two ways back to a granted microphone

/// The pair of buttons the permission banner offers, shared by the state that has never been
/// granted and the session error that turns out to be a refused prompt: the same problem reached
/// from two directions should not read as two different problems.
enum PermissionCopy {
  static var allowAccess: String {
    String(localized: "Allow microphone access",
           comment: "Session banner button that triggers the system prompts")
  }

  static var openSettings: String {
    String(localized: "Open app settings",
           comment: "Session banner button that opens this app's page in iOS Settings")
  }
}

// MARK: - Error text from code that is not edited

/// Turns a translation-runtime failure into text a person can read in their own language.
///
/// `MelangeTranslationRuntime` is off limits, so its `TranslationRuntimeError` descriptions are not
/// localized at the source. They are localized here instead, at the display site: the view model
/// asks for this before putting a failure on screen, and anything it does not recognize keeps the
/// system's own `localizedDescription` rather than losing detail to a generic line.
///
/// The wording is written for the person holding the phone, not for whoever will read the crash
/// report. `Hy-MT2`, `Melange personal key`, and `failed with code 3` name things nobody in a
/// conversation has ever heard of and offer them nothing to do; the engineering detail belongs in
/// `NSLog` and in `TranslationRuntimeError`, which keeps its own precise descriptions.
enum TranslationFailureCopy {
  static func message(for error: any Error) -> String {
    guard let runtimeError = error as? TranslationRuntimeError else { return error.localizedDescription }
    switch runtimeError {
    case .missingPersonalKey:
      return String(localized: "This build of the app cannot download the translation model.",
                    comment: "Model load failure: the build has no download credential")
    case .modelNotLoaded:
      return String(localized: "Translation is not ready yet.",
                    comment: "Translation failure: a request arrived before the model was ready")
    case .generationFailed:
      return String(localized: "The translation did not finish.",
                    comment: "Translation failure: the model stopped part way through")
    case .emptyOutput:
      return String(localized: "The translation came back empty.",
                    comment: "Translation failure: the model produced no text")
    }
  }

  /// The retry offered on a bubble whose translation failed, and on the session banner after a
  /// runtime error. One string, so the two never drift apart.
  static var retryAction: String {
    String(localized: "Try again", comment: "Button that runs a failed piece of work again")
  }

  static var retryHint: String {
    String(localized: "Translates this turn again.",
           comment: "Accessibility hint for the retry button on a failed chat bubble")
  }
}
