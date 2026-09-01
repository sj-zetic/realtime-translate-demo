import SwiftUI

/// Typing a turn instead of speaking it.
///
/// A loud room, a quiet room, a word the recognizer keeps mishearing, a speaker who would rather
/// not talk at a stranger's phone: all of them need the same turn, produced by hand. So the typed
/// text is not a second kind of message. It is a finalized transcript, handed to the exact path a
/// released push-to-talk hands one to, and everything downstream (the counterpart's reading
/// language, the Hy-MT2 request, the bubble, the spoken translation) is unchanged.

// MARK: - Copy

enum TypedInputCopy {
  static let action = "Type a message"
  static let hint = "Opens a box to type a turn instead of speaking it."
  static let blockedHint = "Typing unlocks once the translation model is ready."
  static let send = "Send"
  static let cancel = "Cancel"
  static let speakerPickerLabel = "Who is speaking"
  static let fieldLabel = "Message"

  /// Names both ends of the turn about to be sent, because the sheet covers the language bar.
  static func guidance(speaker: Speaker, typing: TargetLanguage, translatedTo: TargetLanguage)
    -> String {
    "Speaker \(speaker.rawValue) types in \(typing.name). "
      + "It is translated into \(translatedTo.name) for \(speaker.counterpart.rawValue)."
  }

  static func placeholder(for language: TargetLanguage) -> String { "Type in \(language.name)" }
}

// MARK: - State

/// What the typed-input sheet is holding right now: whether it is up, whose turn is being typed,
/// and the draft. Kept out of the view so the send gate is exercised without a keyboard.
@MainActor
final class TypedInputModel: ObservableObject {
  @Published var isPresented = false
  /// The last speaker typed for, remembered across openings: someone typing because their own
  /// speech is not being recognized will type again before the other person does.
  @Published var speaker: Speaker = .a
  @Published var text = ""

  var trimmedText: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }

  /// A draft of nothing but whitespace is not a turn.
  var hasDraft: Bool { !trimmedText.isEmpty }

  func open() {
    text = ""
    isPresented = true
  }

  func close() {
    isPresented = false
    text = ""
  }
}

// MARK: - The sheet

/// One shared affordance rather than a keyboard button beside each push-to-talk control: the
/// bottom bar's contract is the A and B controls, the hint, and the session action, and a fifth
/// and sixth button down there would crowd all three. The A/B choice moves into the sheet, where
/// there is room to name both languages instead of implying them.
struct TypedInputSheet: View {
  @ObservedObject var model: TypedInputModel
  let readingA: TargetLanguage
  let readingB: TargetLanguage
  /// Mirrors the push-to-talk gate: another utterance in flight blocks a typed one too.
  let canSend: Bool
  let send: (String, Speaker) -> Void

  @FocusState private var isFieldFocused: Bool

  private var typingLanguage: TargetLanguage { model.speaker == .a ? readingA : readingB }
  private var counterpartLanguage: TargetLanguage { model.speaker == .a ? readingB : readingA }
  private var isSendEnabled: Bool { canSend && model.hasDraft }

  var body: some View {
    NavigationStack {
      VStack(alignment: .leading, spacing: 16) {
        Picker(TypedInputCopy.speakerPickerLabel, selection: $model.speaker) {
          ForEach(Speaker.allCases) { speaker in
            Text("Speaker \(speaker.rawValue)").tag(speaker)
          }
        }
        .pickerStyle(.segmented)
        .accessibilityIdentifier("typed-input-speaker")
        .accessibilityLabel(TypedInputCopy.speakerPickerLabel)

        Text(
          TypedInputCopy.guidance(speaker: model.speaker, typing: typingLanguage,
                                  translatedTo: counterpartLanguage)
        )
        .font(.caption)
        .foregroundStyle(DesignToken.textSecondary)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityIdentifier("typed-input-guidance")

        TextField(TypedInputCopy.placeholder(for: typingLanguage), text: $model.text,
                  axis: .vertical)
          .lineLimit(3 ... 6)
          .font(.body)
          .foregroundStyle(DesignToken.textPrimary)
          .textInputAutocapitalization(.sentences)
          .padding(12)
          .background(DesignToken.surfaceSubtle)
          .clipShape(RoundedRectangle(cornerRadius: Layout.message))
          .focused($isFieldFocused)
          .accessibilityIdentifier("typed-input-field")
          .accessibilityLabel(TypedInputCopy.fieldLabel)
          .accessibilityHint(TypedInputCopy.placeholder(for: typingLanguage))

        if !canSend {
          Text(TypedInputCopy.blockedHint)
            .font(.caption)
            .foregroundStyle(DesignToken.textSecondary)
            .accessibilityIdentifier("typed-input-blocked")
        }
        Spacer(minLength: 0)
      }
      .padding(16)
      .background(DesignToken.surface)
      .navigationTitle(TypedInputCopy.action)
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button(TypedInputCopy.cancel, action: model.close)
            .accessibilityIdentifier("typed-input-cancel")
            .accessibilityLabel(TypedInputCopy.cancel)
        }
        ToolbarItem(placement: .confirmationAction) {
          Button(TypedInputCopy.send, action: submit)
            .disabled(!isSendEnabled)
            .accessibilityIdentifier("typed-input-send")
            .accessibilityLabel(TypedInputCopy.send)
        }
      }
      // The field is what the sheet is for, so it takes focus rather than waiting for a tap.
      .onAppear { isFieldFocused = true }
    }
    .tint(DesignToken.accent)
  }

  private func submit() {
    guard isSendEnabled else { return }
    send(model.trimmedText, model.speaker)
    model.close()
  }
}

/// The bottom bar's one typed-input control. It rides the hint row, whose trailing half is empty,
/// the same way the sound toggle rides the status strip: the row is already there, so the app
/// gains an affordance without gaining a row of chrome.
struct TypedInputButton: View {
  let isEnabled: Bool
  let open: () -> Void

  var body: some View {
    Button(action: open) {
      Image(systemName: "keyboard")
        .font(.system(size: 13, weight: .medium))
        .foregroundStyle(isEnabled ? DesignToken.textPrimary : DesignToken.textSecondary)
        .frame(width: 36, height: 28)
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .disabled(!isEnabled)
    .accessibilityIdentifier("typed-input")
    .accessibilityLabel(TypedInputCopy.action)
    .accessibilityHint(isEnabled ? TypedInputCopy.hint : TypedInputCopy.blockedHint)
  }
}
