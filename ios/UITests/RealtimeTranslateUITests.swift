import XCTest

final class RealtimeTranslateUITests: XCTestCase {
  func testListeningAShowsPTTAndDisablesBOnTheSameScreen() {
    let app = launch(state: "listeningA")
    XCTAssertTrue(app.staticTexts["Session status: Speaker A is speaking"].exists)
    XCTAssertTrue(app.buttons["End Speaker A's turn"].exists)
    XCTAssertFalse(app.buttons["Start Speaker B's turn"].isEnabled)
    XCTAssertTrue(app.buttons["End session"].exists)
  }

  func testListeningLocksBothLanguageChips() {
    let app = launch(state: "listeningA")
    XCTAssertFalse(app.buttons["languages-A"].isEnabled)
    XCTAssertFalse(app.buttons["languages-B"].isEnabled)
  }

  func testFinalizingShowsActiveSourceBubble() {
    let app = launch(state: "finalizingA")
    XCTAssertTrue(app.staticTexts["Session status: Finalizing Speaker A's transcript"].exists)
    XCTAssertTrue(contains(app, "Hello."))
  }

  /// A failed turn keeps its transcript, says what happened in words a person can act on, and
  /// offers the one thing that was missing: sending it again. It used to be a dead end that
  /// mentioned Hy-MT2 by name and left the words nowhere to go.
  func testAFailedTranslationExplainsItselfAndOffersARetry() {
    let app = launch(state: "translationError")
    XCTAssertTrue(contains(app, "Hello."))
    XCTAssertTrue(contains(app, "The translation did not finish."))
    XCTAssertFalse(contains(app, "Hy-MT2"))

    let retry = app.buttons["retry-translation"]
    XCTAssertTrue(retry.waitForExistence(timeout: 5))
    XCTAssertTrue(retry.isEnabled)
    XCTAssertTrue(retry.isHittable)
    XCTAssertGreaterThanOrEqual(retry.frame.height, 44)

    XCTAssertTrue(app.buttons["Start Speaker A's turn"].isEnabled)
    XCTAssertTrue(app.buttons["Start Speaker B's turn"].isEnabled)
  }

  /// A 1.9 GB transfer someone changed their mind about had no way out at all: the session action
  /// was a disabled `Start Session` and nothing else on the screen stopped anything.
  func testTheModelDownloadCanBeCancelledFromTheBottomBar() {
    let app = launch(state: "loadingModel")
    let cancel = app.buttons["cancel-model-preparation"]
    XCTAssertTrue(cancel.waitForExistence(timeout: 10))
    XCTAssertTrue(cancel.isEnabled)
    XCTAssertTrue(cancel.isHittable)

    cancel.tap()

    let start = app.buttons["start-session"]
    XCTAssertTrue(start.waitForExistence(timeout: 5))
    XCTAssertTrue(start.isEnabled)
    XCTAssertFalse(app.buttons["cancel-model-preparation"].exists)
  }

  func testIdleStateOffersOneTapStartOnTheMainScreen() {
    let app = launch(state: "setup")
    XCTAssertTrue(app.buttons["Start session"].exists)
    XCTAssertTrue(app.buttons["Start session"].isEnabled)
    // The spoken language follows the reading language when the host offers a matching
    // on-device recognizer, and stays Automatic when it does not; accept both hosts.
    let labelA = app.buttons["languages-A"].label
    XCTAssertTrue(labelA.contains("reads English"))
    XCTAssertTrue(labelA.contains("speaks English") || labelA.contains("speaks Automatic"))
    let labelB = app.buttons["languages-B"].label
    XCTAssertTrue(labelB.contains("reads Korean"))
    XCTAssertTrue(labelB.contains("speaks Korean") || labelB.contains("speaks Automatic"))
    XCTAssertFalse(app.buttons["Start Speaker A's turn"].isEnabled)
  }

  /// Three things in one bar, in one order: the wordmark on the leading edge, the title in the
  /// middle, the menu button on the trailing edge. The wordmark is decoration and nothing else,
  /// so the assertion that it is not in `app.buttons` is the point of this test rather than a
  /// detail of it: it went back to being a logo, and a logo that is still tappable is the old
  /// design wearing the new one's layout.
  func testHeaderPutsTheWordmarkLeadingAndTheMenuButtonTrailing() {
    let app = launch(state: "ready")

    let wordmark = app.images["zetic-wordmark"]
    let menu = app.buttons["Settings"]
    XCTAssertTrue(wordmark.waitForExistence(timeout: 10))
    XCTAssertEqual(wordmark.label, "ZETIC")
    XCTAssertFalse(app.buttons["zetic-wordmark"].exists)
    XCTAssertTrue(menu.exists)
    XCTAssertTrue(menu.isHittable)

    XCTAssertLessThan(wordmark.frame.maxX, menu.frame.minX)
    XCTAssertLessThan(wordmark.frame.minX, app.frame.midX)
    XCTAssertGreaterThan(menu.frame.midX, app.frame.midX)
    // A finger's worth of button in both directions, whatever the glyph inside it measures.
    // Rounded, because a 44 pt frame comes back through the accessibility bridge as
    // 43.99999999999999 and a literal comparison fails a button that is exactly the right size.
    XCTAssertGreaterThanOrEqual(menu.frame.width.rounded(), 44)
    XCTAssertGreaterThanOrEqual(menu.frame.height.rounded(), 44)
    // The title sits between them rather than being pushed off one side.
    let title = app.staticTexts["Turn Translate"].firstMatch
    XCTAssertTrue(title.exists)
    XCTAssertGreaterThan(title.frame.minX, wordmark.frame.maxX)
    XCTAssertLessThan(title.frame.maxX, menu.frame.minX)
  }

  func testTheMenuButtonOpensTheSettingsDrawerAndTheScrimClosesIt() {
    let app = launch(state: "ready")
    app.buttons["Settings"].tap()

    let visit = app.buttons["settings-visit-zetic"]
    let contact = app.buttons["settings-contact-us"]
    XCTAssertTrue(visit.waitForExistence(timeout: 2))
    XCTAssertTrue(contact.exists)
    XCTAssertTrue(app.staticTexts["Settings"].exists)
    XCTAssertTrue(contains(app, "Turn Translate"))
    XCTAssertTrue(contains(app, "stays on this phone"))
    XCTAssertTrue(app.buttons["settings-close"].exists)

    // Tapping outside the panel, on the scrim's exposed left edge, closes the drawer.
    app.coordinate(withNormalizedOffset: CGVector(dx: 0.06, dy: 0.5)).tap()
    XCTAssertTrue(waitForDisappearance(visit))
  }

  func testContactRowShowsTheCopyToast() {
    let app = launch(state: "ready")
    app.buttons["Settings"].tap()
    let contact = app.buttons["settings-contact-us"]
    XCTAssertTrue(contact.waitForExistence(timeout: 2))
    XCTAssertTrue(contact.label.contains("contact@zetic.ai"))

    contact.tap()

    let toast = app.staticTexts["Email address copied"]
    XCTAssertTrue(toast.waitForExistence(timeout: 2))
    XCTAssertGreaterThan(toast.frame.minY, app.frame.midY)
    XCTAssertTrue(waitForDisappearance(toast, timeout: 6))
  }

  func testLongPressingABubbleCopiesItAndShowsTheCopiedToast() {
    let app = launch(state: "setup", extra: ["-toastSeconds", "6"])
    let bubble = app.descendants(matching: .any).matching(identifier: "conversation-bubble").firstMatch
    XCTAssertTrue(bubble.waitForExistence(timeout: 5))

    // Under full-suite load the first long-press can miss the context-menu window,
    // and the toast auto-dismisses after 2 seconds; retry the press and read the
    // toast frame only while it still exists.
    let copy = app.buttons["copy-bubble"]
    var menuShown = false
    for _ in 0..<3 where !menuShown {
      bubble.press(forDuration: 1.5)
      menuShown = copy.waitForExistence(timeout: 4)
    }
    XCTAssertTrue(menuShown)
    copy.tap()

    let toast = app.staticTexts["Copied"]
    XCTAssertTrue(toast.waitForExistence(timeout: 5))
    if toast.exists {
      XCTAssertGreaterThan(toast.frame.minY, app.frame.midY)
    }
    XCTAssertTrue(waitForDisappearance(toast, timeout: 8))
  }

  /// The status strip is one line of text again. Nothing tappable rides its trailing end now that
  /// there is no sound state to draw.
  func testTheStatusStripCarriesNoSoundToggle() {
    let app = launch(state: "ready")
    XCTAssertTrue(app.staticTexts["Session status: Ready to talk"].waitForExistence(timeout: 5))
    XCTAssertFalse(app.buttons["speech-mute"].exists)
    XCTAssertFalse(app.buttons["Spoken translation on"].exists)
    XCTAssertFalse(app.buttons["Spoken translation off"].exists)
  }

  /// The play control is the only way this app makes a sound, so it is on every translated bubble
  /// unconditionally: there is no longer a setting that can take it away.
  func testATranslatedBubbleCarriesAPlayControl() {
    let app = launch(state: "setup")
    let replay = app.buttons["replay-translation"]
    XCTAssertTrue(replay.waitForExistence(timeout: 5))
    XCTAssertEqual(replay.label, "Play translation")
    XCTAssertTrue(replay.isHittable)
    XCTAssertTrue(replay.isEnabled)
    replay.tap()

    XCTAssertGreaterThanOrEqual(replay.frame.width, 44)
    XCTAssertGreaterThanOrEqual(replay.frame.height, 44)

    // A failed translation has nothing to play, so the control is absent rather than disabled.
    app.terminate()
    let failed = launch(state: "translationError")
    XCTAssertTrue(failed.staticTexts["Session status: Ready to talk"].waitForExistence(timeout: 5))
    XCTAssertFalse(failed.buttons["replay-translation"].exists)
  }

  // MARK: - Following the conversation

  /// The promise the specification has always made, on a transcript far taller than the phone: the
  /// newest bubble is on screen without anybody scrolling, and there is no jump control offering to
  /// take you somewhere you already are.
  func testALongConversationOpensOnTheNewestBubble() {
    let app = launch(state: "longConversation")
    let newest = newestBubble(app)
    XCTAssertTrue(newest.waitForExistence(timeout: 10))
    XCTAssertTrue(newest.isHittable)
    XCTAssertLessThan(newest.frame.maxY, app.buttons["Start Speaker A's turn"].frame.minY)
    XCTAssertFalse(app.buttons["jump-to-latest"].exists)
  }

  /// Reading mode, end to end. Scrolling back stops the transcript moving; a turn that arrives
  /// while somebody is reading does not drag them anywhere, and the one control that appears puts
  /// them back at the newest bubble.
  ///
  /// The turn is typed rather than spoken, because a UI test has no microphone: a typed message
  /// travels the exact path a released push-to-talk hands a finalized transcript to, so the
  /// transcript changes exactly as it would for a spoken turn.
  func testATurnArrivingWhileScrolledBackOffersAJumpToLatest() {
    let app = launch(state: "longConversation")
    XCTAssertTrue(newestBubble(app).waitForExistence(timeout: 10))

    let jump = app.buttons["jump-to-latest"]
    // The transcript is the only scroller on this screen. Three swipes put the reader well past
    // one bubble's height, which is where reading mode begins. Nothing has arrived below yet, so
    // there is nothing to offer and the control stays away.
    for _ in 0..<3 { app.scrollViews.firstMatch.swipeDown() }
    XCTAssertFalse(jump.exists)

    app.buttons["typed-input"].tap()
    let field = app.descendants(matching: .any).matching(identifier: "typed-input-field").firstMatch
    XCTAssertTrue(field.waitForExistence(timeout: 5))
    field.tap()
    field.typeText("One more turn")
    app.buttons["typed-input-send"].tap()

    XCTAssertTrue(jump.waitForExistence(timeout: 10))
    XCTAssertEqual(jump.label, "Jump to latest")
    XCTAssertTrue(jump.isHittable)
    XCTAssertGreaterThanOrEqual(jump.frame.width.rounded(), 44)
    XCTAssertGreaterThanOrEqual(jump.frame.height.rounded(), 44)
    // Bottom trailing of the transcript, and clear of the push-to-talk row underneath it.
    XCTAssertGreaterThan(jump.frame.midX, app.frame.midX)
    XCTAssertLessThan(jump.frame.maxY, app.buttons["Start Speaker A's turn"].frame.minY)
    // The new turn did not drag the reader anywhere: they are still where they scrolled to.
    XCTAssertFalse(bubble(app, containing: "One more turn").isHittable)

    jump.tap()

    XCTAssertTrue(waitForDisappearance(jump, timeout: 5))
    XCTAssertTrue(bubble(app, containing: "One more turn").isHittable)
  }

  /// A chat bubble is one combined accessibility element, so a bubble is found by its identifier
  /// and its text together rather than as a loose label.
  private func bubble(_ app: XCUIApplication, containing text: String) -> XCUIElement {
    app.descendants(matching: .any).matching(
      NSPredicate(format: "identifier == %@ AND label CONTAINS %@", "conversation-bubble", text)
    ).firstMatch
  }

  private func newestBubble(_ app: XCUIApplication) -> XCUIElement {
    bubble(app, containing: "Turn number 20.")
  }

  private func waitForDisappearance(_ element: XCUIElement, timeout: TimeInterval = 3) -> Bool {
    let gone = expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: element)
    return XCTWaiter().wait(for: [gone], timeout: timeout) == .completed
  }

  func testLanguageBarSitsAboveTheConversationAndPushToTalk() {
    let app = launch(state: "ready")
    let chipA = app.buttons["languages-A"]
    let chipB = app.buttons["languages-B"]

    XCTAssertLessThan(chipA.frame.minX, chipB.frame.minX)
    XCTAssertLessThan(chipA.frame.maxY, app.buttons["Start Speaker A's turn"].frame.minY)
  }

  func testModelLoadingDisablesLanguagePickersAndPushToTalk() {
    let app = launch(state: "loadingModel")
    XCTAssertFalse(app.buttons["languages-A"].isEnabled)
    XCTAssertFalse(app.buttons["languages-B"].isEnabled)
    XCTAssertFalse(app.buttons["Start Speaker A's turn"].isEnabled)
  }

  func testModelLoadFailureEnablesLanguagePickersAndInlineRetry() {
    let app = launch(state: "modelLoadFailed")
    XCTAssertTrue(app.buttons["languages-A"].isEnabled)
    XCTAssertTrue(app.buttons["languages-B"].isEnabled)
    XCTAssertTrue(app.buttons["retry-model-load"].exists)
    XCTAssertTrue(app.buttons["Start session"].isEnabled)
  }

  func testReadyControlsRemainHittableAboveTheHomeIndicator() {
    let app = launch(state: "ready")
    let endSession = app.buttons["End session"]

    XCTAssertTrue(endSession.isHittable)
    XCTAssertLessThan(endSession.frame.maxY, app.frame.maxY)
    XCTAssertTrue(app.buttons["Start Speaker A's turn"].isEnabled)
    XCTAssertTrue(app.buttons["Start Speaker B's turn"].isEnabled)
  }

  private func contains(_ app: XCUIApplication, _ text: String) -> Bool {
    app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", text)).firstMatch.exists
  }

  // MARK: - First run

  func testWelcomeAppearsOnTheVeryFirstLaunchAndNeverAgainAfterGetStarted() {
    let app = XCUIApplication()
    app.launchArguments = ["-firstRun", "fresh", "-uiState", "ready"]
    app.launch()

    let getStarted = app.buttons["welcome-get-started"]
    XCTAssertTrue(getStarted.waitForExistence(timeout: 10))
    XCTAssertTrue(contains(app, "Two people, two languages, one phone."))
    XCTAssertTrue(contains(app, "Nothing is sent to a server."))
    getStarted.tap()
    XCTAssertTrue(waitForDisappearance(getStarted))

    // Straight into the permission priming, because the simulator has answered nothing yet.
    XCTAssertTrue(app.buttons["priming-continue"].waitForExistence(timeout: 5))
    XCTAssertTrue(contains(app, "No audio and no text leave the device."))

    // Relaunching without any first-run argument must find the welcome already remembered.
    // The pause gives `UserDefaults` time to flush the flag before the app goes away.
    Thread.sleep(forTimeInterval: 1)
    app.terminate()
    app.launchArguments = ["-uiState", "ready"]
    app.launch()
    XCTAssertTrue(app.buttons["priming-continue"].waitForExistence(timeout: 10))
    XCTAssertFalse(app.buttons["welcome-get-started"].exists)
  }

  func testFirstStartConversationAsksBeforeDownloadingTheModel() {
    let app = launch(state: "setup", firstRun: "consentNeeded")
    let start = app.buttons["start-session"]
    XCTAssertTrue(start.waitForExistence(timeout: 10))
    XCTAssertFalse(app.buttons["consent-download"].exists)

    start.tap()

    let download = app.buttons["consent-download"]
    XCTAssertTrue(download.waitForExistence(timeout: 5))
    XCTAssertTrue(contains(app, "1.91 GB"))
    XCTAssertTrue(contains(app, "It downloads once"))
    XCTAssertTrue(app.buttons["consent-not-now"].exists)

    app.buttons["consent-not-now"].tap()
    XCTAssertTrue(waitForDisappearance(download))
    XCTAssertTrue(app.buttons["start-session"].isEnabled)
  }

  func testConsentWarnsAboutWiFiOnlyWhenThePathIsExpensive() {
    let cellular = launch(state: "setup", firstRun: "consentNeeded", extra: ["-firstRunCellular"])
    XCTAssertTrue(cellular.buttons["start-session"].waitForExistence(timeout: 10))
    cellular.buttons["start-session"].tap()
    XCTAssertTrue(cellular.buttons["consent-download"].waitForExistence(timeout: 5))
    XCTAssertTrue(cellular.staticTexts["consent-cellular-warning"].exists)
    cellular.terminate()

    let wifi = launch(state: "setup", firstRun: "consentNeeded")
    XCTAssertTrue(wifi.buttons["start-session"].waitForExistence(timeout: 10))
    wifi.buttons["start-session"].tap()
    XCTAssertTrue(wifi.buttons["consent-download"].waitForExistence(timeout: 5))
    XCTAssertFalse(wifi.staticTexts["consent-cellular-warning"].exists)
  }

  func testReturningUserSeesNoFirstRunSurfaceAtAll() {
    let app = launch(state: "ready")
    XCTAssertFalse(app.buttons["welcome-get-started"].exists)
    XCTAssertFalse(app.buttons["priming-continue"].exists)
    XCTAssertFalse(app.buttons["consent-download"].exists)
    XCTAssertTrue(app.buttons["Settings"].exists)
  }

  // MARK: - Typed input and clearing

  func testTypingAMessageProducesThatSpeakersBubble() {
    let app = launch(state: "ready")
    let typedInput = app.buttons["typed-input"]
    XCTAssertTrue(typedInput.waitForExistence(timeout: 10))
    XCTAssertTrue(typedInput.isHittable)
    XCTAssertTrue(typedInput.isEnabled)
    // On the hint row, clear of the push-to-talk controls and the session action.
    XCTAssertGreaterThan(typedInput.frame.minY, app.buttons["Start Speaker A's turn"].frame.maxY)
    XCTAssertLessThan(typedInput.frame.maxY, app.buttons["End session"].frame.minY)

    typedInput.tap()

    // A vertically growing `TextField` surfaces as a text view on some releases and a text field
    // on others, so the field is found by identifier rather than by element type.
    let field = app.descendants(matching: .any).matching(identifier: "typed-input-field").firstMatch
    XCTAssertTrue(field.waitForExistence(timeout: 5))
    XCTAssertTrue(app.buttons["typed-input-cancel"].exists)
    // Nothing typed yet, so there is no turn to send.
    XCTAssertFalse(app.buttons["typed-input-send"].isEnabled)
    XCTAssertTrue(contains(app, "Speaker A types in English"))

    field.tap()
    field.typeText("Good morning")
    let send = app.buttons["typed-input-send"]
    XCTAssertTrue(send.isEnabled)
    send.tap()

    XCTAssertTrue(waitForDisappearance(send, timeout: 5))
    let bubble = app.descendants(matching: .any).matching(identifier: "conversation-bubble").firstMatch
    XCTAssertTrue(bubble.waitForExistence(timeout: 5))
    XCTAssertTrue(bubble.label.contains("Good morning"))
    XCTAssertTrue(bubble.label.contains("Speaker A"))
  }

  func testTypedInputIsLockedBeforeTheModelIsReady() {
    let app = launch(state: "setup")
    let typedInput = app.buttons["typed-input"]
    XCTAssertTrue(typedInput.waitForExistence(timeout: 10))
    XCTAssertFalse(typedInput.isEnabled)
  }

  func testTheDrawersClearRowEmptiesTheTranscript() {
    let app = launch(state: "setup", extra: ["-toastSeconds", "6"])
    let bubble = app.descendants(matching: .any).matching(identifier: "conversation-bubble").firstMatch
    XCTAssertTrue(bubble.waitForExistence(timeout: 10))

    app.buttons["Settings"].tap()
    let clear = app.buttons["settings-clear-conversation"]
    XCTAssertTrue(clear.waitForExistence(timeout: 5))
    XCTAssertTrue(clear.isEnabled)

    clear.tap()

    let toast = app.staticTexts["Conversation cleared"]
    XCTAssertTrue(toast.waitForExistence(timeout: 5))
    XCTAssertTrue(waitForDisappearance(bubble, timeout: 5))
    // The session action is untouched: clearing empties the transcript, it does not end anything.
    XCTAssertTrue(app.buttons["Start session"].exists)

    // With nothing left to clear the row stays where it is and stops being tappable.
    app.buttons["Settings"].tap()
    XCTAssertTrue(clear.waitForExistence(timeout: 5))
    XCTAssertFalse(clear.isEnabled)
  }

  // MARK: - App language

  /// The row exists, sits in the drawer's list, and names the language in force. It deliberately
  /// does not change the language: every assertion in this file is an English string, and an
  /// override written here would outlive the test and be read by the next launch.
  func testTheDrawerNamesTheAppLanguageAndDefaultsToTheSystemOne() {
    let app = launch(state: "ready")
    app.buttons["Settings"].tap()

    let row = app.buttons["settings-app-language"]
    XCTAssertTrue(row.waitForExistence(timeout: 10))
    XCTAssertTrue(row.isEnabled)
    XCTAssertTrue(row.label.contains("App language"))
    XCTAssertTrue(row.label.contains("System"))
    // Between the clear row and `Visit zetic.ai`, so the list keeps the documented order.
    XCTAssertGreaterThan(row.frame.minY, app.buttons["settings-clear-conversation"].frame.maxY)
    XCTAssertLessThan(row.frame.maxY, app.buttons["settings-visit-zetic"].frame.minY)
    // The `Storage` row and its delete flow are gone; the drawer is five rows now.
    XCTAssertFalse(app.buttons["settings-storage"].exists)
  }

  /// Every existing scenario is a returning user: the first-run flags are forced closed so the
  /// welcome never stands between the test and the screen it is checking, the remembered languages
  /// are cleared so a run never inherits the previous one's chips, and the app-language override is
  /// cleared so every run reads the English strings these assertions are written against.
  private func launch(state: String, firstRun: String = "returning",
                      extra: [String] = []) -> XCUIApplication {
    let app = XCUIApplication()
    app.launchArguments =
      ["-uiState", state, "-firstRun", firstRun, "-resetLanguages", "-resetAppLanguage"] + extra
    app.launch()
    return app
  }
}

