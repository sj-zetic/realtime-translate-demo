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
}

private enum Layout {
  static let message: CGFloat = 16
  static let control: CGFloat = 20
}

/// One screen holds everything: status, an inline session banner, the chat transcript,
/// per-speaker language chips, and the A/B push-to-talk controls.
struct RealtimeTranslateRootView: View {
  @StateObject var viewModel: RealtimeTranslateViewModel

  var body: some View {
    NavigationStack {
      VStack(spacing: 0) {
        StatusStrip(title: viewModel.state.title)
        ThinDivider()
        SessionBanner(viewModel: viewModel)
        ConversationList(items: viewModel.items, emptyHint: emptyHint)
      }
      .background(DesignToken.surface)
      .navigationTitle("Turn Translate")
      .navigationBarTitleDisplayMode(.inline)
      .safeAreaInset(edge: .bottom, spacing: 0) { BottomBar(viewModel: viewModel) }
    }
    .tint(DesignToken.accent)
  }

  private var emptyHint: String {
    viewModel.isSessionLive
      ? "Speaker A or B can begin speaking."
      : "Choose the languages below, then start the session."
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
          .font(.caption).fontWeight(.semibold).foregroundStyle(DesignToken.textSecondary)
        Text(item.transcript.isEmpty ? "Listening..." : item.transcript)
          .font(.body).foregroundStyle(DesignToken.textPrimary)
        ThinDivider()
        Text("To \(item.speaker.counterpart.rawValue) - \(item.targetLanguage.name)")
          .font(.caption).foregroundStyle(DesignToken.textSecondary)
        deliveryLine
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(12)
      .background(isA ? DesignToken.surfaceSubtle : DesignToken.surface)
      .clipShape(RoundedRectangle(cornerRadius: Layout.message))
      .overlay(
        RoundedRectangle(cornerRadius: Layout.message)
          .stroke(isA ? Color.clear : DesignToken.divider, lineWidth: 1)
      )
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
        speakerColumn(.a, source: $viewModel.sourceLanguageA, target: $viewModel.targetLanguageA)
        speakerColumn(.b, source: $viewModel.sourceLanguageB, target: $viewModel.targetLanguageB)
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
    if case .permissionRequired = viewModel.state {
      return "Grant microphone access to enable push-to-talk."
    }
    if let active = viewModel.state.activeSpeaker {
      return "Speaker \(active.counterpart.rawValue) cannot begin while speaker \(active.rawValue) is active."
    }
    if viewModel.isSessionLive {
      return "Hold a button to talk, or tap once to start and again to stop."
    }
    return "Push-to-talk unlocks once the translation model is ready."
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

  @ViewBuilder private func speakerColumn(
    _ speaker: Speaker, source: Binding<SpeechSourceLanguage>, target: Binding<TargetLanguage>
  ) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(speaker.rawValue)
        .font(.subheadline).fontWeight(.bold).foregroundStyle(DesignToken.textSecondary)
        .accessibilityLabel("Speaker \(speaker.rawValue) controls")
      Menu {
        Picker("Speaker \(speaker.rawValue) recognition language", selection: source) {
          ForEach(viewModel.availableSourceLanguages) { Text($0.name).tag($0) }
        }
      } label: {
        LanguageChip(caption: "Speaks", value: source.wrappedValue.name)
      }
      .disabled(!viewModel.canEditLanguages)
      .accessibilityIdentifier("source-language-\(speaker.rawValue)")
      .accessibilityLabel(
        "Speaker \(speaker.rawValue) recognition language selector: \(source.wrappedValue.name)"
      )
      Menu {
        Picker("Speaker \(speaker.rawValue) translation language", selection: target) {
          ForEach(TargetLanguage.hyMT2Candidates) { Text($0.name).tag($0) }
        }
      } label: {
        LanguageChip(caption: "Reads", value: target.wrappedValue.name)
      }
      .disabled(!viewModel.canEditLanguages)
      .accessibilityIdentifier("target-language-\(speaker.rawValue)")
      .accessibilityLabel(
        "Speaker \(speaker.rawValue) translation language selector: \(target.wrappedValue.name)"
      )
      PTTButton(speaker: speaker, state: viewModel.state, begin: viewModel.beginTurn, end: viewModel.endTurn)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}

private struct LanguageChip: View {
  let caption: String
  let value: String

  var body: some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(caption).font(.caption2).foregroundStyle(DesignToken.textSecondary)
      Text(value)
        .font(.caption).fontWeight(.medium).foregroundStyle(DesignToken.textPrimary)
        .lineLimit(2).multilineTextAlignment(.leading)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.horizontal, 12)
    .padding(.vertical, 8)
    .background(DesignToken.surface)
    .clipShape(RoundedRectangle(cornerRadius: Layout.control))
    .overlay(RoundedRectangle(cornerRadius: Layout.control).stroke(DesignToken.divider, lineWidth: 1))
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
  private var label: String {
    isListening ? "\(speaker.rawValue) recording - release to stop" : "\(speaker.rawValue) - hold to talk"
  }
  private var blockedHint: String {
    if let active = state.activeSpeaker, active != speaker {
      return "Speaker \(speaker.rawValue) cannot start while speaker \(active.rawValue) is active."
    }
    return "Push-to-talk unlocks once the translation model is ready."
  }
  private var containerColor: Color {
    if isListening { return DesignToken.accent }
    return isBlocked ? DesignToken.surfaceSubtle : DesignToken.surface
  }
  private var contentColor: Color {
    if isListening { return DesignToken.surface }
    return isBlocked ? DesignToken.textSecondary : DesignToken.textPrimary
  }

  var body: some View {
    Button(action: { isListening ? end(speaker) : begin(speaker) }, label: {
      Text(label)
        .font(.footnote).fontWeight(.semibold)
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .padding(.horizontal, 4)
    })
    .buttonStyle(.plain)
    .foregroundStyle(contentColor)
    .background(containerColor)
    .clipShape(RoundedRectangle(cornerRadius: Layout.control))
    .overlay(
      RoundedRectangle(cornerRadius: Layout.control)
        .stroke(isListening ? DesignToken.accent : DesignToken.divider, lineWidth: 1)
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
