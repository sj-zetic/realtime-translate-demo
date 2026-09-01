import SwiftUI

/// The three first-run surfaces: the one-time welcome, the permission priming that precedes the
/// system prompts, and the model-download consent card.
///
/// All three stay inside the existing minimal chrome: `color.surface` fill, near-black text,
/// gray supporting text, hairline dividers, and exactly one accent-filled primary action per
/// surface. The welcome and the priming are full-surface and modal to VoiceOver, because nothing
/// behind them is actionable yet; the consent card sits over the main screen on the same scrim the
/// settings drawer uses, because it interrupts one tap rather than the whole app.

// MARK: - Welcome

struct WelcomeView: View {
  let start: () -> Void

  var body: some View {
    FirstRunSurface {
      VStack(alignment: .leading, spacing: 16) {
        Image("ZeticLogo")
          .resizable()
          .scaledToFit()
          .frame(height: 16)
          .accessibilityHidden(true)
        Text(FirstRunCopy.welcomeTitle)
          .font(.largeTitle)
          .fontWeight(.semibold)
          .foregroundStyle(DesignToken.textPrimary)
          .fixedSize(horizontal: false, vertical: true)
        Text(FirstRunCopy.welcomeTagline)
          .font(.title3)
          .foregroundStyle(DesignToken.textPrimary)
          .fixedSize(horizontal: false, vertical: true)
        ThinDivider()
        Text(FirstRunCopy.welcomePrivacy)
          .font(.subheadline)
          .foregroundStyle(DesignToken.textSecondary)
          .fixedSize(horizontal: false, vertical: true)
      }
    } actions: {
      FirstRunPrimaryButton(
        title: FirstRunCopy.welcomeAction,
        identifier: "welcome-get-started",
        action: start
      )
    }
  }
}

// MARK: - Permission priming

/// Explains what the two system prompts are for before either one fires, so the OS alert is never
/// the first mention of the microphone. `allow` triggers the real prompts.
struct PermissionPrimingView: View {
  let allow: () -> Void
  let skip: () -> Void

  var body: some View {
    FirstRunSurface {
      VStack(alignment: .leading, spacing: 16) {
        Text(FirstRunCopy.primingTitle)
          .font(.title2)
          .fontWeight(.semibold)
          .foregroundStyle(DesignToken.textPrimary)
          .fixedSize(horizontal: false, vertical: true)
        VStack(alignment: .leading, spacing: 12) {
          Text(FirstRunCopy.primingMicrophone)
          ThinDivider()
          Text(FirstRunCopy.primingSpeech)
        }
        .font(.subheadline)
        .foregroundStyle(DesignToken.textPrimary)
        .fixedSize(horizontal: false, vertical: true)
        ThinDivider()
        Text(FirstRunCopy.primingPrivacy)
          .font(.subheadline)
          .foregroundStyle(DesignToken.textSecondary)
          .fixedSize(horizontal: false, vertical: true)
        Text(FirstRunCopy.primingNext)
          .font(.caption)
          .foregroundStyle(DesignToken.textSecondary)
          .fixedSize(horizontal: false, vertical: true)
      }
    } actions: {
      VStack(spacing: 8) {
        FirstRunPrimaryButton(
          title: FirstRunCopy.primingAction,
          identifier: "priming-continue",
          action: allow
        )
        FirstRunSecondaryButton(
          title: FirstRunCopy.primingDecline,
          identifier: "priming-not-now",
          action: skip
        )
      }
    }
  }
}

// MARK: - Model download consent

/// The consent step for the one large transfer the app ever makes. Shown only when no complete
/// local model exists, so a returning user goes straight into a local load.
struct ModelConsentOverlay: View {
  let prompt: FirstRunModel.ConsentPrompt?
  let download: () -> Void
  let dismiss: () -> Void

  var body: some View {
    ZStack {
      if let prompt {
        Color.black.opacity(0.16)
          .ignoresSafeArea()
          .transition(.opacity)
          .contentShape(Rectangle())
          .onTapGesture(perform: dismiss)
          .accessibilityIdentifier("consent-scrim")
          .accessibilityLabel("Dismiss the model download step")
          .accessibilityAddTraits(.isButton)
        card(cellularWarning: prompt.cellularWarning)
          .transition(.opacity)
      }
    }
    .animation(.easeOut(duration: 0.2), value: prompt)
  }

  private func card(cellularWarning: Bool) -> some View {
    VStack(alignment: .leading, spacing: 12) {
      // Same rule as the full-surface steps: the copy scrolls inside the card once it outgrows the
      // phone, so "Download now" and "Not now" are never pushed off the bottom edge.
      ViewThatFits(in: .vertical) {
        copy(cellularWarning: cellularWarning)
        ScrollView { copy(cellularWarning: cellularWarning) }
      }
      VStack(spacing: 8) {
        FirstRunPrimaryButton(
          title: FirstRunCopy.consentAction,
          identifier: "consent-download",
          action: download
        )
        FirstRunSecondaryButton(
          title: FirstRunCopy.consentDecline,
          identifier: "consent-not-now",
          action: dismiss
        )
      }
      .padding(.top, 4)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(20)
    .background(DesignToken.surface)
    .clipShape(RoundedRectangle(cornerRadius: Layout.message))
    .overlay(
      RoundedRectangle(cornerRadius: Layout.message).stroke(DesignToken.divider, lineWidth: 1)
    )
    .padding(20)
    .accessibilityAddTraits(.isModal)
  }

  private func copy(cellularWarning: Bool) -> some View {
    VStack(alignment: .leading, spacing: 12) {
      Text(FirstRunCopy.consentTitle)
        .font(.headline)
        .foregroundStyle(DesignToken.textPrimary)
        .fixedSize(horizontal: false, vertical: true)
      Text(FirstRunCopy.consentSize)
        .font(.subheadline)
        .foregroundStyle(DesignToken.textPrimary)
        .fixedSize(horizontal: false, vertical: true)
      Text(FirstRunCopy.consentOnce)
        .font(.subheadline)
        .foregroundStyle(DesignToken.textSecondary)
        .fixedSize(horizontal: false, vertical: true)
      if cellularWarning {
        ThinDivider()
        Text(FirstRunCopy.consentCellular)
          .font(.subheadline)
          .foregroundStyle(DesignToken.textPrimary)
          .fixedSize(horizontal: false, vertical: true)
          .accessibilityIdentifier("consent-cellular-warning")
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}

// MARK: - Shared chrome

/// One full-surface first-run layout: content leading-aligned in the middle, actions pinned at the
/// bottom. Modal to VoiceOver so the main screen behind it is not reachable by swipe.
///
/// The surface carries no identifier of its own on purpose: an identifier on a container this size
/// is inherited by every element inside it and would overwrite the buttons' own identifiers.
private struct FirstRunSurface<Content: View, Actions: View>: View {
  @ViewBuilder let content: () -> Content
  @ViewBuilder let actions: () -> Actions

  var body: some View {
    VStack(alignment: .leading, spacing: 24) {
      // Centered while the copy fits, scrolling once it does not. At the accessibility text sizes
      // this copy is taller than the phone, and without the second layout the column overflows in
      // both directions at once: the title rides up over the status bar and the last action falls
      // off the bottom edge.
      ViewThatFits(in: .vertical) {
        centered
        ScrollView { content().frame(maxWidth: .infinity, alignment: .leading) }
      }
      actions()
    }
    .padding(24)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    .background(DesignToken.surface.ignoresSafeArea())
    .accessibilityAddTraits(.isModal)
  }

  private var centered: some View {
    VStack(alignment: .leading, spacing: 24) {
      Spacer(minLength: 0)
      content()
        .frame(maxWidth: .infinity, alignment: .leading)
      Spacer(minLength: 0)
    }
  }
}

/// The accent-filled action. One per surface, matching the `Start Session` treatment on the main
/// screen so the brand accent keeps meaning "this is the way forward".
private struct FirstRunPrimaryButton: View {
  let title: String
  let identifier: String
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      Text(title)
        .font(.subheadline).fontWeight(.semibold)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
    }
    .buttonStyle(.plain)
    .foregroundStyle(DesignToken.surface)
    .background(DesignToken.accent)
    .clipShape(RoundedRectangle(cornerRadius: Layout.control))
    .accessibilityIdentifier(identifier)
    .accessibilityLabel(title)
  }
}

/// The quiet alternative, in the same outline treatment the banner buttons use.
private struct FirstRunSecondaryButton: View {
  let title: String
  let identifier: String
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      Text(title)
        .font(.subheadline).fontWeight(.semibold)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
    }
    .buttonStyle(.plain)
    .foregroundStyle(DesignToken.textPrimary)
    .background(DesignToken.surface)
    .clipShape(RoundedRectangle(cornerRadius: Layout.control))
    .overlay(
      RoundedRectangle(cornerRadius: Layout.control).stroke(DesignToken.divider, lineWidth: 1)
    )
    .accessibilityIdentifier(identifier)
    .accessibilityLabel(title)
  }
}
