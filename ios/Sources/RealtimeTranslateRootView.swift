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

/// Typographic placeholder for the ZETIC wordmark. Replace with the official ZETIC wordmark
/// vector (an image asset in the app bundle rendered through `Image`) when the brand asset is
/// added to the repository; keep the size, placement, and `ZETIC` accessibility label.
private struct ZeticWordmark: View {
  var body: some View {
    Text("ZETIC")
      .font(.system(size: 13, weight: .heavy))
      .kerning(13 * 0.08)
      .foregroundStyle(DesignToken.textPrimary)
      .accessibilityLabel("ZETIC")
  }
}

private enum Layout {
  static let message: CGFloat = 16
  static let control: CGFloat = 20
}

/// One screen holds everything: status, a per-speaker language bar, an inline session banner,
/// the chat transcript, and the A/B push-to-talk controls.
struct RealtimeTranslateRootView: View {
  @StateObject var viewModel: RealtimeTranslateViewModel

  var body: some View {
    NavigationStack {
      VStack(spacing: 0) {
        StatusStrip(title: viewModel.state.title)
        ThinDivider()
        LanguageBar(viewModel: viewModel)
        SessionBanner(viewModel: viewModel)
        ConversationList(items: viewModel.items, emptyHint: emptyHint)
      }
      .background(DesignToken.surface)
      .navigationTitle("Turn Translate")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .navigationBarTrailing) { ZeticWordmark() }
      }
      .safeAreaInset(edge: .bottom, spacing: 0) { BottomBar(viewModel: viewModel) }
    }
    .tint(DesignToken.accent)
  }

  private var emptyHint: String {
    viewModel.isSessionLive
      ? "Speaker A or B can begin speaking."
      : "Choose the languages above, then start the session."
  }
}

private struct ThinDivider: View {
  var body: some View { Rectangle().fill(DesignToken.divider).frame(height: 1) }
}

private struct StatusStrip: View {
  let title: String

  var body: some View {
    Text(title)
      .font(.caption)
      .foregroundStyle(DesignToken.textSecondary)
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.horizontal, 16)
      .padding(.vertical, 12)
      .accessibilityLabel("Session status: \(title)")
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
      banner {
        Text(progress.map { "Loading translation model \(Int($0 * 100))%" } ?? "Loading translation model...")
          .font(.subheadline).foregroundStyle(DesignToken.textPrimary)
        ProgressView(value: progress).tint(DesignToken.accent)
        Text("Speaker controls unlock when the model is ready.")
          .font(.caption).foregroundStyle(DesignToken.textSecondary)
      }
    case let .modelLoadFailed(reason):
      banner {
        Text(reason).font(.subheadline).foregroundStyle(DesignToken.error)
        BannerButton(title: "Retry Model Load", action: viewModel.startSession)
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
          ForEach(items) { ConversationBubble(item: $0).id($0.id) }
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

  private var isA: Bool { item.speaker == .a }

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
      if isA { Spacer(minLength: 32) }
    }
    .accessibilityElement(children: .combine)
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
    case let .translationFailed(reason):
      Text(reason).font(.caption).foregroundStyle(DesignToken.error)
    }
  }
}

private struct BottomBar: View {
  @ObservedObject var viewModel: RealtimeTranslateViewModel

  var body: some View {
    VStack(spacing: 12) {
      ThinDivider()
      HStack(alignment: .top, spacing: 12) {
        PTTButton(speaker: .a, state: viewModel.state, begin: viewModel.beginTurn, end: viewModel.endTurn)
        PTTButton(speaker: .b, state: viewModel.state, begin: viewModel.beginTurn, end: viewModel.endTurn)
      }
      .padding(.horizontal, 16)
      Text(hint)
        .font(.caption).foregroundStyle(DesignToken.textSecondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
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
      return "Tap Start Session to load the translation model."
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
      Button(action: viewModel.startSession) {
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
