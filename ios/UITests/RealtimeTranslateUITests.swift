import XCTest

final class RealtimeTranslateUITests: XCTestCase {
  func testListeningAShowsPTTAndDisablesBOnTheSameScreen() {
    let app = launch(state: "listeningA")
    XCTAssertTrue(app.staticTexts["Session status: A is speaking"].exists)
    XCTAssertTrue(app.buttons["End A Turn"].exists)
    XCTAssertFalse(app.buttons["Start B Turn"].isEnabled)
    XCTAssertTrue(app.buttons["End Session"].exists)
  }

  func testListeningLocksBothLanguageChips() {
    let app = launch(state: "listeningA")
    XCTAssertFalse(app.buttons["languages-A"].isEnabled)
    XCTAssertFalse(app.buttons["languages-B"].isEnabled)
  }

  func testFinalizingShowsActiveSourceBubble() {
    let app = launch(state: "finalizingA")
    XCTAssertTrue(app.staticTexts["Session status: Finalizing A's transcript"].exists)
    XCTAssertTrue(contains(app, "Hello."))
  }

  func testTranslationErrorKeepsBubbleAndEnablesNextTurn() {
    let app = launch(state: "translationError")
    XCTAssertTrue(contains(app, "Hello."))
    XCTAssertTrue(contains(app, "Hy-MT2"))
    XCTAssertTrue(app.buttons["Start A Turn"].isEnabled)
    XCTAssertTrue(app.buttons["Start B Turn"].isEnabled)
  }

  func testEndedStateOffersOneTapStartOnTheMainScreen() {
    let app = launch(state: "ended")
    XCTAssertTrue(app.buttons["Start Session"].exists)
    XCTAssertTrue(app.buttons["Start Session"].isEnabled)
    // The spoken language follows the reading language when the host offers a matching
    // on-device recognizer, and stays Automatic when it does not; accept both hosts.
    let labelA = app.buttons["languages-A"].label
    XCTAssertTrue(labelA.contains("reads English"))
    XCTAssertTrue(labelA.contains("speaks English") || labelA.contains("speaks Automatic"))
    let labelB = app.buttons["languages-B"].label
    XCTAssertTrue(labelB.contains("reads Korean"))
    XCTAssertTrue(labelB.contains("speaks Korean") || labelB.contains("speaks Automatic"))
    XCTAssertFalse(app.buttons["Start A Turn"].isEnabled)
  }

  func testHeaderCarriesTheZeticWordmarkAsTheSettingsButton() {
    let app = launch(state: "ready")
    XCTAssertTrue(app.buttons["ZETIC, opens settings"].exists)
    XCTAssertTrue(app.buttons["ZETIC, opens settings"].isHittable)
  }

  func testWordmarkOpensTheSettingsDrawerAndTheScrimClosesIt() {
    let app = launch(state: "ready")
    app.buttons["ZETIC, opens settings"].tap()

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
    app.buttons["ZETIC, opens settings"].tap()
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
    let app = launch(state: "ended")
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

  func testTheMuteToggleSitsInTheStatusStripAndFlipsItsState() {
    let app = launch(state: "ready")
    let toggle = app.buttons["speech-mute"]
    XCTAssertTrue(toggle.waitForExistence(timeout: 5))
    XCTAssertTrue(toggle.isHittable)
    // Near the status strip, above the language chips, and clear of the wordmark button.
    XCTAssertLessThan(toggle.frame.maxY, app.buttons["languages-A"].frame.minY)
    XCTAssertGreaterThan(toggle.frame.minY, app.buttons["ZETIC, opens settings"].frame.maxY)

    let soundOn = toggle.label
    XCTAssertEqual(soundOn, "Spoken translation on")
    toggle.tap()
    XCTAssertTrue(app.buttons["Spoken translation off"].waitForExistence(timeout: 3))

    // Left as it was found, so the stored preference does not leak into the next test.
    app.buttons["Spoken translation off"].tap()
    XCTAssertTrue(app.buttons[soundOn].waitForExistence(timeout: 3))
  }

  func testATranslatedBubbleCarriesAReplayControl() {
    let app = launch(state: "ended")
    let replay = app.buttons["replay-translation"]
    XCTAssertTrue(replay.waitForExistence(timeout: 5))
    XCTAssertEqual(replay.label, "Play translation")
    XCTAssertTrue(replay.isHittable)
    replay.tap()

    // A failed translation has nothing to play, so the control is absent rather than disabled.
    app.terminate()
    let failed = launch(state: "translationError")
    XCTAssertTrue(failed.staticTexts["Session status: Ready to Talk"].waitForExistence(timeout: 5))
    XCTAssertFalse(failed.buttons["replay-translation"].exists)
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
    XCTAssertLessThan(chipA.frame.maxY, app.buttons["Start A Turn"].frame.minY)
  }

  func testModelLoadingDisablesLanguagePickersAndPushToTalk() {
    let app = launch(state: "loadingModel")
    XCTAssertFalse(app.buttons["languages-A"].isEnabled)
    XCTAssertFalse(app.buttons["languages-B"].isEnabled)
    XCTAssertFalse(app.buttons["Start A Turn"].isEnabled)
  }

  func testModelLoadFailureEnablesLanguagePickersAndInlineRetry() {
    let app = launch(state: "modelLoadFailed")
    XCTAssertTrue(app.buttons["languages-A"].isEnabled)
    XCTAssertTrue(app.buttons["languages-B"].isEnabled)
    XCTAssertTrue(app.buttons["retry-model-load"].exists)
    XCTAssertTrue(app.buttons["Start Session"].isEnabled)
  }

  func testReadyControlsRemainHittableAboveTheHomeIndicator() {
    let app = launch(state: "ready")
    let endSession = app.buttons["End Session"]

    XCTAssertTrue(endSession.isHittable)
    XCTAssertLessThan(endSession.frame.maxY, app.frame.maxY)
    XCTAssertTrue(app.buttons["Start A Turn"].isEnabled)
    XCTAssertTrue(app.buttons["Start B Turn"].isEnabled)
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
    let app = launch(state: "ended", firstRun: "consentNeeded")
    let start = app.buttons["start-session"]
    XCTAssertTrue(start.waitForExistence(timeout: 10))
    XCTAssertFalse(app.buttons["consent-download"].exists)

    start.tap()

    let download = app.buttons["consent-download"]
    XCTAssertTrue(download.waitForExistence(timeout: 5))
    XCTAssertTrue(contains(app, "about 1.9 GB"))
    XCTAssertTrue(contains(app, "It downloads once"))
    XCTAssertTrue(app.buttons["consent-not-now"].exists)

    app.buttons["consent-not-now"].tap()
    XCTAssertTrue(waitForDisappearance(download))
    XCTAssertTrue(app.buttons["start-session"].isEnabled)
  }

  func testConsentWarnsAboutWiFiOnlyWhenThePathIsExpensive() {
    let cellular = launch(state: "ended", firstRun: "consentNeeded", extra: ["-firstRunCellular"])
    XCTAssertTrue(cellular.buttons["start-session"].waitForExistence(timeout: 10))
    cellular.buttons["start-session"].tap()
    XCTAssertTrue(cellular.buttons["consent-download"].waitForExistence(timeout: 5))
    XCTAssertTrue(cellular.staticTexts["consent-cellular-warning"].exists)
    cellular.terminate()

    let wifi = launch(state: "ended", firstRun: "consentNeeded")
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
    XCTAssertTrue(app.buttons["ZETIC, opens settings"].exists)
  }

  /// Every existing scenario is a returning user: the first-run flags are forced closed so the
  /// welcome never stands between the test and the screen it is checking.
  private func launch(state: String, firstRun: String = "returning",
                      extra: [String] = []) -> XCUIApplication {
    let app = XCUIApplication()
    app.launchArguments = ["-uiState", state, "-firstRun", firstRun] + extra
    app.launch()
    return app
  }
}

