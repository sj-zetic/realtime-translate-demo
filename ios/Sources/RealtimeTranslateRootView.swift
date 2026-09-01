import SwiftUI

enum DesignToken {
  static let primary = Color(red: 59 / 255, green: 91 / 255, blue: 219 / 255)
  static let secondary = Color(red: 11 / 255, green: 114 / 255, blue: 133 / 255)
  static let surfaceMuted = Color(red: 241 / 255, green: 243 / 255, blue: 245 / 255)
  static let textPrimary = Color(red: 31 / 255, green: 41 / 255, blue: 55 / 255)
  static let textSecondary = Color(red: 107 / 255, green: 114 / 255, blue: 128 / 255)
  static let error = Color(red: 201 / 255, green: 42 / 255, blue: 42 / 255)
}

struct RealtimeTranslateRootView: View {
  @StateObject var viewModel: RealtimeTranslateViewModel

  var body: some View {
    NavigationStack {
      Group {
        switch viewModel.state {
        case .permissionRequired, .setup, .loadingModel, .modelLoadFailed, .ended:
          SetupView(viewModel: viewModel)
        case .endingSession:
          EndingSessionView()
        case .error where viewModel.items.isEmpty:
          ErrorView(reason: errorReason, retry: viewModel.requestMicrophonePermission)
        default:
          ConversationView(viewModel: viewModel)
        }
      }
      .navigationTitle("Turn Translate")
    }
    .tint(DesignToken.primary)
  }

  private var errorReason: String {
    if case let .error(reason) = viewModel.state { return reason }
    return "Unable to process the request."
  }
}

private struct EndingSessionView: View {
  var body: some View {
    ProgressView("Closing translation session...")
      .accessibilityIdentifier("closing-session")
  }
}

private struct SetupView: View {
  @ObservedObject var viewModel: RealtimeTranslateViewModel

  var body: some View {
    Form {
      speakerSection(.a, source: $viewModel.sourceLanguageA, target: $viewModel.targetLanguageA)
      speakerSection(.b, source: $viewModel.sourceLanguageB, target: $viewModel.targetLanguageB)
      Section("Permissions") {
        Text("Microphone and speech recognition permissions are required.")
          .foregroundStyle(DesignToken.textSecondary)
        Button("Allow Microphone Access", action: viewModel.requestMicrophonePermission)
        Button("Open App Settings", action: viewModel.openAppSettings)
      }
      sessionSection
    }
  }

  @ViewBuilder private var sessionSection: some View {
    switch viewModel.state {
    case .setup, .ended:
      Section {
        Button("Start Session", action: viewModel.startSession)
          .buttonStyle(.borderedProminent)
          .accessibilityIdentifier("start-session")
      } footer: {
        Text("The translation model loads on this device before either speaker can talk.")
      }
    case let .loadingModel(progress):
      Section("Preparing Translation") {
        ProgressView(value: progress)
        Text(progress.map { "Downloading model \(Int($0 * 100))%" } ?? "Loading model...")
      }
    case let .modelLoadFailed(reason):
      Section("Translation Model Unavailable") {
        Text(reason).foregroundStyle(DesignToken.error)
        Button("Retry Model Load", action: viewModel.startSession)
          .buttonStyle(.borderedProminent)
          .accessibilityIdentifier("retry-model-load")
      }
    default:
      EmptyView()
    }
  }

  @ViewBuilder private func speakerSection(
    _ speaker: Speaker, source: Binding<SpeechSourceLanguage>, target: Binding<TargetLanguage>
  ) -> some View {
    Section("\(speaker.rawValue) Settings") {
      Picker("\(speaker.rawValue) Spoken Language", selection: source) {
        ForEach(viewModel.availableSourceLanguages) { Text($0.name).tag($0) }
      }
      .disabled(!viewModel.canEditSessionSettings)
      .accessibilityIdentifier("source-language-\(speaker.rawValue)")
      Picker("Translation Language for \(speaker.rawValue)", selection: target) {
        ForEach(TargetLanguage.hyMT2Candidates) { Text($0.name).tag($0) }
      }
      .disabled(!viewModel.canEditSessionSettings)
      .accessibilityIdentifier("target-language-\(speaker.rawValue)")
    }
  }
}

private struct ConversationView: View {
  @ObservedObject var viewModel: RealtimeTranslateViewModel

  var body: some View {
    VStack(spacing: 0) {
      StatusHeader(state: viewModel.state)
      List(viewModel.items) { ConversationBubble(item: $0) }
        .listStyle(.plain)
    }
    .safeAreaInset(edge: .bottom, spacing: 0) { controls }
  }

  private var controls: some View {
    VStack(spacing: 8) {
      if case .error = viewModel.state { ErrorBanner(reason: "Try speech recognition again or check Settings.") }
      if viewModel.state != .ended {
        HStack(spacing: 12) {
          PTTButton(speaker: .a, state: viewModel.state, begin: viewModel.beginTurn, end: viewModel.endTurn)
          PTTButton(speaker: .b, state: viewModel.state, begin: viewModel.beginTurn, end: viewModel.endTurn)
        }
        Button("End Session", action: viewModel.endSession)
          .accessibilityLabel("End Session")
      }
    }
    .padding(16)
    .background(.bar)
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
    isListening ? "End \(speaker.rawValue) Turn" : "Hold to Talk as \(speaker.rawValue)"
  }

  var body: some View {
    Button(action: { isListening ? end(speaker) : begin(speaker) }, label: {
      Text(label).frame(maxWidth: .infinity)
    })
    .buttonStyle(.borderedProminent)
    .tint(speaker == .a ? DesignToken.primary : DesignToken.secondary)
    .disabled(isBlocked)
    .simultaneousGesture(LongPressGesture(minimumDuration: 0.15).onEnded { _ in
      if !isListening && !isBlocked { begin(speaker) }
    })
    .accessibilityLabel(isListening ? "End \(speaker.rawValue) Turn" : "Start \(speaker.rawValue) Turn")
    .accessibilityHint(
      isBlocked ? "Another turn or translation is in progress." : "Hold to talk, or tap once to start and again to end."
    )
  }
}

private struct StatusHeader: View {
  let state: SessionState
  var body: some View {
    Label(state.title, systemImage: "mic.fill")
      .font(.subheadline).foregroundStyle(DesignToken.textPrimary)
      .frame(maxWidth: .infinity, alignment: .leading).padding(12).background(DesignToken.surfaceMuted)
      .accessibilityLabel(state.title)
  }
}

private struct ConversationBubble: View {
  let item: ConversationItem
  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text("\(item.speaker.rawValue) - To \(item.targetLanguage.name)")
        .font(.caption).foregroundStyle(DesignToken.textSecondary)
      Text(item.transcript.isEmpty ? "Listening..." : item.transcript)
        .font(.body).foregroundStyle(DesignToken.textPrimary)
      switch item.state {
      case .partial, .finalizing:
        Text("Finalizing transcript").font(.caption).foregroundStyle(DesignToken.textSecondary)
      case .translated: if let translation = item.translation { Text(translation).foregroundStyle(DesignToken.primary) }
      case let .translationFailed(reason): Text(reason).font(.caption).foregroundStyle(DesignToken.error)
      }
    }
    .padding(12).background(DesignToken.surfaceMuted).clipShape(RoundedRectangle(cornerRadius: 16))
    .accessibilityElement(children: .combine)
  }
}

private struct ErrorBanner: View {
  let reason: String
  var body: some View { Text(reason).font(.caption).foregroundStyle(DesignToken.error).padding(.horizontal, 16) }
}

private struct ErrorView: View {
  let reason: String
  let retry: () -> Void
  var body: some View {
    VStack(spacing: 12) {
      Label("Unable to process the request", systemImage: "exclamationmark.triangle.fill")
      Text(reason).multilineTextAlignment(.center)
      Button("Try Again", action: retry)
    }.foregroundStyle(DesignToken.error).padding(16)
  }
}
