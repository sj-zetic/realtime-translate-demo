import Foundation

/// One push-to-talk utterance, assembled from however many recognition segments the platform
/// chooses to break it into.
///
/// An on-device `SFSpeechRecognizer` decides for itself where an utterance ends, and it decides
/// that a pause mid-sentence is the end of one: it delivers a final result and, from then on, its
/// hypotheses describe only the audio that came after the silence. A view that shows each partial
/// in place therefore watches the first half of a sentence disappear the moment its speaker takes
/// a breath. The button, not the recognizer, owns where an utterance ends, so the segments are
/// banked here and joined at the release.
///
/// Everything about it is a pure value: the AVFoundation shell decides *when* a segment ends, this
/// decides what the words are.
struct UtteranceAccumulator: Equatable {
  /// The segments already finished with, in the order they were spoken.
  private(set) var committedSegments: [String] = []
  /// The segment being recognized right now, as of its most recent partial.
  private(set) var liveSegment: String = ""

  init() {}

  /// Everything said so far: the banked segments and the live one, single-space joined. This is
  /// what the bubble shows while the control is held.
  var text: String { Self.join(committedSegments + [liveSegment]) }

  var isEmpty: Bool { text.isEmpty }

  /// A partial hypothesis for the segment in flight. Returns the text to show.
  ///
  /// An empty partial is ignored rather than applied: it is not the recognizer saying the words
  /// are gone, and treating it as one would blank the bubble for exactly the reason this type
  /// exists.
  @discardableResult
  mutating func receivePartial(_ transcript: String) -> String {
    let next = Self.normalized(transcript)
    guard !next.isEmpty else { return text }
    if Self.isHypothesisReset(previous: liveSegment, next: next) { commit(liveSegment) }
    liveSegment = next
    return text
  }

  /// The recognizer's last word on the segment in flight, arriving while the caller still holds
  /// the control. The segment is banked and the next partial starts a new one. Returns the text to
  /// show, which is every word so far rather than only this segment's.
  ///
  /// An empty or whitespace-only final leaves that segment's last partial standing, because a
  /// recognizer that said something and then said nothing has already said what was said.
  @discardableResult
  mutating func commitSegment(_ transcript: String = "") -> String {
    let candidate = Self.normalized(transcript)
    commit(candidate.isEmpty ? liveSegment : candidate)
    liveSegment = ""
    return text
  }

  /// The whole utterance, for the one `onFinal` a turn is allowed. `transcript` is the in-flight
  /// segment's own final when one arrived; an empty or missing one leaves that segment's last
  /// partial standing, on the same reasoning as `commitSegment`.
  func concluded(with transcript: String? = nil) -> String {
    let last = Self.normalized(transcript ?? "")
    return Self.join(committedSegments + [last.isEmpty ? liveSegment : last])
  }

  private mutating func commit(_ segment: String) {
    let value = Self.normalized(segment)
    guard !value.isEmpty else { return }
    committedSegments.append(value)
  }

  /// Whether a partial is a fresh hypothesis about new audio rather than a refinement of the one
  /// before it: the secondary half of the pause fix, for a recognizer that resets its hypothesis
  /// without ever declaring a final.
  ///
  /// Deliberately hard to satisfy. A false positive banks a partial that the next hypothesis is
  /// about to restate, which duplicates words in the finished transcript, and duplicated words are
  /// worse to read than the rare reset this misses. So all of it has to hold: there were at least
  /// three words to lose, the new hypothesis is at most half as long, it is neither an extension
  /// nor a tail of the old one, and it does not even begin with the same word. A recognizer
  /// rewriting `I went to the store` as `I want to the store` is refining, not resetting, and
  /// keeps its segment.
  static func isHypothesisReset(previous: String, next: String) -> Bool {
    let previousWords = words(previous)
    let nextWords = words(next)
    guard previousWords.count >= 3, !nextWords.isEmpty else { return false }
    guard nextWords.count * 2 <= previousWords.count else { return false }
    let established = normalized(previous).lowercased()
    let candidate = normalized(next).lowercased()
    // An extension of what was already there is the ordinary case, and a tail of it is the
    // recognizer narrowing its own hypothesis. Neither one throws any words away.
    guard !candidate.hasPrefix(established), !established.hasSuffix(candidate) else { return false }
    guard let opening = previousWords.first, let restart = nextWords.first,
          opening.compare(restart, options: [.caseInsensitive, .diacriticInsensitive]) != .orderedSame
    else { return false }
    return true
  }

  private static func words(_ text: String) -> [String] {
    normalized(text).split(whereSeparator: \.isWhitespace).map(String.init)
  }

  private static func normalized(_ text: String) -> String {
    text.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  /// Single-space joined, with empty segments dropped rather than joined into double spaces.
  private static func join(_ segments: [String]) -> String {
    segments.map(normalized).filter { !$0.isEmpty }.joined(separator: " ")
  }
}
