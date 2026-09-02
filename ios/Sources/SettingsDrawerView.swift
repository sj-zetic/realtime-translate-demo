import SwiftUI

/// The right-side settings drawer and its scrim, with the shared copy-confirmation toast layered
/// over it. Presented as a full-screen overlay above the main screen so the menu button stays
/// where it is.
struct SettingsDrawerOverlay: View {
  @ObservedObject var model: SettingsDrawerModel
  /// The one session action the drawer carries. Passed in rather than reached for, so the drawer
  /// still knows nothing about the view model behind it.
  let canClearConversation: Bool
  let clearConversation: () -> Void
  /// The app-language override, owned by the root view's `@AppStorage` so the environment locale
  /// and the row can never disagree, and handed down here the same way the clear action is.
  let appLanguage: AppLanguage
  let selectAppLanguage: (AppLanguage) -> Void

  var body: some View {
    ZStack(alignment: .trailing) {
      if model.isOpen {
        Scrim(close: model.close)
        SettingsDrawerPanel(model: model, canClearConversation: canClearConversation,
                            clearConversation: clearConversation,
                            appLanguage: appLanguage, selectAppLanguage: selectAppLanguage)
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
      .accessibilityLabel(Text("Close settings",
                               comment: "Accessibility label for the drawer scrim and close button"))
      .accessibilityAddTraits(.isButton)
  }
}

private struct SettingsDrawerPanel: View {
  @ObservedObject var model: SettingsDrawerModel
  let canClearConversation: Bool
  let clearConversation: () -> Void
  let appLanguage: AppLanguage
  let selectAppLanguage: (AppLanguage) -> Void

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
      // One key, two places: the panel heading here and the navigation bar button that opens it,
      // which is the same word for the same thing and must not drift apart in translation.
      Text("Settings",
           comment: "Settings drawer panel heading, and the accessibility label for the navigation bar button that opens it")
        .font(.headline)
        .foregroundStyle(DesignToken.textPrimary)
      Spacer(minLength: 8)
      Button(action: model.close) {
        Image(systemName: "xmark")
          .font(.system(size: 15, weight: .semibold))
          .foregroundStyle(DesignToken.textSecondary)
          .frame(width: Layout.tapTarget, height: Layout.tapTarget)
          .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .accessibilityIdentifier("settings-close")
      .accessibilityLabel(Text("Close settings",
                               comment: "Accessibility label for the drawer scrim and close button"))
    }
    .padding(.leading, 16)
    .padding(.trailing, 8)
    .padding(.vertical, 10)
  }

  /// The drawer's row list. New settings rows slot in here between the existing rows and keep the
  /// same divider rhythm.
  private var rows: some View {
    VStack(spacing: 0) {
      // First, because it is the one row someone opens the drawer in order to use. Disabled
      // rather than hidden on an empty transcript or mid-utterance, so the row never moves.
      SettingsRow(
        title: SettingsDrawerModel.clearConversationTitle,
        subtitle: SettingsDrawerModel.clearConversationSubtitle,
        symbol: "trash",
        identifier: "settings-clear-conversation",
        accessibilityLabel: SettingsDrawerModel
          .clearConversationAccessibilityLabel(isEnabled: canClearConversation),
        isEnabled: canClearConversation,
        action: { model.clearConversation(clearConversation) }
      )
      ThinDivider()
      AppLanguageRow(selected: appLanguage, select: selectAppLanguage)
      ThinDivider()
      SettingsRow(
        title: String(localized: "Visit zetic.ai",
                      comment: "Settings drawer row title. zetic.ai is a domain, keep it as is"),
        subtitle: nil,
        symbol: "arrow.up.right.square",
        identifier: "settings-visit-zetic",
        accessibilityLabel: String(localized: "Visit zetic.ai, opens the website",
                                   comment: "Accessibility label for the Visit zetic.ai row"),
        action: model.openWebsite
      )
      ThinDivider()
      SettingsRow(
        title: String(localized: "Contact us", comment: "Settings drawer row title"),
        subtitle: SettingsDrawerModel.contactEmail,
        symbol: "doc.on.doc",
        identifier: "settings-contact-us",
        accessibilityLabel: String(
          localized: "settings.contactUs.accessibility",
          defaultValue: "Contact us, copies \(SettingsDrawerModel.contactEmail)",
          comment: "Accessibility label for the Contact us row. %@ is an email address"
        ),
        action: model.copyContactEmail
      )
    }
  }

  private var about: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text("About", comment: "Settings drawer section heading above the app name and version")
        .font(.caption)
        .foregroundStyle(DesignToken.textSecondary)
      Text(verbatim: model.appInfo.displayName)
        .font(.subheadline)
        .foregroundStyle(DesignToken.textPrimary)
        .fixedSize(horizontal: false, vertical: true)
      Text(verbatim: model.appInfo.versionLine)
        .font(.caption)
        .foregroundStyle(DesignToken.textSecondary)
        .accessibilityIdentifier("settings-version")
      Text(verbatim: SettingsDrawerModel.privacyLine)
        .font(.caption)
        .foregroundStyle(DesignToken.textSecondary)
        .fixedSize(horizontal: false, vertical: true)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(16)
  }
}

/// The app-language row. A `Menu` rather than a push destination, because the drawer has no
/// navigation of its own and four options do not earn a screen; it wears the same layout as every
/// other row so the list keeps one shape.
///
/// The row shows the current choice as its subtitle, which is the whole point of it: someone who
/// has put the app into a language they cannot read needs to recognize this row by its value.
private struct AppLanguageRow: View {
  let selected: AppLanguage
  let select: (AppLanguage) -> Void

  var body: some View {
    Menu {
      Picker(AppLanguageCopy.title, selection: binding) {
        ForEach(AppLanguage.allCases) { language in
          Text(verbatim: language.displayName).tag(language)
        }
      }
      .pickerStyle(.inline)
    } label: {
      SettingsRowLabel(title: AppLanguageCopy.title, subtitle: selected.displayName,
                       symbol: "globe", isEnabled: true)
    }
    .accessibilityIdentifier("settings-app-language")
    .accessibilityLabel(accessibilityLabel)
  }

  /// A comma between two pieces that are each already translated, so it is punctuation rather than
  /// copy and stays out of the catalog. Held in a `String` so it cannot take the localized overload.
  private var accessibilityLabel: String {
    "\(AppLanguageCopy.title), \(selected.displayName)"
  }

  /// The picker writes through the caller rather than holding state of its own, so the stored
  /// preference, the environment locale, and the `AppleLanguages` override all move together.
  private var binding: Binding<AppLanguage> {
    Binding(get: { selected }, set: select)
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
      SettingsRowLabel(title: title, subtitle: subtitle, symbol: symbol, isEnabled: isEnabled)
    }
    .buttonStyle(.plain)
    .disabled(!isEnabled)
    .accessibilityIdentifier(identifier)
    .accessibilityLabel(accessibilityLabel)
  }
}

/// One row's appearance, without the button around it, so the language row's `Menu` and the four
/// action rows are laid out by the same code rather than by two copies of it.
private struct SettingsRowLabel: View {
  let title: String
  let subtitle: String?
  let symbol: String
  let isEnabled: Bool

  var body: some View {
    HStack(spacing: 12) {
      // Both lines wrap rather than truncate: at the accessibility sizes a row's subtitle is
      // three lines of a 280 point panel, and "1.9 GB on this phone" losing its number to an
      // ellipsis would leave the row saying nothing at all.
      VStack(alignment: .leading, spacing: 2) {
        Text(verbatim: title)
          .font(.subheadline)
          .foregroundStyle(isEnabled ? DesignToken.textPrimary : DesignToken.textSecondary)
          .fixedSize(horizontal: false, vertical: true)
        if let subtitle {
          Text(verbatim: subtitle)
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
}
