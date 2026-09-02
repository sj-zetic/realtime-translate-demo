import Foundation
import UIKit

/// The three session-comfort behaviours and, more importantly, the decisions behind them.
///
/// None of the effects here can be asserted in a unit test: the idle timer, the Taptic Engine, and
/// the system clipboard all live outside the process the tests can observe. So each behaviour is
/// split in two. The decision is a pure function or a tiny state machine over an injected sink, and
/// the UIKit call is the thin shell around it. The tests exercise the decisions; the shell is
/// verified on device.

// MARK: - Keep the screen awake

/// The screen must not dim while a session is live: both speakers are looking at the same phone,
/// and a turn can be seconds of silence while someone thinks. Every other state is either a setup
/// screen or a wait with nothing to read, so the normal idle timer applies.
extension SessionState {
  /// The model is loaded and the conversation screen is in use, so the A/B controls and
  /// `End Session` belong on screen and the display should stay lit.
  var isSessionLive: Bool {
    switch self {
    case .ready, .listening, .finalizing, .translating, .error: true
    default: false
    }
  }
}

enum ScreenAwakePolicy {
  /// A backgrounded scene never holds the idle timer, whatever the session state is: the screen
  /// the user is actually looking at belongs to some other app by then.
  static func shouldKeepAwake(state: SessionState, isForeground: Bool) -> Bool {
    isForeground && state.isSessionLive
  }
}

/// Anything that can hold the display awake. `UIApplication` in the app, a spy in tests.
protocol IdleTimerControlling {
  func setIdleTimerDisabled(_ disabled: Bool)
}

struct SystemIdleTimer: IdleTimerControlling {
  func setIdleTimerDisabled(_ disabled: Bool) { UIApplication.shared.isIdleTimerDisabled = disabled }
}

/// Applies `ScreenAwakePolicy` to the idle timer, and remembers what it applied so a screen that
/// re-renders on every partial transcript does not write the same value hundreds of times.
@MainActor
final class ScreenAwakeController {
  private(set) var isKeepingAwake = false
  private let idleTimer: any IdleTimerControlling

  init(idleTimer: any IdleTimerControlling = SystemIdleTimer()) {
    self.idleTimer = idleTimer
  }

  func update(state: SessionState, isForeground: Bool) {
    apply(ScreenAwakePolicy.shouldKeepAwake(state: state, isForeground: isForeground))
  }

  /// Hands the idle timer back unconditionally, for the moment the screen goes away.
  func release() { apply(false) }

  private func apply(_ keepAwake: Bool) {
    guard keepAwake != isKeepingAwake else { return }
    isKeepingAwake = keepAwake
    idleTimer.setIdleTimerDisabled(keepAwake)
  }
}

// MARK: - Haptics

/// What happened, not what it feels like. The session emits these; the mapping to a physical
/// sensation is a separate, testable table.
enum HapticEvent: Equatable {
  /// A push-to-talk control was pressed and recording started.
  case turnBegan
  /// A push-to-talk control was released and the utterance is finalizing.
  case turnEnded
  /// A finalized transcript came back as a translation.
  case translationDelivered
  /// A session error banner appeared.
  case sessionError
}

/// How an event feels. Deliberately quiet: one medium tap to say recording started, lighter taps
/// for the two things that end on their own, and the standard error notification for the one
/// failure that takes over the screen. A failed translation stays silent, because the bubble
/// already says so and the session carries on.
enum HapticFeedback: Equatable {
  case impact(UIImpactFeedbackGenerator.FeedbackStyle)
  case notification(UINotificationFeedbackGenerator.FeedbackType)
}

extension HapticEvent {
  var feedback: HapticFeedback {
    switch self {
    case .turnBegan: .impact(.medium)
    case .turnEnded: .impact(.light)
    case .translationDelivered: .impact(.soft)
    case .sessionError: .notification(.error)
    }
  }
}

/// Anything that can play a comfort haptic. The Taptic Engine in the app, a spy in tests.
@MainActor
protocol HapticSink {
  func play(_ event: HapticEvent)
}

@MainActor
struct SystemHaptics: HapticSink {
  func play(_ event: HapticEvent) {
    switch event.feedback {
    case let .impact(style):
      let generator = UIImpactFeedbackGenerator(style: style)
      generator.prepare()
      generator.impactOccurred()
    case let .notification(type):
      let generator = UINotificationFeedbackGenerator()
      generator.prepare()
      generator.notificationOccurred(type)
    }
  }
}

// MARK: - Copy confirmation

/// Bottom-of-screen confirmation state: the message, its self-dismissal, and the matching
/// accessibility announcement. Extracted from the settings drawer so the drawer's copy row and a
/// copied chat bubble share one toast behaviour instead of growing a second one.
@MainActor
final class ToastCenter: ObservableObject {
  @Published private(set) var message: String?

  private let duration: TimeInterval
  private let announce: (String) -> Void
  private var dismissal: Task<Void, Never>?

  init(duration: TimeInterval = ToastCenter.defaultDuration,
       announce: @escaping (String) -> Void = {
         UIAccessibility.post(notification: .announcement, argument: $0)
       }) {
    self.duration = duration
    self.announce = announce
  }

  /// UI tests race the 2 second fade under full-suite load; `-toastSeconds N` stretches it the
  /// same way `-uiState` forces screens. Production launches never pass it. Nonisolated so it can
  /// serve as a default argument evaluated off the main actor.
  nonisolated static var defaultDuration: TimeInterval {
    let arguments = ProcessInfo.processInfo.arguments
    guard let index = arguments.firstIndex(of: "-toastSeconds"),
          let value = arguments.dropFirst(index + 1).first.flatMap(TimeInterval.init) else { return 2 }
    return value
  }

  /// Shows a message and starts its fade. A second message replaces the first and restarts the
  /// clock, so repeated copies never leave a toast stranded on screen.
  func show(_ message: String) {
    dismissal?.cancel()
    self.message = message
    announce(message)
    let duration = duration
    dismissal = Task { [weak self] in
      try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
      guard !Task.isCancelled else { return }
      self?.message = nil
    }
  }
}

extension ConversationItem {
  /// What a copy takes from this bubble: the translation once there is one, and the source
  /// transcript until then. A bubble still waiting for its first words has nothing to copy.
  ///
  /// A provisional (live) translation counts as "there is one", which is the one judgement call in
  /// the live-translation work. Copy takes what the bubble is showing, and a bubble showing a
  /// translation that hands back only the source transcript is the surprising answer, not the safe
  /// one. What the clipboard loses is the styling that marked the text as provisional, which is
  /// acceptable for two reasons: a copy is a snapshot of a moving screen either way, and the final
  /// replaces the provisional a second or two later, so a second copy gets the settled wording. The
  /// final still wins here as everywhere: a `translated` bubble copies its final translation, and a
  /// failed one copies its transcript rather than a provisional the failure has already withdrawn.
  var copyableText: String? {
    let text: String
    switch state {
    case .translated: text = translation ?? transcript
    case .partial, .finalizing: text = provisionalTranslation ?? transcript
    case .translationFailed: text = transcript
    }
    return text.isEmpty ? nil : text
  }
}

/// Copying a chat bubble: what the bubble yields, the clipboard write, and the confirmation.
/// Kept out of the view so the copy is exercised without driving a long press.
@MainActor
final class ConversationCopyModel: ObservableObject {
  static var confirmation: String {
    String(localized: "Copied", comment: "Toast after a chat bubble is copied to the clipboard")
  }
  static var action: String {
    String(localized: "Copy", comment: "Long press menu action on a chat bubble")
  }

  let toasts: ToastCenter

  private let pasteboard: any SettingsPasteboard

  /// `toasts` is optional rather than defaulted, because a default argument is evaluated outside
  /// the actor and `ToastCenter` is main-actor isolated.
  init(pasteboard: any SettingsPasteboard = SystemPasteboard(), toasts: ToastCenter? = nil) {
    self.pasteboard = pasteboard
    self.toasts = toasts ?? ToastCenter()
  }

  func copy(_ item: ConversationItem) {
    guard let text = item.copyableText else { return }
    pasteboard.write(text)
    toasts.show(Self.confirmation)
  }
}
