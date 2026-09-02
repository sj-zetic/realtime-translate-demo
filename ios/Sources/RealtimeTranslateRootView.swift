import SwiftUI

/// ZETIC minimal design tokens. White surfaces, near-black text, one teal accent.
enum DesignToken {
  static let accent = Color(red: 45 / 255, green: 189 / 255, blue: 178 / 255)
  static let surface = Color.white
  static let surfaceSubtle = Color(red: 240 / 255, green: 240 / 255, blue: 240 / 255)
  static let divider = Color(red: 232 / 255, green: 232 / 255, blue: 232 / 255)
  static let textPrimary = Color(red: 10 / 255, green: 10 / 255, blue: 10 / 255)
  static let textSecondary = Color(red: 107 / 255, green: 107 / 255, blue: 107 / 255)
  static let error = Color(red: 201 / 255, green: 42 / 255, blue: 42 / 255)

  /// Per-speaker identity families, both derived from the brand system: speaker A is the teal
  /// family and speaker B is the ink family. Color is always redundant with the speaker label
  /// and the leading/trailing alignment, never the only distinguisher.
  static let accentA = Color(red: 45 / 255, green: 189 / 255, blue: 178 / 255)
  static let deepA = Color(red: 23 / 255, green: 135 / 255, blue: 125 / 255)
  static let tintA = Color(red: 233 / 255, green: 247 / 255, blue: 245 / 255)
  static let borderA = Color(red: 191 / 255, green: 231 / 255, blue: 226 / 255)
  static let accentB = Color(red: 10 / 255, green: 10 / 255, blue: 10 / 255)
  static let deepB = Color(red: 10 / 255, green: 10 / 255, blue: 10 / 255)
  /// One step deeper than the old `#F0F0F0`, matched to `tintA`'s lightness so the two bubble
  /// fills separate from the white page by the same amount. At `#F0F0F0` against `#E9F7F5` the
  /// two speakers were the same block of pale at arm's length, which is the distance this app is
  /// used at: one phone on a table between two people.
  static let tintB = Color(red: 233 / 255, green: 233 / 255, blue: 233 / 255)
  static let borderB = Color(red: 217 / 255, green: 217 / 255, blue: 217 / 255)
}

extension Speaker {
  var accentColor: Color { self == .a ? DesignToken.accentA : DesignToken.accentB }
  var deepColor: Color { self == .a ? DesignToken.deepA : DesignToken.deepB }
  var tintColor: Color { self == .a ? DesignToken.tintA : DesignToken.tintB }
  var borderColor: Color { self == .a ? DesignToken.borderA : DesignToken.borderB }
}

/// The official ZETIC logo lockup, from `Assets.xcassets/ZeticLogo`, at the leading edge of the
/// navigation bar.
///
/// Decoration, not a control. Carrying the settings drawer behind the brand mark meant the one way
/// into settings was a logo, which is a thing users read rather than a thing they press, and it
/// needed a glyph glued to its side to admit that it was tappable at all. The drawer now has its
/// own button at the trailing edge, so the lockup is back to being what it looks like.
private struct ZeticWordmark: View {
  var body: some View {
    Image("ZeticLogo")
      .resizable()
      .scaledToFit()
      .frame(height: 24)
      .accessibilityIdentifier("zetic-wordmark")
      // `Text(verbatim:)`, like the product name: the brand is spelled the same in every language
      // and must never reach the string catalog.
      .accessibilityLabel(Text(verbatim: "ZETIC"))
  }
}

/// The three lines are the platform's own settled sign for "a list of settings lives behind this",
/// with no direction in them to get wrong. Not a downward chevron: a chevron pointing down
/// promises something that drops from where it stands, and the drawer slides in from the trailing
/// edge.
enum SettingsMenuGlyph {
  static let menu = "line.3.horizontal"
}

/// The standalone menu button that opens the settings drawer, at the trailing edge of the
/// navigation bar. Icon-only, and drawn to a full `Layout.tapTarget` box in both directions
/// however small the glyph inside it measures.
private struct SettingsMenuButton: View {
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      Image(systemName: SettingsMenuGlyph.menu)
        .font(.system(size: 16, weight: .semibold))
        .foregroundStyle(DesignToken.textSecondary)
        .frame(minWidth: Layout.tapTarget, minHeight: Layout.tapTarget, alignment: .trailing)
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityIdentifier("settings-menu")
    // The `Text` overload rather than the string one, so the label can carry a translator comment
    // and still resolve against the environment locale.
    .accessibilityLabel(Text("Settings",
                             comment: "Settings drawer panel heading, and the accessibility label for the navigation bar button that opens it"))
  }
}

enum Layout {
  static let message: CGFloat = 16
  static let control: CGFloat = 20
  /// The minimum edge of anything that can be tapped. Every icon-only control in this app was
  /// drawn to its glyph (36x28, 32x32, 28x24) rather than to a finger, which is under the
  /// platform's own floor in both directions at once.
  static let tapTarget: CGFloat = 44
  /// Above this, the bottom bar drops its hint line. See `BottomBar.showsHint`.
  static let hintCeiling: DynamicTypeSize = .accessibility1
  /// The tallest a scrolling session banner may grow to before the transcript starts paying for
  /// it. Enough for a headline, a line of detail, and two stacked banner buttons.
  static let bannerCeiling: CGFloat = 340
}

/// One screen holds everything: status, a per-speaker language bar, an inline session banner,
/// the chat transcript, and the A/B push-to-talk controls.
///
/// The first-run surfaces sit above it as overlays rather than as separate destinations, so the
/// main screen is never rebuilt on the way in and there is no navigation to unwind.
struct RealtimeTranslateRootView: View {
  @StateObject var viewModel: RealtimeTranslateViewModel
  @StateObject private var settings = SettingsDrawerModel()
  @StateObject private var firstRun: FirstRunModel
  @StateObject private var conversationCopy = ConversationCopyModel()
  @StateObject private var typedInput = TypedInputModel()
  @AppStorage(FirstRunDefaults.welcomeSeenKey) private var welcomeSeen = false
  @AppStorage(FirstRunDefaults.permissionPrimingSeenKey) private var primingSeen = false
  /// The app-language override, as its raw value. `@AppStorage` cannot bind an enum without a
  /// `RawRepresentable` conformance that would then also have to survive an unknown stored value,
  /// so the raw string is the stored form and `AppLanguage.named` is the one tolerant reader.
  @AppStorage(AppLanguageDefaults.storageKey) private var appLanguageRaw = AppLanguage.system.rawValue
  @Environment(\.scenePhase) private var scenePhase
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  /// Holds the display awake while a session is live. A reference, not observed state: nothing on
  /// screen depends on it, so it must never invalidate the body it is driven from.
  @State private var screenAwake = ScreenAwakeController()

  /// Both collaborators arrive as autoclosures, like the four `@StateObject` properties above.
  /// SwiftUI rebuilds a root view struct freely and keeps only the first `StateObject` it is
  /// given, so an eagerly built pair is a recognizer enumeration, a translation runtime, a set of
  /// `NotificationCenter` registrations, and an `NWPathMonitor` constructed and thrown away on
  /// every one of those rebuilds.
  @MainActor init(viewModel: @autoclosure @escaping () -> RealtimeTranslateViewModel,
                  firstRun: @autoclosure @escaping () -> FirstRunModel = .fromLaunchArguments()) {
    _viewModel = StateObject(wrappedValue: viewModel())
    _firstRun = StateObject(wrappedValue: firstRun())
  }

  /// The chosen app language, or nil while the phone's own order applies.
  private var localeOverride: Locale? {
    AppLanguage.named(appLanguageRaw).localeIdentifier.map(Locale.init(identifier:))
  }

  var body: some View {
    mainScreen
      .overlay {
        SettingsDrawerOverlay(model: settings, canClearConversation: viewModel.canClearConversation,
                              clearConversation: viewModel.clearConversation,
                              appLanguage: AppLanguage.named(appLanguageRaw),
                              selectAppLanguage: selectAppLanguage)
      }
      .overlay { firstRunOverlay }
      // Half of the localization applies immediately: everything a SwiftUI `Text` resolves from a
      // literal follows the environment locale, so an override repaints the screen on the spot.
      // The other half, the strings models build with `String(localized:)`, follows the bundle,
      // which iOS settles at launch. That is what the row's toast is telling the user about.
      .environment(\.locale, localeOverride ?? .autoupdatingCurrent)
      .onAppear {
        viewModel.adoptExistingPermission()
        updateScreenAwake()
      }
      .onDisappear { screenAwake.release() }
      .onChange(of: viewModel.state) { _ in updateScreenAwake() }
      .onChange(of: scenePhase) { _ in updateScreenAwake() }
  }

  /// The one place the idle timer is decided: a live session in the foreground keeps the screen
  /// lit, and everything else, backgrounding included, hands it back.
  private func updateScreenAwake() {
    screenAwake.update(state: viewModel.state, isForeground: scenePhase == .active)
  }

  private var firstRunStep: FirstRunStep {
    FirstRunStep.step(welcomeSeen: welcomeSeen, primingSeen: primingSeen,
                      permissionNeeded: viewModel.needsPermissionPriming)
  }

  @ViewBuilder private var firstRunOverlay: some View {
    switch firstRunStep {
    case .welcome:
      WelcomeView(start: completeWelcome)
    case .permissionPriming:
      PermissionPrimingView(allow: allowPermissions, skip: { primingSeen = true })
    case .none:
      ModelConsentOverlay(prompt: firstRun.consent, download: firstRun.acceptConsent,
                          dismiss: firstRun.declineConsent)
    }
  }

  /// The welcome is shown once. Leaving it also settles the priming step: a returning user whose
  /// permissions are already granted skips it without ever seeing it.
  private func completeWelcome() {
    welcomeSeen = true
    viewModel.adoptExistingPermission()
    if !viewModel.needsPermissionPriming { primingSeen = true }
  }

  private func allowPermissions() {
    primingSeen = true
    viewModel.requestMicrophonePermission()
  }

  /// One place the choice is written: `@AppStorage` for this launch's environment locale, and the
  /// drawer model for the `AppleLanguages` override and the confirmation.
  private func selectAppLanguage(_ language: AppLanguage) {
    settings.selectAppLanguage(language)
    appLanguageRaw = language.rawValue
  }

  /// Every path that would load the model routes through the consent gate, including the retry
  /// after a failed load: that is exactly when a large transfer may be about to start again.
  private func startSession() {
    firstRun.requestSessionStart { [viewModel] in viewModel.startSession() }
  }

  private var mainScreen: some View {
    NavigationStack {
      VStack(spacing: 0) {
        LanguageBar(viewModel: viewModel)
        // The banner is the one row on this screen with no ceiling of its own, and at the
        // accessibility sizes the permission banner alone is taller than the phone. A `VStack`
        // whose children do not fit overflows in both directions at once, which is how the status
        // line came to be drawn through the navigation bar and the session action came to be
        // pushed off the bottom edge. Above the same ceiling the hint line goes at, the banner
        // scrolls inside a bounded box instead, and only when there is a banner to bound: an
        // empty scroller would leave a blank third of the screen behind in every other state.
        if viewModel.hasSessionBanner, dynamicTypeSize >= Layout.hintCeiling {
          ScrollView { sessionBanner }
            .frame(maxHeight: Layout.bannerCeiling)
            // Ahead of the transcript in the queue for what is left. The transcript's own
            // scroller is greedy, and without this the banner is offered nothing at all.
            .layoutPriority(1)
        } else {
          sessionBanner
        }
        // The copy confirmation sits at the bottom of the transcript rather than the bottom of the
        // screen, so it never lands on top of the push-to-talk row or the session action.
        ConversationList(items: viewModel.items, emptyHint: emptyHint, copy: conversationCopy.copy,
                         canReplay: viewModel.canReplay, replay: viewModel.replay,
                         canRetry: viewModel.canRetryTranslation, retry: viewModel.retryTranslation)
          .overlay(alignment: .bottom) {
            ToastLayer(center: conversationCopy.toasts, identifier: "copy-toast")
          }
      }
      .background(DesignToken.surface)
      // A top safe-area inset rather than the first row of the column, because the column is laid
      // out inside a navigation stack whose inline bar floats over it: at the accessibility sizes
      // a two-line status line grew upward out of the column and drew straight through the bar's
      // title and the ZETIC button. As an inset it is placed under the bar and pushes the rest of
      // the screen down instead of overlapping anything.
      .safeAreaInset(edge: .top, spacing: 0) {
        VStack(spacing: 0) {
          StatusStrip(title: viewModel.state.title)
          ThinDivider()
        }
        .background(DesignToken.surface)
      }
      // A plain `String`, not a literal: the product name is the same in every language and must
      // never reach the catalog.
      .navigationTitle(AppText.productName)
      .navigationBarTitleDisplayMode(.inline)
      // Three things in one bar: wordmark, title, menu button. All three survive every Dynamic
      // Type category, checked at `accessibility5` on the narrowest phone this app runs on, because
      // an inline navigation title caps its own growth well below where the row would run out of
      // width. Nothing here has to be hidden or truncated at the accessibility sizes.
      .toolbar {
        // iOS 26 wraps toolbar items in a glass capsule; the minimal chrome stays flat, and the
        // wordmark in particular must not be handed a capsule that would make decoration read as
        // a control again.
        if #available(iOS 26.0, *) {
          ToolbarItem(placement: .navigationBarLeading) {
            ZeticWordmark()
          }
          .sharedBackgroundVisibility(.hidden)
          ToolbarItem(placement: .navigationBarTrailing) {
            SettingsMenuButton(action: settings.open)
          }
          .sharedBackgroundVisibility(.hidden)
        } else {
          ToolbarItem(placement: .navigationBarLeading) { ZeticWordmark() }
          ToolbarItem(placement: .navigationBarTrailing) {
            SettingsMenuButton(action: settings.open)
          }
        }
      }
      .safeAreaInset(edge: .bottom, spacing: 0) {
        BottomBar(viewModel: viewModel, startSession: startSession, openTypedInput: typedInput.open)
      }
      // A sheet rather than an inline field: the keyboard covers the bottom bar either way, and a
      // sheet is the surface VoiceOver already treats as modal.
      .sheet(isPresented: $typedInput.isPresented) {
        TypedInputSheet(model: typedInput, readingA: viewModel.targetLanguageA,
                        readingB: viewModel.targetLanguageB,
                        canSend: viewModel.canSubmitTypedTranscript,
                        send: viewModel.submitTypedTranscript)
          .presentationDetents([.medium])
      }
    }
    .tint(DesignToken.accent)
  }

  private var emptyHint: String? { ConversationEmptyHint.text(for: viewModel.state) }

  private var sessionBanner: some View {
    SessionBanner(viewModel: viewModel, startSession: startSession,
                  recoverFromError: viewModel.recoverFromError)
  }
}

struct ThinDivider: View {
  var body: some View { Rectangle().fill(DesignToken.divider).frame(height: 1) }
}

/// Bottom-of-screen confirmation. Text only, no icon, and it fades itself out. Shared by the
/// settings drawer's copy row and a copied chat bubble, so both confirmations look identical.
struct Toast: View {
  let message: String?
  let identifier: String

  var body: some View {
    ZStack {
      if let message {
        Text(message)
          .font(.caption)
          .foregroundStyle(DesignToken.surface)
          // Wraps rather than running past the phone at the accessibility sizes.
          .multilineTextAlignment(.center)
          .fixedSize(horizontal: false, vertical: true)
          .padding(.horizontal, 16)
          .padding(.vertical, 10)
          .background(DesignToken.textPrimary)
          .clipShape(RoundedRectangle(cornerRadius: Layout.control))
          .padding(.horizontal, 24)
          .padding(.bottom, 24)
          .accessibilityIdentifier(identifier)
      }
    }
    .animation(.easeInOut(duration: 0.2), value: message)
    .allowsHitTesting(false)
  }
}

/// The `Toast` bound to a `ToastCenter`, so the surface presenting it only has to place it.
struct ToastLayer: View {
  @ObservedObject var center: ToastCenter
  var identifier = "toast"

  var body: some View { Toast(message: center.message, identifier: identifier) }
}

/// The app's one line of running commentary. It carried the sound toggle at its trailing end until
/// speech became a per-bubble tap: with nothing to mute there is no state to draw up here, and the
/// row goes back to being the one short sentence it always was.
private struct StatusStrip: View {
  let title: String

  var body: some View {
    HStack(spacing: 8) {
      Text(title)
        .font(.caption)
        .foregroundStyle(DesignToken.textSecondary)
        // Wraps at the accessibility sizes: "Translation model unavailable" truncated to
        // "Translation model" is a status line that says the opposite of what it means. Two lines
        // is the ceiling, though: this is the app's quietest line, and letting it run to four
        // takes the space away from the transcript, which is the loudest.
        .fixedSize(horizontal: false, vertical: true)
        .lineLimit(3)
        .minimumScaleFactor(0.7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityLabel(Text("Session status: \(title)",
                                 comment: "Accessibility label for the status strip. %@ is the status"))
    }
    .padding(.leading, 16)
    .padding(.trailing, 16)
    .padding(.vertical, 4)
  }
}

/// One chip per speaker, mirroring the side their chat bubbles appear on.
private struct LanguageBar: View {
  @ObservedObject var viewModel: RealtimeTranslateViewModel

  var body: some View {
    HStack(spacing: 12) {
      speakerMenu(.a, source: $viewModel.sourceLanguageA, target: $viewModel.targetLanguageA,
                  counterpart: viewModel.targetLanguageB)
      Spacer(minLength: 12)
      speakerMenu(.b, source: $viewModel.sourceLanguageB, target: $viewModel.targetLanguageB,
                  counterpart: viewModel.targetLanguageA)
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 8)
    ThinDivider()
  }

  @ViewBuilder private func speakerMenu(
    _ speaker: Speaker, source: Binding<SpeechSourceLanguage>, target: Binding<TargetLanguage>,
    counterpart: TargetLanguage
  ) -> some View {
    Menu {
      // The `label:` form, because the shorthand `Picker("...")` init has nowhere to put a
      // translator comment. The language names themselves are `verbatim`: they are already in the
      // reader's own language, and a catalog entry per language name would be 38 entries a
      // translator has to reproduce by hand from what the system already knows.
      Picker(selection: target) {
        // Not catalogue order: the two languages this conversation is using, then the phone's own,
        // then the remaining 35 alphabetically by the name actually on screen.
        ForEach(TargetLanguage.menuOrder(pinning: [target.wrappedValue, counterpart])) {
          Text(verbatim: $0.menuName).tag($0)
        }
      } label: {
        Text("Reading language", comment: "Section label in a speaker's language menu")
      }
      .pickerStyle(.inline)
      Picker(selection: source) {
        ForEach(viewModel.availableSourceLanguages) { Text(verbatim: $0.name).tag($0) }
      } label: {
        Text("Spoken language", comment: "Section label in a speaker's language menu")
      }
      .pickerStyle(.inline)
    } label: {
      // `verbatim`, because neither half is copy: one is a speaker label and a separator, the
      // other is a language name the system has already localized.
      (
        Text(verbatim: "\(speaker.rawValue) ·").fontWeight(.bold).foregroundColor(speaker.deepColor)
          + Text(verbatim: " \(target.wrappedValue.menuName)").fontWeight(.medium)
            .foregroundColor(DesignToken.textPrimary)
      )
      .font(.caption)
      // Two chips share one row, so the reading language is the first thing to lose at the
      // accessibility sizes. A second line and a little shrink keep the whole name readable
      // without letting a name like "Traditional Chinese" turn the language bar into four rows.
      .lineLimit(2)
      .minimumScaleFactor(0.7)
      .padding(.horizontal, 12)
      .padding(.vertical, 6)
      .background(DesignToken.surface)
      .clipShape(RoundedRectangle(cornerRadius: Layout.control))
      .overlay(
        RoundedRectangle(cornerRadius: Layout.control).stroke(speaker.borderColor, lineWidth: 1)
      )
    }
    .disabled(!viewModel.canEditLanguages)
    .accessibilityIdentifier("languages-\(speaker.rawValue)")
    .accessibilityLabel(
      String(localized: "languageChip.accessibility",
             defaultValue: "Speaker \(speaker.rawValue) languages: reads \(target.wrappedValue.displayName), speaks \(source.wrappedValue.name)",
             comment: "Language chip accessibility label. %1$@ speaker, %2$@ reading, %3$@ spoken")
    )
  }
}

private struct SessionBanner: View {
  @ObservedObject var viewModel: RealtimeTranslateViewModel
  let startSession: () -> Void
  let recoverFromError: () -> Void

  var body: some View {
    switch viewModel.state {
    case .permissionRequired:
      banner {
        Text("Turn Translate needs microphone and speech recognition access on this device.",
             comment: "Session banner body text. Turn Translate is the product name, keep it as is")
          .font(.subheadline).foregroundStyle(DesignToken.textPrimary)
          .fixedSize(horizontal: false, vertical: true)
        // `BannerButton` takes a plain `String`, so each title is looked up here rather than
        // handed over as a literal that would never reach the catalog.
        BannerButton(title: PermissionCopy.allowAccess, action: viewModel.requestMicrophonePermission)
        BannerButton(title: PermissionCopy.openSettings, action: viewModel.openAppSettings)
      }
    case let .loadingModel(progress):
      // A genuine download reports progress and can name a size; a local load reports nothing at
      // all, so it stays an indeterminate spinner rather than promising bytes that never move.
      let status = ModelPreparationStatus.status(for: progress)
      banner {
        HStack(spacing: 8) {
          if !status.isDownloading {
            ProgressView().progressViewStyle(.circular).tint(DesignToken.accent)
          }
          Text(status.headline)
            .font(.subheadline).foregroundStyle(DesignToken.textPrimary)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("model-preparation-headline")
        }
        if let detail = status.detail {
          Text(detail)
            .font(.caption).foregroundStyle(DesignToken.textSecondary)
            .accessibilityIdentifier("model-preparation-detail")
        }
        if let value = status.progress {
          ProgressView(value: value).tint(DesignToken.accent)
        }
        // No "Speaker controls unlock when the model is ready." here any more: the bottom bar's
        // own hint says exactly that, two inches lower, in the same words.
      }
    case let .modelLoadFailed(reason):
      banner {
        // The reason is already localized: it comes through `TranslationFailureCopy`.
        Text(verbatim: reason).font(.subheadline).foregroundStyle(DesignToken.error)
          .fixedSize(horizontal: false, vertical: true)
        BannerButton(
          title: String(localized: "Retry model load",
                        comment: "Session banner button that loads the model again after a failure"),
          action: startSession
        )
        .accessibilityIdentifier("retry-model-load")
      }
    case let .error(failure):
      banner {
        Text(verbatim: failure.message).font(.subheadline).foregroundStyle(DesignToken.error)
          .fixedSize(horizontal: false, vertical: true)
        // What the way out actually is. A refused permission goes back to the system prompts and
        // has to say so; anything else is one button that puts the session back, without throwing
        // the loaded model's session away to ask for a microphone the app already holds.
        switch failure.cause {
        case .permission:
          BannerButton(title: PermissionCopy.allowAccess, action: recoverFromError)
            .accessibilityIdentifier("recover-session")
          BannerButton(title: PermissionCopy.openSettings, action: viewModel.openAppSettings)
        case .runtime:
          BannerButton(title: TranslationFailureCopy.retryAction, action: recoverFromError)
            .accessibilityIdentifier("recover-session")
        }
      }
    default:
      // An interruption is not a failure, so the note borrows the banner's shape but none of its
      // urgency: secondary text, no error color, no button. The next push-to-talk clears it.
      if let notice = viewModel.notice {
        banner {
          Text(verbatim: notice)
            .font(.subheadline).foregroundStyle(DesignToken.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("session-notice")
        }
      } else {
        EmptyView()
      }
    }
  }

  @ViewBuilder private func banner<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      content()
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(16)
    .background(DesignToken.surfaceSubtle)
    ThinDivider()
  }
}

private struct BannerButton: View {
  let title: String
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      // The caller localizes; this is a `String`, so `verbatim` says so rather than leaving the
      // overload to look like an oversight.
      Text(verbatim: title)
        .font(.footnote).fontWeight(.semibold)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
    }
    .buttonStyle(.plain)
    .foregroundStyle(DesignToken.textPrimary)
    .background(DesignToken.surface)
    .clipShape(RoundedRectangle(cornerRadius: Layout.control))
    .overlay(RoundedRectangle(cornerRadius: Layout.control).stroke(DesignToken.divider, lineWidth: 1))
    .accessibilityLabel(title)
  }
}

private struct ConversationList: View {
  let items: [ConversationItem]
  /// Nil in the states where the banner above is already saying what is happening.
  let emptyHint: String?
  let copy: (ConversationItem) -> Void
  /// Whether tapping a bubble's play control would actually play anything right now.
  let canReplay: Bool
  let replay: (ConversationItem) -> Void
  let canRetry: Bool
  let retry: (ConversationItem) -> Void

  var body: some View {
    ScrollViewReader { proxy in
      ScrollView {
        LazyVStack(alignment: .leading, spacing: 12) {
          if items.isEmpty, let emptyHint {
            Text(emptyHint)
              .font(.subheadline)
              .foregroundStyle(DesignToken.textSecondary)
              .fixedSize(horizontal: false, vertical: true)
              .frame(maxWidth: .infinity, alignment: .leading)
          }
          ForEach(items) { item in
            ConversationBubble(item: item, copy: { copy(item) }, canReplay: canReplay,
                               replay: { replay(item) }, canRetry: canRetry,
                               retry: { retry(item) })
              .id(item.id)
          }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
      }
      .onChange(of: items.count) { _ in
        guard let last = items.last else { return }
        withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
      }
    }
  }
}

private struct ConversationBubble: View {
  let item: ConversationItem
  let copy: () -> Void
  /// Whether tapping one would play right now: false while the recognizer holds the microphone.
  let canReplay: Bool
  let replay: () -> Void
  let canRetry: Bool
  let retry: () -> Void

  private var isA: Bool { item.speaker == .a }
  /// Only a finished translation can be played, so the glyph is absent, not disabled, on a bubble
  /// that is still recognizing, still translating, or whose translation failed. Every other
  /// translated bubble carries it: it is the only way this app makes a sound.
  private var showsReplayControl: Bool { item.speakableTranslation != nil }

  var body: some View {
    // The bubble sizes to its content and the spacer takes what is left, rather than the bubble
    // taking the full width and the spacer 32 points of it. Two near-full-width blocks whose only
    // difference is a 12 point label and two tints one step apart are not two speakers at arm's
    // length; a shape that leans is legible across a table.
    HStack(spacing: 0) {
      if !isA { Spacer(minLength: 64) }
      VStack(alignment: .leading, spacing: 6) {
        Text("Speaker \(item.speaker.rawValue)",
             comment: "Chat bubble heading. %@ is the speaker label, A or B")
          .font(.caption).fontWeight(.semibold).foregroundStyle(item.speaker.deepColor)
        // Two branches rather than one ternary: a ternary between a literal and a variable is a
        // `String`, which takes the verbatim `Text` overload and never reaches the catalog.
        Group {
          if item.transcript.isEmpty {
            Text("Listening...", comment: "Chat bubble placeholder before any words are recognized")
          } else {
            Text(verbatim: item.transcript)
          }
        }
        .font(.body).foregroundStyle(DesignToken.textPrimary)
        ThinDivider()
        Text("To \(item.speaker.counterpart.rawValue) - \(item.targetLanguage.menuName)",
             comment: "Chat bubble destination line. %1$@ is a speaker label, %2$@ a language name")
          .font(.caption).foregroundStyle(DesignToken.textSecondary)
        deliveryLine
      }
      .frame(alignment: .leading)
      .padding(12)
      .background(item.speaker.tintColor)
      .clipShape(RoundedRectangle(cornerRadius: Layout.message))
      // A long press on the bubble offers one labelled `Copy`, rather than copying silently on
      // any long press: the transcript scrolls, so a bare gesture would fire on a slow drag, and
      // the menu is also what puts the action in the accessibility rotor.
      .contextMenu {
        if item.copyableText != nil {
          Button(ConversationCopyModel.action, action: copy)
            .accessibilityIdentifier("copy-bubble")
        }
      }
      // Grouped on the bubble rather than the row, so the accessibility element and the long-press
      // target are the bubble itself and not the empty half of the screen beside it.
      .accessibilityElement(children: .combine)
      .accessibilityIdentifier("conversation-bubble")
      // Applied after the grouping, which is what keeps the replay control its own element rather
      // than a glyph folded into the bubble's combined label.
      .overlay(alignment: .bottomTrailing) {
        if showsReplayControl {
          ReplayButton(isEnabled: canReplay, replay: replay)
        }
      }
      if isA { Spacer(minLength: 64) }
    }
  }

  @ViewBuilder private var deliveryLine: some View {
    switch item.state {
    case .partial:
      Text("Recognizing speech", comment: "Chat bubble state while speech is still being recognized")
        .font(.caption).foregroundStyle(DesignToken.textSecondary)
      provisionalLine
    case .finalizing:
      Text("Translation pending", comment: "Chat bubble state while a translation is in flight")
        .font(.caption).foregroundStyle(DesignToken.textSecondary)
      provisionalLine
    case .translated:
      Text(verbatim: item.translation ?? "")
        .font(.body).fontWeight(.medium).foregroundStyle(DesignToken.textPrimary)
        // Keeps the last line of a long translation clear of the replay glyph in the corner.
        .padding(.trailing, showsReplayControl ? 34 : 0)
    case let .translationFailed(reason):
      // Already localized where it was built, by `TranslationFailureCopy` at the display site.
      // A failed turn is the one thing on this screen that used to be a dead end: the words were
      // said, the transcript is right there, and nothing anywhere offered to send it again.
      VStack(alignment: .leading, spacing: 6) {
        Text(verbatim: reason).font(.caption).foregroundStyle(DesignToken.error)
          .fixedSize(horizontal: false, vertical: true)
        Button(action: retry) {
          Text(verbatim: TranslationFailureCopy.retryAction)
            .font(.caption).fontWeight(.semibold)
            .padding(.horizontal, 12)
            .frame(minHeight: Layout.tapTarget)
        }
        .buttonStyle(.plain)
        .foregroundStyle(canRetry ? DesignToken.textPrimary : DesignToken.textSecondary)
        .background(DesignToken.surface)
        .clipShape(RoundedRectangle(cornerRadius: Layout.control))
        .disabled(!canRetry)
        .accessibilityIdentifier("retry-translation")
        .accessibilityLabel(TranslationFailureCopy.retryAction)
        .accessibilityHint(TranslationFailureCopy.retryHint)
      }
    }
  }

  /// The live translation, while the turn is still being spoken or is waiting for its final answer.
  ///
  /// Same size as a finished translation, because it is the same sentence and it has to be readable
  /// across a table, and deliberately not the same weight or color: the final is `textPrimary` at
  /// `.medium`, this is `textSecondary` at the body's own weight. That is the whole of the
  /// distinction, and it is the same one the rest of the screen already uses for text that is not
  /// the point yet, from the destination line to the session notice. It sits under the state caption
  /// that is already there, so nothing has to say "provisional" in words: `Recognizing speech`
  /// followed by grey text is the caption naming what the text below it is, and that is also how
  /// VoiceOver reads the combined bubble.
  @ViewBuilder private var provisionalLine: some View {
    if let provisional = item.provisionalTranslation {
      Text(verbatim: provisional)
        .font(.body).foregroundStyle(DesignToken.textSecondary)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityIdentifier("provisional-translation")
    }
  }
}

/// The per-bubble play control, and the app's only way of making a sound. While the recognizer
/// holds the microphone it stays but goes disabled, because that is a moment rather than a
/// setting, and the control has to be in the same place when the moment passes.
private struct ReplayButton: View {
  let isEnabled: Bool
  let replay: () -> Void

  var body: some View {
    Button(action: replay) {
      Image(systemName: SpeechGlyph.replay)
        .font(.system(size: 15, weight: .medium))
        .foregroundStyle(isEnabled ? DesignToken.textPrimary : DesignToken.textSecondary)
        .frame(width: Layout.tapTarget, height: Layout.tapTarget)
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .disabled(!isEnabled)
    .accessibilityIdentifier("replay-translation")
    .accessibilityLabel(SpeechOutputCopy.replayAction)
    .accessibilityHint(SpeechOutputCopy.replayHint)
  }
}

private struct BottomBar: View {
  @ObservedObject var viewModel: RealtimeTranslateViewModel
  let startSession: () -> Void
  let openTypedInput: () -> Void
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

  /// The hint line is the first thing to go at the accessibility sizes.
  ///
  /// This bar is a safe-area inset, which means it takes whatever height it asks for and the
  /// transcript gets the rest. At AX5 the hint alone runs to five lines, which pushed the session
  /// action off the bottom edge of the phone and squeezed the conversation, the thing the app is
  /// for, into a couple of hundred points. Nothing is lost by dropping it: every sentence it says
  /// is already the accessibility hint on the control it is about.
  private var showsHint: Bool { dynamicTypeSize < Layout.hintCeiling }

  var body: some View {
    VStack(spacing: 12) {
      ThinDivider()
      HStack(alignment: .top, spacing: 12) {
        PTTButton(speaker: .a, state: viewModel.state, begin: viewModel.beginTurn, end: viewModel.endTurn)
        PTTButton(speaker: .b, state: viewModel.state, begin: viewModel.beginTurn, end: viewModel.endTurn)
      }
      .padding(.horizontal, 16)
      // The hint line is one short sentence with its trailing half empty, so the typed-input
      // control lands there instead of becoming a third and fourth button in the row above. The
      // control stays when the sentence goes: it is an affordance, not commentary.
      HStack(spacing: 8) {
        if showsHint {
          Text(hint)
            .font(.caption).foregroundStyle(DesignToken.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
          Spacer(minLength: 0)
        }
        TypedInputButton(isEnabled: viewModel.canSubmitTypedTranscript, open: openTypedInput)
      }
      .padding(.leading, 16)
      .padding(.trailing, 4)
      sessionButton
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }
    .background(DesignToken.surface)
  }

  private var hint: String {
    switch viewModel.state {
    case .permissionRequired:
      return String(localized: "Grant microphone access to enable push-to-talk.",
                    comment: "Bottom bar hint while the microphone prompt is unanswered")
    case .loadingModel, .modelLoadFailed:
      return String(localized: "Push-to-talk unlocks once the translation model is ready.",
                    comment: "Bottom bar hint while the model is not ready")
    case .error:
      return String(localized: "Resolve the error above to continue.",
                    comment: "Bottom bar hint while a session error banner is showing")
    case .setup:
      return String(localized: "Tap Start session to begin translating.",
                    comment: "Bottom bar hint before a session starts. Start session is a button")
    default:
      break
    }
    if let active = viewModel.state.activeSpeaker {
      return String(localized: "bottomBar.otherSpeakerActive",
                    defaultValue: "Speaker \(active.counterpart.rawValue) cannot begin while Speaker \(active.rawValue) is active.",
                    comment: "Bottom bar hint. %1$@ is the blocked speaker, %2$@ the active one")
    }
    return String(localized: "Hold a button to talk, or tap once to start and again to stop.",
                  comment: "Bottom bar hint while the session is idle and ready")
  }

  /// One slot, three actions, because there is only ever one thing to do to a session from here.
  ///
  /// The middle one is the new one. A 1.9 GB transfer used to show a disabled `Start Session` and
  /// nothing else: the only ways to stop it were to background the app or to delete it, and the
  /// download would still be running. `End session` already stops the transfer as well as the
  /// screen watching it, so the cancel is that same path under the name it has while a model is
  /// being prepared. A local load has no transfer to stop and is abandoned the same way.
  @ViewBuilder private var sessionButton: some View {
    if viewModel.canCancelModelPreparation {
      outlinedAction(title: SessionActionCopy.cancelPreparation, identifier: "cancel-model-preparation",
                     action: viewModel.endSession)
    } else if viewModel.isSessionLive {
      outlinedAction(title: SessionActionCopy.end, identifier: "end-session",
                     action: viewModel.endSession)
    } else {
      Button(action: startSession) {
        Text(verbatim: SessionActionCopy.start)
          .font(.footnote).fontWeight(.semibold)
          .frame(maxWidth: .infinity, minHeight: Layout.tapTarget)
      }
      .buttonStyle(.plain)
      .foregroundStyle(viewModel.canStartSession ? DesignToken.surface : DesignToken.textSecondary)
      .background(viewModel.canStartSession ? DesignToken.accent : DesignToken.surfaceSubtle)
      .clipShape(RoundedRectangle(cornerRadius: Layout.control))
      .disabled(!viewModel.canStartSession)
      .accessibilityIdentifier("start-session")
      .accessibilityLabel(SessionActionCopy.start)
    }
  }

  private func outlinedAction(title: String, identifier: String,
                              action: @escaping () -> Void) -> some View {
    Button(action: action) {
      Text(verbatim: title)
        .font(.footnote).fontWeight(.semibold)
        .frame(maxWidth: .infinity, minHeight: Layout.tapTarget)
    }
    .buttonStyle(.plain)
    .foregroundStyle(DesignToken.textPrimary)
    .background(DesignToken.surface)
    .clipShape(RoundedRectangle(cornerRadius: Layout.control))
    .overlay(RoundedRectangle(cornerRadius: Layout.control).stroke(DesignToken.divider, lineWidth: 1))
    .accessibilityIdentifier(identifier)
    .accessibilityLabel(title)
  }
}

private struct PTTButton: View {
  let speaker: Speaker
  let state: SessionState
  let begin: (Speaker) -> Void
  let end: (Speaker) -> Void

  private var isListening: Bool { state == .listening(speaker) }
  private var isBlocked: Bool {
    switch state {
    case .ready: return false
    case let .listening(active): return active != speaker
    default: return true
    }
  }
  /// The speaker letter, then one translated phrase. The separating space is punctuation and lives
  /// in the code, so neither catalog entry has to begin with a space a translator might drop.
  private var label: Text {
    Text(verbatim: "\(speaker.rawValue) ").fontWeight(.bold).foregroundColor(prefixColor)
      + suffix.fontWeight(.semibold).foregroundColor(contentColor)
  }

  /// The phrase after the speaker letter. Two `Text` branches rather than one ternary between two
  /// literals, so each half can carry its own translator comment.
  private var suffix: Text {
    isListening
      ? Text("recording - release to stop",
             comment: "Push-to-talk button, after the speaker letter, while recording")
      : Text("- hold to talk",
             comment: "Push-to-talk button, after the speaker letter, while idle")
  }
  private var prefixColor: Color {
    if isListening { return DesignToken.surface }
    return isBlocked ? DesignToken.textSecondary : speaker.deepColor
  }
  private var borderColor: Color {
    if isListening { return speaker.accentColor }
    return isBlocked ? DesignToken.divider : speaker.borderColor
  }
  private var blockedHint: String {
    if let active = state.activeSpeaker, active != speaker {
      return String(localized: "ptt.blockedByOtherSpeaker",
                    defaultValue: "Speaker \(speaker.rawValue) cannot start while Speaker \(active.rawValue) is active.",
                    comment: "Push-to-talk accessibility hint. %1$@ is this speaker, %2$@ the active one")
    }
    return String(localized: "Push-to-talk unlocks once the translation model is ready.",
                  comment: "Bottom bar hint while the model is not ready")
  }
  private var containerColor: Color {
    if isListening { return speaker.accentColor }
    return isBlocked ? DesignToken.surfaceSubtle : DesignToken.surface
  }
  private var contentColor: Color {
    if isListening { return DesignToken.surface }
    return isBlocked ? DesignToken.textSecondary : DesignToken.textPrimary
  }

  var body: some View {
    Button(action: { isListening ? end(speaker) : begin(speaker) }, label: {
      label
        .font(.footnote)
        .multilineTextAlignment(.center)
        // Wraps to as many lines as it needs instead of truncating. Without it, the two controls
        // this app is built around read "A - hol..." and "B - hol..." at the accessibility sizes:
        // an ellipsis where the instruction should be, on the only two buttons that matter.
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, minHeight: Layout.tapTarget)
        .padding(.vertical, 14)
        .padding(.horizontal, 4)
    })
    .buttonStyle(.plain)
    .background(containerColor)
    .clipShape(RoundedRectangle(cornerRadius: Layout.control))
    .overlay(
      RoundedRectangle(cornerRadius: Layout.control).stroke(borderColor, lineWidth: 1)
    )
    .disabled(isBlocked)
    .simultaneousGesture(LongPressGesture(minimumDuration: 0.15).onEnded { _ in
      if !isListening && !isBlocked { begin(speaker) }
    })
    .accessibilityLabel(
      isListening
        ? String(localized: "ptt.accessibility.end",
                 defaultValue: "End Speaker \(speaker.rawValue)'s turn",
                 comment: "Push-to-talk accessibility label while recording. %@ is A or B")
        : String(localized: "ptt.accessibility.start",
                 defaultValue: "Start Speaker \(speaker.rawValue)'s turn",
                 comment: "Push-to-talk accessibility label while idle. %@ is A or B")
    )
    .accessibilityHint(
      isBlocked
        ? blockedHint
        : String(localized: "Hold to talk, or tap once to start and again to end.",
                 comment: "Push-to-talk accessibility hint while it is available")
    )
  }
}
