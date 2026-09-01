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
    XCTAssertFalse(app.buttons["source-language-A"].isEnabled)
    XCTAssertFalse(app.buttons["target-language-A"].isEnabled)
    XCTAssertFalse(app.buttons["source-language-B"].isEnabled)
    XCTAssertFalse(app.buttons["target-language-B"].isEnabled)
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
    XCTAssertTrue(app.buttons["source-language-A"].label.contains("Automatic"))
    XCTAssertTrue(app.buttons["source-language-B"].label.contains("Automatic"))
    XCTAssertFalse(app.buttons["Start A Turn"].isEnabled)
  }

  func testModelLoadingDisablesLanguagePickersAndPushToTalk() {
    let app = launch(state: "loadingModel")
    XCTAssertFalse(app.buttons["source-language-A"].isEnabled)
    XCTAssertFalse(app.buttons["target-language-A"].isEnabled)
    XCTAssertFalse(app.buttons["source-language-B"].isEnabled)
    XCTAssertFalse(app.buttons["target-language-B"].isEnabled)
    XCTAssertFalse(app.buttons["Start A Turn"].isEnabled)
  }

  func testModelLoadFailureEnablesLanguagePickersAndInlineRetry() {
    let app = launch(state: "modelLoadFailed")
    XCTAssertTrue(app.buttons["source-language-A"].isEnabled)
    XCTAssertTrue(app.buttons["target-language-B"].isEnabled)
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

  private func launch(state: String) -> XCUIApplication {
    let app = XCUIApplication()
    app.launchArguments = ["-uiState", state]
    app.launch()
    return app
  }
}
