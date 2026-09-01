import AVFAudio
import Foundation

/// Audio interruption recovery, and the decisions behind it.
///
/// A phone call, Siri, or an alarm takes the audio session away mid-sentence. The recognizer's
/// input node goes quiet, and whatever it had transcribed so far is gone: there is no way to
/// resume an utterance that lost its microphone halfway through. So the app does not pretend
/// otherwise. The utterance dies the same way a failed `beginTurn` dies, the session and the
/// loaded model stay exactly where they were, and one gentle line says what happened.
///
/// Nothing here can be asserted by placing a real phone call, so the same split the rest of the
/// app uses applies again: the decision is a pure function over the session state, and the
/// `NotificationCenter` plumbing is the thin shell around it. The tests exercise the decision.

// MARK: - Events

/// What the audio system reported, reduced to the three things this app responds to differently.
enum AudioInterruptionEvent: Equatable {
  /// Something else took the session: a call, Siri, an alarm.
  case began
  /// The interrupting thing finished. `shouldResume` is the system's hint that resuming audio
  /// would be appropriate; this app never acts on it, because push-to-talk is explicit.
  case ended(shouldResume: Bool)
  /// The route this app was recording or speaking on went away, typically headphones unplugged
  /// or a Bluetooth headset disconnecting. Indistinguishable from an interruption to a speaker
  /// mid-sentence, so it is treated as one.
  case routeLost

  /// Reads `AVAudioSession.interruptionNotification`'s payload. Anything unrecognised yields nil
  /// rather than a guess, so a future interruption type is ignored instead of ending a turn.
  static func fromInterruption(_ userInfo: [AnyHashable: Any]?) -> AudioInterruptionEvent? {
    guard let raw = userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
          let type = AVAudioSession.InterruptionType(rawValue: raw) else { return nil }
    switch type {
    case .began:
      return .began
    case .ended:
      let options = (userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt).map {
        AVAudioSession.InterruptionOptions(rawValue: $0)
      }
      return .ended(shouldResume: options?.contains(.shouldResume) == true)
    @unknown default:
      return nil
    }
  }

  /// Reads `AVAudioSession.routeChangeNotification`'s payload. Only the one reason that actually
  /// costs this app its input or output counts; a new device merely becoming available, or a
  /// category change this app made itself, is not an interruption.
  static func fromRouteChange(_ userInfo: [AnyHashable: Any]?) -> AudioInterruptionEvent? {
    guard let raw = userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
          let reason = AVAudioSession.RouteChangeReason(rawValue: raw),
          reason == .oldDeviceUnavailable else { return nil }
    return .routeLost
  }
}

// MARK: - The decision

/// What the session does about an interruption. Deliberately narrow: there is no "pause", because
/// there is nothing to resume, and no "restart", because starting to listen is always a deliberate
/// press of a push-to-talk control.
enum AudioInterruptionResponse: Equatable {
  /// Nothing was using audio, so nothing has to change.
  case ignore
  /// A translation was being read aloud and is cut short. The transcript is untouched: the bubble
  /// is still there, with its replay glyph, for whoever wants to hear it again.
  case stopSpeech
  /// The microphone was open. The in-flight bubble is discarded, the recognizer is released, and
  /// the session returns to idle with a note.
  case abandonUtterance
}

enum AudioInterruptionPolicy {
  /// The whole decision table. An interruption only ever costs the app what was using audio at
  /// that instant, and an interruption ending is never a reason to start using it again.
  static func response(to event: AudioInterruptionEvent, state: SessionState,
                       isSpeaking: Bool) -> AudioInterruptionResponse {
    switch event {
    // The system's `shouldResume` hint is read and then deliberately not acted on. Resuming would
    // mean opening the microphone on a phone that has just come off a call, with nobody holding a
    // button, which is the one thing a push-to-talk app must never do.
    case .ended:
      return .ignore
    case .began, .routeLost:
      // `translating` is not recognizer-live: the microphone was handed back before the request
      // went out, so a call arriving mid-translation costs the utterance nothing.
      if state.isRecognizerLive { return .abandonUtterance }
      return isSpeaking ? .stopSpeech : .ignore
    }
  }
}

// MARK: - Copy

enum AudioInterruptionCopy {
  /// The whole message. It says what happened and what to do, and nothing about why, because the
  /// reason is already on screen: a call, an alarm, or Siri took over the phone.
  static let notice = "Interrupted. Tap to talk again."
}

// MARK: - The observer

/// Anything that can report audio interruptions. `NotificationCenter` in the app, a stub in tests,
/// which is what keeps the decision table testable without a real phone call.
@MainActor
protocol AudioInterruptionObserving: AnyObject {
  /// Starts delivering events to `handler`, replacing any previous registration. Called once, by
  /// whoever owns the response.
  func observe(_ handler: @escaping (AudioInterruptionEvent) -> Void)
}

/// The live `AVAudioSession` notifications. Delivered on the main queue, because everything that
/// reacts to them is main-actor state.
@MainActor
final class SystemAudioInterruptions: AudioInterruptionObserving {
  private let center: NotificationCenter
  private var tokens: [NSObjectProtocol] = []

  init(center: NotificationCenter = .default) {
    self.center = center
  }

  func observe(_ handler: @escaping (AudioInterruptionEvent) -> Void) {
    removeObservers()
    let deliver = UncheckedBox(handler)
    tokens = [
      center.addObserver(forName: AVAudioSession.interruptionNotification, object: nil,
                         queue: .main) { notification in
        guard let event = AudioInterruptionEvent.fromInterruption(notification.userInfo) else { return }
        deliver.value(event)
      },
      center.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil,
                         queue: .main) { notification in
        guard let event = AudioInterruptionEvent.fromRouteChange(notification.userInfo) else { return }
        deliver.value(event)
      }
    ]
  }

  private func removeObservers() {
    for token in tokens { center.removeObserver(token) }
    tokens = []
  }

  deinit {
    for token in tokens { center.removeObserver(token) }
  }
}

/// Carries the main-actor handler into the notification block. The block is only ever run on the
/// main queue, which the registration above guarantees, so the hop is a formality the type system
/// cannot see on its own.
private final class UncheckedBox<Value>: @unchecked Sendable {
  let value: Value
  init(_ value: Value) { self.value = value }
}
