import Foundation

/// Live (streaming) translation: the two decisions that make a translation appear while somebody is
/// still talking, without either spamming a 1.8B model or letting a late answer overwrite a good one.
///
/// Both are pure values, for the same reason everything else in this app that cannot be asserted by
/// talking at a phone is pure: the scheduling is a struct with an injected clock, the staleness rule
/// is a static function over a snapshot, and the view model owns nothing but the wiring. The model
/// call itself is the existing pipeline, untouched: `HyMT2Request` plus `translationRuntime.translate`,
/// the same prompt a finished turn sends.

// MARK: - When a partial pass may start

/// The throttle in front of the partial passes.
///
/// A partial pass is a whole Hy-MT2 generation over everything said so far, so the transcript
/// growing by one word is not a reason to run another one. Three gates, all of which have to open:
///
/// 1. **One at a time.** There is never more than one partial pass in flight. The runtime serializes
///    on its own queue anyway, so a second pass would only queue behind the first and land even
///    further out of date.
/// 2. **Something changed.** A pass only starts when the accumulated transcript differs from the one
///    the last pass started with. A recognizer that re-emits the same hypothesis buys nothing.
/// 3. **A minimum gap.** Even when the first two open, two passes never start closer together than
///    `minimumGap`.
///
/// Nothing here runs on a timer. A pass is attempted when a partial arrives and again when a pass
/// finishes, which is what makes the whole thing a value with a clock argument rather than a second
/// piece of concurrency to reason about. The consequence is that a speaker who stops talking without
/// releasing the control can leave the last few words untranslated until the release; the final pass
/// covers them, and it covers them with the whole utterance rather than a suffix of it.
struct LivePartialTranslationScheduler: Equatable {
  /// The floor between the starts of two partial passes, in seconds.
  ///
  /// 0.7 seconds sits inside the 0.5 to 1.0 window the behavior was specified with. Below it, the
  /// word-by-word churn of a live recognizer turns into a queue of near-identical generations on a
  /// 1.8B model that is also the thing the final translation has to wait for; above it, the
  /// provisional text visibly stops keeping up with the speaker. In practice a pass on device takes
  /// longer than this, so gate 1 is usually the binding one and this is the backstop for the short
  /// utterances where it is not.
  static let minimumGap: TimeInterval = 0.7

  /// Why a partial pass did or did not start. Returned rather than a `Bool` so the reason is
  /// assertable: the three refusals are three different behaviors that would otherwise be one.
  enum Decision: Equatable {
    case start
    case skipEmpty
    case skipInFlight
    case skipUnchanged
    case skipTooSoon
  }

  private(set) var isPassInFlight = false
  /// The transcript the most recent pass was started with, which is what "changed" is measured
  /// against. Deliberately not the most recent transcript seen: a pass that is still running was
  /// started from this text, so this is the text whose translation is already on its way.
  private(set) var lastStartedText: String?
  private(set) var lastStartedAt: TimeInterval?

  init() {}

  /// Opens the three gates, and records the pass when they all open.
  mutating func begin(text: String, now: TimeInterval) -> Decision {
    guard !text.isEmpty else { return .skipEmpty }
    guard !isPassInFlight else { return .skipInFlight }
    guard text != lastStartedText else { return .skipUnchanged }
    if let lastStartedAt, now - lastStartedAt < Self.minimumGap { return .skipTooSoon }
    isPassInFlight = true
    lastStartedText = text
    lastStartedAt = now
    return .start
  }

  /// The pass in flight is over, however it ended. A pass that failed frees the slot exactly like a
  /// pass that succeeded: a partial translation that did not come back is not worth a retry, because
  /// the next partial is a fraction of a second away and the final is the one that has to land.
  mutating func finishPass() { isPassInFlight = false }

  /// Forgets everything, for the moments a turn stops existing: a new turn, an abandoned one, a
  /// cleared conversation, an ended session. The next turn's first partial must not be refused for
  /// being too close to the previous turn's last one, or for saying the same words.
  mutating func reset() { self = LivePartialTranslationScheduler() }
}

// MARK: - One partial pass, tagged

/// A partial pass, carrying enough to recognize its own answer as stale when it comes back.
///
/// `revision` is a session-wide counter rather than a per-item one, so "newer" is a single
/// comparison across the whole conversation and a pass from a previous turn can never look newer
/// than one from this turn.
struct PartialTranslationPass: Equatable {
  let itemID: UUID
  let revision: Int
  let text: String
}

// MARK: - Whether a completed pass may be shown

/// The stale-guard: everything that can happen to a bubble between a partial pass starting and its
/// answer arriving, and the single rule for whether that answer still means anything.
///
/// A partial pass is not cancelled when the world moves on. The runtime has one queue and no
/// cancellation, and adding one for this would put a cancel in the path of the final translation,
/// which is the one that must not be disturbed. So late answers are allowed to arrive and are
/// dropped here instead, which makes the whole race a pure function rather than a timing question.
enum LivePartialTranslationGuard {
  /// Whether `pass`'s answer may be written into the bubble it was started for.
  ///
  /// - `item` is that bubble as it stands now, or nil if it is gone.
  /// - `liveItemID` is the bubble partial results may still apply to: set when a turn begins, kept
  ///   through the release and the final translation, and cleared when the final lands or the turn
  ///   is abandoned. A pass whose item is no longer the live one belongs to a turn that has ended,
  ///   which covers both the abandoned turn and the next turn's bubble.
  /// - `appliedRevision` is the newest revision already on screen, so an answer that was overtaken
  ///   while it was in flight cannot un-do the newer one.
  ///
  /// The final always wins: once the bubble is `translated` or `translationFailed` its translation
  /// region belongs to the final answer or to the retry control, and no partial may touch it again.
  static func shouldApply(pass: PartialTranslationPass, liveItemID: UUID?,
                          item: ConversationItem?, appliedRevision: Int) -> Bool {
    guard let item, item.id == pass.itemID else { return false }
    guard liveItemID == pass.itemID else { return false }
    guard pass.revision > appliedRevision else { return false }
    switch item.state {
    case .partial, .finalizing: return true
    case .translated, .translationFailed: return false
    }
  }
}
