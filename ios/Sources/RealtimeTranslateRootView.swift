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
  static let tintB = Color(red: 240 / 255, green: 240 / 255, blue: 240 / 255)
  static let borderB = Color(red: 232 / 255, green: 232 / 255, blue: 232 / 255)
}

extension Speaker {
  var accentColor: Color { self == .a ? DesignToken.accentA : DesignToken.accentB }
  var deepColor: Color { self == .a ? DesignToken.deepA : DesignToken.deepB }
  var tintColor: Color { self == .a ? DesignToken.tintA : DesignToken.tintB }
  var borderColor: Color { self == .a ? DesignToken.borderA : DesignToken.borderB }
}

/// The official ZETIC logo lockup, from `Assets.xcassets/ZeticLogo`, as the button that opens
/// the settings drawer. The chevron is the only affordance that says the lockup is tappable.
private struct ZeticWordmarkButton: View {
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      HStack(spacing: 4) {
        Image("ZeticLogo")
          .resizable()
          .scaledToFit()
          .frame(height: 16)
        Image(systemName: "chevron.down")
          .font(.system(size: 9, weight: .semibold))
          .foregroundStyle(DesignToken.textSecondary)
      }
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityIdentifier("zetic-settings")
    // The `Text` overload rather than the string one, so the label can carry a translator comment
    // and still resolve against the environment locale.
    .accessibilityLabel(Text("ZETIC, opens settings",
                             comment: "Accessibility label for the wordmark button in the navigation bar"))
  }
}

enum Layout {
  static let message: CGFloat = 16
  static let control: CGFloat = 20
}

/// One screen holds everything: status, a per-speaker language bar, an inline session banner,
/// the chat transcript, and the A/B push-to-talk controls.
///
/// The first-run surfaces sit above it as overlays rather than as separate destinations, so the
/// main screen is never rebuilt on the way in and there is no navigation to unwind.
struct RealtimeTranslateRootView: View {
  @StateObject var viewModel: RealtimeTranslateViewModel
  @StateObject private var settings = SettingsDrawerModel.fromLaunchArguments()
  @StateObject private var firstRun: FirstRunModel
  @StateObject private var conversationCopy = ConversationCopyModel()
  @StateObject private var typedInput = TypedInputModel()
  @AppStorage(FirstRunDefaults.welcomeSeenKey) private var welcomeSeen = false
  @AppStorage(FirstRunDefaults.permissionPrimingSeenKey) private var primingSeen = false
  /// The mute toggle's stored state. The view model seeds itself from the same key, so this is
  /// the one place the preference is written and there is no second copy to drift.
  @AppStorage(SpeechOutputDefaults.mutedKey) private var speechMuted = false
  /// The app-language override, as its raw value. `@AppStorage` cannot bind an enum without a
  /// `RawRepresentable` conformance that would then also have to survive an unknown stored value,
  /// so the raw string is the stored form and `AppLanguage.named` is the one tolerant reader.
  @AppStorage(AppLanguageDefaults.storageKey) private var appLanguageRaw = AppLanguage.system.rawValue
  @Environment(\.scenePhase) private var scenePhase
  /// Holds the display awake while a session is live. A reference, not observed state: nothing on
  /// screen depends on it, so it must never invalidate the body it is driven from.
  @State private var screenAwake = ScreenAwakeController()

  @MainActor init(viewModel: RealtimeTranslateViewModel,
                  firstRun: FirstRunModel = .fromLaunchArguments()) {
    _viewModel = StateObject(wrappedValue: viewModel)
    _firstRun = StateObject(wrappedValue: firstRun)
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
                              isSessionLive: viewModel.isSessionLive,
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
        viewModel.setMuted(speechMuted)
        updateScreenAwake()
      }
      .onDisappear { screenAwake.release() }
      .onChange(of: viewModel.state) { _ in updateScreenAwake() }
      .onChange(of: scenePhase) { _ in updateScreenAwake() }
      .onChange(of: speechMuted) { viewModel.setMuted($0) }
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
        // The mute toggle rides the status strip: that row is one short line of text with the
        // whole trailing half empty, so the app's only always-present control lands there without
        // crowding the wordmark or adding a row of chrome.
        StatusStrip(title: viewModel.state.title, isMuted: speechMuted,
                    toggleMute: { speechMuted.toggle() })
        ThinDivider()
        LanguageBar(viewModel: viewModel)
        SessionBanner(viewModel: viewModel, startSession: startSession)
        // The copy confirmation sits at the bottom of the transcript rather than the bottom of the
        // screen, so it never lands on top of the push-to-talk row or the session action.
        ConversationList(items: viewModel.items, emptyHint: emptyHint, copy: conversationCopy.copy,
                         isMuted: viewModel.isMuted, replay: viewModel.replay)
          .overlay(alignment: .bottom) {
            ToastLayer(center: conversationCopy.toasts, identifier: "copy-toast")
          }
      }
      .background(DesignToken.surface)
      // A plain `String`, not a literal: the product name is the same in every language and must
      // never reach the catalog.
      .navigationTitle(AppText.productName)
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        // iOS 26 wraps toolbar buttons in a glass capsule; the minimal chrome stays flat.
        if #available(iOS 26.0, *) {
          ToolbarItem(placement: .navigationBarTrailing) {
            ZeticWordmarkButton(action: settings.open)
          }
          .sharedBackgroundVisibility(.hidden)
        } else {
          ToolbarItem(placement: .navigationBarTrailing) {
            ZeticWordmarkButton(action: settings.open)
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

  private var emptyHint: String {
    viewModel.isSessionLive
      ? String(localized: "Speaker A or B can begin speaking.",
               comment: "Empty transcript hint while a session is live")
      : String(localized: "Choose the languages above, then start the session.",
               comment: "Empty transcript hint before a session starts")
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

private struct StatusStrip: View {
  let title: String
  let isMuted: Bool
  let toggleMute: () -> Void

  var body: some View {
    HStack(spacing: 8) {
      Text(title)
        .font(.caption)
        .foregroundStyle(DesignToken.textSecondary)
        // Wraps at the accessibility sizes: "Translation Model Unavailable" truncated to
        // "Translation Model" is a status line that says the opposite of what it means.
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityLabel(Text("Session status: \(title)",
                                 comment: "Accessibility label for the status strip. %@ is the status"))
      SpeechMuteToggle(isMuted: isMuted, toggle: toggleMute)
    }
    .padding(.leading, 16)
    .padding(.trailing, 8)
    .padding(.vertical, 8)
  }
}

/// The one sound control: speaker on, speaker crossed out off. The glyph is the whole face, so
/// the label carries the state in words for anything that cannot see it.
private struct SpeechMuteToggle: View {
  let isMuted: Bool
  let toggle: () -> Void

  var body: some View {
    Button(action: toggle) {
      Image(systemName: isMuted ? "speaker.slash" : "speaker.wave.2")
        .font(.system(size: 13, weight: .medium))
        .foregroundStyle(isMuted ? DesignToken.textSecondary : DesignToken.textPrimary)
        .frame(width: 36, height: 28)
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .accessibilityIdentifier("speech-mute")
    .accessibilityLabel(isMuted ? SpeechOutputCopy.soundOffLabel : SpeechOutputCopy.soundOnLabel)
    .accessibilityHint(isMuted ? SpeechOutputCopy.soundOffHint : SpeechOutputCopy.soundOnHint)
  }
}

/// One chip per speaker, mirroring the side their chat bubbles appear on.
private struct LanguageBar: View {
  @ObservedObject var viewModel: RealtimeTranslateViewModel

  var body: some View {
    HStack(spacing: 12) {
      speakerMenu(.a, source: $viewModel.sourceLanguageA, target: $viewModel.targetLanguageA)
      Spacer(minLength: 12)
      speakerMenu(.b, source: $viewModel.sourceLanguageB, target: $viewModel.targetLanguageB)
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 8)
    ThinDivider()
  }

  @ViewBuilder private func speakerMenu(
    _ speaker: Speaker, source: Binding<SpeechSourceLanguage>, target: Binding<TargetLanguage>
  ) -> some View {
    Menu {
      // The `label:` form, because the shorthand `Picker("...")` init has nowhere to put a
      // translator comment. The language names themselves are `verbatim`: see `TargetLanguage`.
      Picker(selection: target) {
        ForEach(TargetLanguage.hyMT2Candidates) { Text(verbatim: $0.name).tag($0) }
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
      // other is a Hy-MT2 language name. A catalog entry of "%@ ·" would be noise.
      (
        Text(verbatim: "\(speaker.rawValue) ·").fontWeight(.bold).foregroundColor(speaker.deepColor)
          + Text(verbatim: " \(target.wrappedValue.name)").fontWeight(.medium)
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
             defaultValue: "Speaker \(speaker.rawValue) languages: reads \(target.wrappedValue.name), speaks \(source.wrappedValue.name)",
             comment: "Language chip accessibility label. %1$@ speaker, %2$@ reading, %3$@ spoken")
    )
  }
}

private struct SessionBanner: View {
  @ObservedObject var viewModel: RealtimeTranslateViewModel
  let startSession: () -> Void

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
        BannerButton(
          title: String(localized: "Allow Microphone Access",
                        comment: "Session banner button that triggers the system prompts"),
          action: viewModel.requestMicrophonePermission
        )
        BannerButton(
          title: String(localized: "Open App Settings",
                        comment: "Session banner button that opens this app's page in iOS Settings"),
          action: viewModel.openAppSettings
        )
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
        Text("Speaker controls unlock when the model is ready.",
             comment: "Session banner body text while the model loads")
          .font(.caption).foregroundStyle(DesignToken.textSecondary)
          .fixedSize(horizontal: false, vertical: true)
      }
    case let .modelLoadFailed(reason):
      banner {
        // The reason is already localized: it comes through `TranslationFailureCopy`.
        Text(verbatim: reason).font(.subheadline).foregroundStyle(DesignToken.error)
          .fixedSize(horizontal: false, vertical: true)
        BannerButton(
          title: String(localized: "Retry Model Load",
                        comment: "Session banner button that loads the model again after a failure"),
          action: startSession
        )
        .accessibilityIdentifier("retry-model-load")
      }
    case .endingSession:
      banner {
        Text("Closing translation session...",
             comment: "Session banner body text while the session unwinds")
          .font(.subheadline).foregroundStyle(DesignToken.textSecondary)
          .accessibilityIdentifier("closing-session")
      }
    case let .error(reason):
      banner {
        Text(verbatim: reason).font(.subheadline).foregroundStyle(DesignToken.error)
          .fixedSize(horizontal: false, vertical: true)
        BannerButton(
          title: String(localized: "Try Again",
                        comment: "Session banner button that retries after a runtime error"),
          action: viewModel.requestMicrophonePermission
        )
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
  let emptyHint: String
  let copy: (ConversationItem) -> Void
  let isMuted: Bool
  let replay: (ConversationItem) -> Void

  var body: some View {
    ScrollViewReader { proxy in
      ScrollView {
        LazyVStack(alignment: .leading, spacing: 12) {
          if items.isEmpty {
            Text(emptyHint)
              .font(.subheadline)
              .foregroundStyle(DesignToken.textSecondary)
              .fixedSize(horizontal: false, vertical: true)
              .frame(maxWidth: .infinity, alignment: .leading)
          }
          ForEach(items) { item in
            ConversationBubble(item: item, copy: { copy(item) }, isMuted: isMuted,
                               replay: { replay(item) })
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
  let isMuted: Bool
  let replay: () -> Void

  private var isA: Bool { item.speaker == .a }
  /// Only a finished translation can be replayed, so the glyph is absent, not disabled, on a
  /// bubble that is still recognizing, still translating, or whose translation failed.
  private var canReplay: Bool { item.speakableTranslation != nil }

  var body: some View {
    HStack(spacing: 0) {
      if !isA { Spacer(minLength: 32) }
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
        Text("To \(item.speaker.counterpart.rawValue) - \(item.targetLanguage.name)",
             comment: "Chat bubble destination line. %1$@ is a speaker label, %2$@ a language name")
          .font(.caption).foregroundStyle(DesignToken.textSecondary)
        deliveryLine
      }
      .frame(maxWidth: .infinity, alignment: .leading)
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
        if canReplay {
          ReplayButton(isMuted: isMuted, replay: replay).padding([.trailing, .bottom], 8)
        }
      }
      if isA { Spacer(minLength: 32) }
    }
  }

  @ViewBuilder private var deliveryLine: some View {
    switch item.state {
    case .partial:
      Text("Recognizing speech", comment: "Chat bubble state while speech is still being recognized")
        .font(.caption).foregroundStyle(DesignToken.textSecondary)
    case .finalizing:
      Text("Translation pending", comment: "Chat bubble state while a translation is in flight")
        .font(.caption).foregroundStyle(DesignToken.textSecondary)
    case .translated:
      Text(verbatim: item.translation ?? "")
        .font(.body).fontWeight(.medium).foregroundStyle(DesignToken.textPrimary)
        // Keeps the last line of a long translation clear of the replay glyph in the corner.
        .padding(.trailing, canReplay ? 30 : 0)
    case let .translationFailed(reason):
      // Already localized where it was built, by `TranslationFailureCopy` at the display site.
      Text(verbatim: reason).font(.caption).foregroundStyle(DesignToken.error)
    }
  }
}

/// The per-bubble replay control. Muted, it stays visible but inert: the bubble still has a
/// translation to speak, the app is simply not speaking anything right now.
private struct ReplayButton: View {
  let isMuted: Bool
  let replay: () -> Void

  var body: some View {
    Button(action: replay) {
      Image(systemName: "speaker.wave.2")
        .font(.system(size: 12, weight: .medium))
        .foregroundStyle(isMuted ? DesignToken.textSecondary : DesignToken.textPrimary)
        .frame(width: 28, height: 24)
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .disabled(isMuted)
    .accessibilityIdentifier("replay-translation")
    .accessibilityLabel(SpeechOutputCopy.replayAction)
    .accessibilityHint(SpeechOutputCopy.replayHint)
  }
}

private struct BottomBar: View {
  @ObservedObject var viewModel: RealtimeTranslateViewModel
  let startSession: () -> Void
  let openTypedInput: () -> Void

  var body: some View {
    VStack(spacing: 12) {
      ThinDivider()
      HStack(alignment: .top, spacing: 12) {
        PTTButton(speaker: .a, state: viewModel.state, begin: viewModel.beginTurn, end: viewModel.endTurn)
        PTTButton(speaker: .b, state: viewModel.state, begin: viewModel.beginTurn, end: viewModel.endTurn)
      }
      .padding(.horizontal, 16)
      // The hint line is one short sentence with its trailing half empty, so the typed-input
      // control lands there instead of becoming a third and fourth button in the row above.
      HStack(spacing: 8) {
        Text(hint)
          .font(.caption).foregroundStyle(DesignToken.textSecondary)
          .frame(maxWidth: .infinity, alignment: .leading)
        TypedInputButton(isEnabled: viewModel.canSubmitTypedTranscript, open: openTypedInput)
      }
      .padding(.leading, 16)
      .padding(.trailing, 8)
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
    case .endingSession:
      return String(localized: "Wait while the session ends.",
                    comment: "Bottom bar hint while the session is unwinding")
    case .setup, .ended:
      return String(localized: "Tap Start Session to begin translating.",
                    comment: "Bottom bar hint before a session starts. Start Session is a button")
    default:
      break
    }
    if let active = viewModel.state.activeSpeaker {
      return String(localized: "bottomBar.otherSpeakerActive",
                    defaultValue: "Speaker \(active.counterpart.rawValue) cannot begin while speaker \(active.rawValue) is active.",
                    comment: "Bottom bar hint. %1$@ is the blocked speaker, %2$@ the active one")
    }
    return String(localized: "Hold a button to talk, or tap once to start and again to stop.",
                  comment: "Bottom bar hint while the session is idle and ready")
  }

  @ViewBuilder private var sessionButton: some View {
    if viewModel.isSessionLive {
      Button(action: viewModel.endSession) {
        Text("End Session", comment: "Bottom bar action that ends a live session")
          .font(.footnote).fontWeight(.semibold)
          .frame(maxWidth: .infinity)
          .padding(.vertical, 12)
      }
      .buttonStyle(.plain)
      .foregroundStyle(DesignToken.textPrimary)
      .background(DesignToken.surface)
      .clipShape(RoundedRectangle(cornerRadius: Layout.control))
      .overlay(RoundedRectangle(cornerRadius: Layout.control).stroke(DesignToken.divider, lineWidth: 1))
      .disabled(viewModel.state == .endingSession)
      .accessibilityIdentifier("end-session")
      .accessibilityLabel("End Session")
    } else {
      Button(action: startSession) {
        Text("Start Session", comment: "Bottom bar action that starts a session")
          .font(.footnote).fontWeight(.semibold)
          .frame(maxWidth: .infinity)
          .padding(.vertical, 12)
      }
      .buttonStyle(.plain)
      .foregroundStyle(viewModel.canStartSession ? DesignToken.surface : DesignToken.textSecondary)
      .background(viewModel.canStartSession ? DesignToken.accent : DesignToken.surfaceSubtle)
      .clipShape(RoundedRectangle(cornerRadius: Layout.control))
      .disabled(!viewModel.canStartSession)
      .accessibilityIdentifier("start-session")
      .accessibilityLabel("Start Session")
    }
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
                    defaultValue: "Speaker \(speaker.rawValue) cannot start while speaker \(active.rawValue) is active.",
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
        .frame(maxWidth: .infinity)
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
        ? String(localized: "ptt.accessibility.end", defaultValue: "End \(speaker.rawValue) Turn",
                 comment: "Push-to-talk accessibility label while recording. %@ is A or B")
        : String(localized: "ptt.accessibility.start", defaultValue: "Start \(speaker.rawValue) Turn",
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
