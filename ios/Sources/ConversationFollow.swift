import CoreGraphics
import Foundation

/// Following the conversation: whether the transcript keeps its own bottom pinned as new words
/// arrive, or holds still because somebody is reading back through what was already said.
///
/// The specification has promised since the first draft that "the newest bubble is scrolled into
/// view", and until now that was true only when the number of bubbles changed. A turn's transcript
/// growing word by word, the grey provisional translation growing under it, and the final landing
/// all made the bubble taller without adding one, so a long turn grew off the bottom of the screen
/// and the reader had to chase it by hand.
///
/// Pinning on every content change is the fix and also the new hazard: a transcript that yanks
/// itself to the bottom while somebody is three turns back reading a translation is worse than one
/// that never moves. So there are two modes and one rule for moving between them, and, in the style
/// of `SessionComfort.swift`, the rule is a value rather than a pile of view state. Everything here
/// is a pure decision over numbers a `GeometryReader` reports; the scrolling itself is four lines in
/// `ConversationList`.

// MARK: - Follow mode and reading mode

/// The transcript's two modes, and the unseen-content flag that decides whether the jump control
/// has anything to offer.
///
/// One value, mutated by three events: the scroll offset probe says where the reader is, the item
/// list says something changed, and `snapToLatest` says a "now" moment happened. Each mutation
/// answers with the one effect the view can perform, so the view never decides anything itself.
struct ConversationFollow: Equatable {
  /// What the view should do about a change. Returned rather than a `Bool` so a decision that
  /// deliberately does nothing is as readable as one that scrolls.
  enum Effect: Equatable {
    case none
    case scrollToLatest
  }

  /// How far from the bottom still counts as "at the bottom", in points.
  ///
  /// Roughly one bubble: a two line bubble at the default text size measures about 110 points, plus
  /// the 12 point gap between bubbles. The number is a tolerance rather than a boundary anybody
  /// aims at. Too small and a reader who nudged the transcript a few points, or a bounce that has
  /// not quite settled, drops out of follow mode and the conversation stops moving for no reason
  /// they can see. Too large and someone who has genuinely scrolled up to re-read the previous turn
  /// gets yanked back down mid-sentence, which is the one thing this whole type exists to prevent.
  static let nearBottomThreshold: CGFloat = 120

  /// Whether the bottom is pinned. True at the start, because a conversation that has not been
  /// scrolled is a conversation somebody is watching happen.
  private(set) var isFollowing = true
  /// Whether something arrived below the fold since the reader scrolled up. Only ever true in
  /// reading mode: content that arrives while the bottom is pinned has already been shown.
  private(set) var hasUnseenContent = false

  init() {}

  /// Whether the floating jump control belongs on screen. Both halves matter: it is not a permanent
  /// piece of furniture (that is what the scroll bar is for), and it never appears over a transcript
  /// that has nothing new to jump to.
  var showsJumpControl: Bool { !isFollowing && hasUnseenContent }

  /// The offset probe's report: how far the bottom of the content sits below the bottom of the
  /// viewport. Zero or less means the last bubble is fully on screen, and a bounce past the end
  /// makes it negative.
  ///
  /// This is the only way back into follow mode besides an explicit jump: scrolling to the bottom by
  /// hand re-arms the pinning, which is what every messaging app on the phone does and therefore the
  /// behaviour nobody has to be taught.
  mutating func observe(distanceFromBottom: CGFloat) {
    guard distanceFromBottom > Self.nearBottomThreshold else {
      isFollowing = true
      hasUnseenContent = false
      return
    }
    isFollowing = false
  }

  /// Something in the transcript changed: a bubble appeared, a partial transcript grew, the
  /// provisional translation was refreshed, or the final landed. All four are the same event here,
  /// which is the whole point: the old implementation could only see the first of them.
  ///
  /// - Parameters:
  ///   - isEmpty: whether anything is left to scroll to. An emptied transcript has no bottom worth
  ///     moving to, and the next turn must start pinned, so this resets the whole value.
  ///   - isVoiceOverRunning: see the note on the return value below.
  ///
  /// **The VoiceOver call.** When VoiceOver is running, a content change scrolls nothing. Moving a
  /// scroll view under a reader who is part way through a sentence is how an automatic scroll turns
  /// into a lost place: VoiceOver's focus stays on the element it was reading, the screen slides out
  /// from under it, and the next swipe lands somewhere unexpected. Nothing is lost by holding still,
  /// because VoiceOver scrolls the transcript itself as focus advances through the bubbles, and a
  /// new bubble is appended immediately after the one being read. The jump control is unaffected: it
  /// is a labelled button somebody chose to press, and so are the "now" moments below.
  mutating func contentChanged(isEmpty: Bool, isVoiceOverRunning: Bool) -> Effect {
    guard !isEmpty else {
      self = ConversationFollow()
      return .none
    }
    guard isFollowing else {
      hasUnseenContent = true
      return .none
    }
    return isVoiceOverRunning ? .none : .scrollToLatest
  }

  /// A moment that is always "now": the jump control was pressed, a turn began, a session started,
  /// or the transcript was emptied. The bottom is where the conversation is, so the transcript goes
  /// there and stays there.
  mutating func snapToLatest() -> Effect {
    isFollowing = true
    hasUnseenContent = false
    return .scrollToLatest
  }
}

// MARK: - The session transitions that are always "now"

/// Which session-state transitions drag the transcript back to the bottom regardless of where the
/// reader had scrolled to.
///
/// Keyed on the transition rather than on the state, because the states these moments land in are
/// not moments at all on their own. `ready` is where a session arrives after it loads *and* where
/// every finished turn returns to, so snapping on `ready` alone would haul a reader back down every
/// time a translation landed, which is precisely the behaviour reading mode exists to stop.
enum ConversationSnapMoment {
  static func shouldSnap(from previous: SessionState, to next: SessionState) -> Bool {
    guard previous != next else { return false }
    switch (previous, next) {
    // A turn is beginning. Whoever pressed the control is about to produce the newest bubble, and
    // they pressed it deliberately, so this is the clearest "now" the app has.
    case (_, .listening):
      return true
    // A session has just finished loading its model. The conversation starts here.
    case (.loadingModel, .ready):
      return true
    // A session ended, which empties the transcript. Nothing to look at but the bottom.
    case (_, .setup):
      return true
    default:
      return false
    }
  }
}

// MARK: - Copy

enum ConversationFollowCopy {
  /// The floating control's only words. It carries a chevron rather than a label on screen, so this
  /// string exists for VoiceOver and for the accessibility rotor, where it is the whole control.
  static var jumpToLatest: String {
    String(localized: "Jump to latest",
           comment: "Accessibility label for the control that scrolls the conversation to the newest bubble")
  }

  static var jumpToLatestHint: String {
    String(localized: "Scrolls to the newest bubble and follows the conversation again.",
           comment: "Accessibility hint for the control that scrolls the conversation to the newest bubble")
  }
}
