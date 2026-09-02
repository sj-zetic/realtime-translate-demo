import SwiftUI

/// The right-side settings drawer and its scrim, with the shared copy-confirmation toast layered
/// over it. Presented as a full-screen overlay above the main screen so the wordmark button stays
/// where it is.
struct SettingsDrawerOverlay: View {
  @ObservedObject var model: SettingsDrawerModel
  /// The one session action the drawer carries. Passed in rather than reached for, so the drawer
  /// still knows nothing about the view model behind it.
  let canClearConversation: Bool
  let clearConversation: () -> Void
  /// The model is in memory, so deleting it from disk is not something the drawer can offer yet.
  let isSessionLive: Bool

  var body: some View {
    ZStack(alignment: .trailing) {
      if model.isOpen {
        Scrim(close: model.close)
        SettingsDrawerPanel(model: model, canClearConversation: canClearConversation,
                            clearConversation: clearConversation, isSessionLive: isSessionLive)
          .transition(.move(edge: .trailing))
      }
    }
    .animation(.easeOut(duration: 0.22), value: model.isOpen)
    .overlay(alignment: .bottom) {
      ToastLayer(center: model.toasts, identifier: "settings-toast")
    }
  }
}

private struct Scrim: View {
  let close: () -> Void

  var body: some View {
    Color.black.opacity(0.16)
      .ignoresSafeArea()
      .transition(.opacity)
      .contentShape(Rectangle())
      .onTapGesture(perform: close)
      .accessibilityIdentifier("settings-scrim")
      .accessibilityLabel("Close settings")
      .accessibilityAddTraits(.isButton)
  }
}

private struct SettingsDrawerPanel: View {
  @ObservedObject var model: SettingsDrawerModel
  let canClearConversation: Bool
  let clearConversation: () -> Void
  let isSessionLive: Bool

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      header
      ThinDivider()
      // At the accessibility text sizes the rows and the About block are taller than the panel.
      // Without a scroller the whole column overflows and rides up over the status bar; with one
      // the header stays put and the last row is still reachable.
      ScrollView {
        VStack(alignment: .leading, spacing: 0) {
          rows
          ThinDivider()
          about
        }
      }
    }
    .frame(maxWidth: 280, maxHeight: .infinity, alignment: .top)
    .background(DesignToken.surface.ignoresSafeArea())
    .overlay(alignment: .leading) {
      Rectangle().fill(DesignToken.divider).frame(width: 1).ignoresSafeArea()
    }
    .gesture(
      DragGesture(minimumDistance: 20)
        .onEnded { value in
          if value.translation.width > 60 { model.close() }
        }
    )
  }

  private var header: some View {
    HStack(spacing: 8) {
      Text("Settings")
        .font(.headline)
        .foregroundStyle(DesignToken.textPrimary)
      Spacer(minLength: 8)
      Button(action: model.close) {
        Image(systemName: "xmark")
          .font(.system(size: 13, weight: .semibold))
          .foregroundStyle(DesignToken.textSecondary)
          .frame(width: 32, height: 32)
          .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .accessibilityIdentifier("settings-close")
      .accessibilityLabel("Close settings")
    }
    .padding(.leading, 16)
    .padding(.trailing, 8)
    .padding(.vertical, 10)
  }

  /// The drawer's row list. New settings rows, including the deferred app-language row, slot in
  /// here between the existing rows and keep the same divider rhythm.
  private var rows: some View {
    VStack(spacing: 0) {
      // First, because it is the one row someone opens the drawer in order to use. Disabled
      // rather than hidden on an empty transcript or mid-utterance, so the row never moves.
      SettingsRow(
        title: SettingsDrawerModel.clearConversationTitle,
        subtitle: SettingsDrawerModel.clearConversationSubtitle,
        symbol: "trash",
        identifier: "settings-clear-conversation",
        accessibilityLabel: canClearConversation
          ? "\(SettingsDrawerModel.clearConversationTitle), keeps the session and the languages"
          : "\(SettingsDrawerModel.clearConversationTitle), unavailable, there is nothing to clear",
        isEnabled: canClearConversation,
        action: { model.clearConversation(clearConversation) }
      )
      ThinDivider()
      storageRow
      ThinDivider()
      SettingsRow(
        title: "Visit zetic.ai",
        subtitle: nil,
        symbol: "arrow.up.right.square",
        identifier: "settings-visit-zetic",
        accessibilityLabel: "Visit zetic.ai, opens the website",
        action: model.openWebsite
      )
      ThinDivider()
      SettingsRow(
        title: "Contact us",
        subtitle: SettingsDrawerModel.contactEmail,
        symbol: "doc.on.doc",
        identifier: "settings-contact-us",
        accessibilityLabel: "Contact us, copies \(SettingsDrawerModel.contactEmail)",
        action: model.copyContactEmail
      )
    }
  }

  /// The model's footprint, and the app's only destructive action behind the app's only
  /// `confirmationDialog`. The row itself never deletes: it asks.
  private var storageRow: some View {
    let row = model.storageRow(isSessionLive: isSessionLive)
    return SettingsRow(
      title: ModelStorageCopy.title,
      subtitle: row.subtitle,
      symbol: "internaldrive",
      identifier: "settings-storage",
      accessibilityLabel: row.accessibilityLabel,
      isEnabled: row.isEnabled,
      action: model.confirmDeleteModel
    )
    .confirmationDialog(ModelStorageCopy.confirmationTitle, isPresented: $model.isConfirmingDelete,
                        titleVisibility: .visible) {
      // No identifiers here: SwiftUI turns these into alert actions, which carry their titles as
      // their identifiers, and an identifier of our own would be dropped on some releases and
      // shadow the title on others.
      Button(ModelStorageCopy.deleteAction, role: .destructive, action: model.deleteModel)
      Button(ModelStorageCopy.keepAction, role: .cancel) {}
    } message: {
      Text(ModelStorageCopy.confirmationMessage(
        ModelStorageCopy.size(bytes: model.storage.totalBytes)
      ))
    }
  }

  private var about: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text("About")
        .font(.caption)
        .foregroundStyle(DesignToken.textSecondary)
      Text(model.appInfo.displayName)
        .font(.subheadline)
        .foregroundStyle(DesignToken.textPrimary)
        .fixedSize(horizontal: false, vertical: true)
      Text(model.appInfo.versionLine)
        .font(.caption)
        .foregroundStyle(DesignToken.textSecondary)
        .accessibilityIdentifier("settings-version")
      Text(SettingsDrawerModel.privacyLine)
        .font(.caption)
        .foregroundStyle(DesignToken.textSecondary)
        .fixedSize(horizontal: false, vertical: true)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(16)
  }
}

private struct SettingsRow: View {
  let title: String
  let subtitle: String?
  let symbol: String
  let identifier: String
  let accessibilityLabel: String
  var isEnabled = true
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      HStack(spacing: 12) {
        // Both lines wrap rather than truncate: at the accessibility sizes a row's subtitle is
        // three lines of a 280 point panel, and "1.9 GB on this phone" losing its number to an
        // ellipsis would leave the row saying nothing at all.
        VStack(alignment: .leading, spacing: 2) {
          Text(title)
            .font(.subheadline)
            .foregroundStyle(isEnabled ? DesignToken.textPrimary : DesignToken.textSecondary)
            .fixedSize(horizontal: false, vertical: true)
          if let subtitle {
            Text(subtitle)
              .font(.caption)
              .foregroundStyle(DesignToken.textSecondary)
              .fixedSize(horizontal: false, vertical: true)
          }
        }
        Spacer(minLength: 8)
        Image(systemName: symbol)
          .font(.system(size: 13, weight: .regular))
          .foregroundStyle(DesignToken.textSecondary)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.horizontal, 16)
      .padding(.vertical, 14)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .disabled(!isEnabled)
    .accessibilityIdentifier(identifier)
    .accessibilityLabel(accessibilityLabel)
  }
}
