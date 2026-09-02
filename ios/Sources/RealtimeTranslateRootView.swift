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
    .accessibilityLabel("ZETIC, opens settings")
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
  @StateObject private var settings = SettingsDrawerModel()
  @StateObject private var firstRun: FirstRunModel
  @StateObject private var conversationCopy = ConversationCopyModel()
  @StateObject private var typedInput = TypedInputModel()
  @AppStorage(FirstRunDefaults.welcomeSeenKey) private var welcomeSeen = false
  @AppStorage(FirstRunDefaults.permissionPrimingSeenKey) private var primingSeen = false
  /// The mute toggle's stored state. The view model seeds itself from the same key, so this is
  /// the one place the preference is written and there is no second copy to drift.
  @AppStorage(SpeechOutputDefaults.mutedKey) private var speechMuted = false
  @Environment(\.scenePhase) private var scenePhase
  /// Holds the display awake while a session is live. A reference, not observed state: nothing on
  /// screen depends on it, so it must never invalidate the body it is driven from.
  @State private var screenAwake = ScreenAwakeController()

  @MainActor init(viewModel: RealtimeTranslateViewModel,
                  firstRun: FirstRunModel = .fromLaunchArguments()) {
    _viewModel = StateObject(wrappedValue: viewModel)
    _firstRun = StateObject(wrappedValue: firstRun)
  }

  var body: some View {
    mainScreen
      .overlay {
        SettingsDrawerOverlay(model: settings, canClearConversation: viewModel.canClearConversation,
                              clearConversation: viewModel.clearConversation)
      }
      .overlay { firstRunOverlay }
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
      .navigationTitle("Turn Translate")
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
      ? "Speaker A or B can begin speaking."
      : "Choose the languages above, then start the session."
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
          .padding(.horizontal, 16)
          .padding(.vertical, 10)
          .background(DesignToken.textPrimary)
          .clipShape(RoundedRectangle(cornerRadius: Layout.control))
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
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityLabel("Session status: \(title)")
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
      Picker("Reading language", selection: target) {
        ForEach(TargetLanguage.hyMT2Candidates) { Text($0.name).tag($0) }
      }
      .pickerStyle(.inline)
      Picker("Spoken language", selection: source) {
        ForEach(viewModel.availableSourceLanguages) { Text($0.name).tag($0) }
      }
      .pickerStyle(.inline)
    } label: {
      (
        Text("\(speaker.rawValue) ·").fontWeight(.bold).foregroundColor(speaker.deepColor)
          + Text(" \(target.wrappedValue.name)").fontWeight(.medium)
            .foregroundColor(DesignToken.textPrimary)
      )
      .font(.caption)
      .lineLimit(1)
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
      "Speaker \(speaker.rawValue) languages: reads \(target.wrappedValue.name), "
        + "speaks \(source.wrappedValue.name)"
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
        Text("Turn Translate needs microphone and speech recognition access on this device.")
          .font(.subheadline).foregroundStyle(DesignToken.textPrimary)
        BannerButton(title: "Allow Microphone Access", action: viewModel.requestMicrophonePermission)
        BannerButton(title: "Open App Settings", action: viewModel.openAppSettings)
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
        Text("Speaker controls unlock when the model is ready.")
          .font(.caption).foregroundStyle(DesignToken.textSecondary)
      }
    case let .modelLoadFailed(reason):
      banner {
        Text(reason).font(.subheadline).foregroundStyle(DesignToken.error)
        BannerButton(title: "Retry Model Load", action: startSession)
          .accessibilityIdentifier("retry-model-load")
      }
    case .endingSession:
      banner {
        Text("Closing translation session...")
          .font(.subheadline).foregroundStyle(DesignToken.textSecondary)
          .accessibilityIdentifier("closing-session")
      }
    case let .error(reason):
      banner {
        Text(reason).font(.subheadline).foregroundStyle(DesignToken.error)
        BannerButton(title: "Try Again", action: viewModel.requestMicrophonePermission)
      }
    default:
      EmptyView()
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
      Text(title)
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
        Text("Speaker \(item.speaker.rawValue)")
          .font(.caption).fontWeight(.semibold).foregroundStyle(item.speaker.deepColor)
        Text(item.transcript.isEmpty ? "Listening..." : item.transcript)
          .font(.body).foregroundStyle(DesignToken.textPrimary)
        ThinDivider()
        Text("To \(item.speaker.counterpart.rawValue) - \(item.targetLanguage.name)")
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
      Text("Recognizing speech").font(.caption).foregroundStyle(DesignToken.textSecondary)
    case .finalizing:
      Text("Translation pending").font(.caption).foregroundStyle(DesignToken.textSecondary)
    case .translated:
      Text(item.translation ?? "")
        .font(.body).fontWeight(.medium).foregroundStyle(DesignToken.textPrimary)
        // Keeps the last line of a long translation clear of the replay glyph in the corner.
        .padding(.trailing, canReplay ? 30 : 0)
    case let .translationFailed(reason):
      Text(reason).font(.caption).foregroundStyle(DesignToken.error)
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
      return "Grant microphone access to enable push-to-talk."
    case .loadingModel, .modelLoadFailed:
      return "Push-to-talk unlocks once the translation model is ready."
    case .error:
      return "Resolve the error above to continue."
    case .endingSession:
      return "Wait while the session ends."
    case .setup, .ended:
      return "Tap Start Session to begin translating."
    default:
      break
    }
    if let active = viewModel.state.activeSpeaker {
      return "Speaker \(active.counterpart.rawValue) cannot begin while speaker \(active.rawValue) is active."
    }
    return "Hold a button to talk, or tap once to start and again to stop."
  }

  @ViewBuilder private var sessionButton: some View {
    if viewModel.isSessionLive {
      Button(action: viewModel.endSession) {
        Text("End Session")
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
        Text("Start Session")
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
  private var label: Text {
    Text(speaker.rawValue).fontWeight(.bold).foregroundColor(prefixColor)
      + Text(isListening ? " recording - release to stop" : " - hold to talk")
        .fontWeight(.semibold).foregroundColor(contentColor)
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
      return "Speaker \(speaker.rawValue) cannot start while speaker \(active.rawValue) is active."
    }
    return "Push-to-talk unlocks once the translation model is ready."
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
    .accessibilityLabel(isListening ? "End \(speaker.rawValue) Turn" : "Start \(speaker.rawValue) Turn")
    .accessibilityHint(
      isBlocked ? blockedHint : "Hold to talk, or tap once to start and again to end."
    )
  }
}
