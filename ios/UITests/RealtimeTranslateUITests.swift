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
    XCTAssertTrue(app.buttons["languages-A"].label.contains("reads English"))
    XCTAssertTrue(app.buttons["languages-A"].label.contains("speaks Automatic"))
    XCTAssertTrue(app.buttons["languages-B"].label.contains("reads Korean"))
    XCTAssertTrue(app.buttons["languages-B"].label.contains("speaks Automatic"))
    XCTAssertFalse(app.buttons["Start A Turn"].isEnabled)
  }

  func testHeaderCarriesTheZeticWordmark() {
    let app = launch(state: "ready")
    XCTAssertTrue(app.images["ZETIC"].exists)
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

  private func launch(state: String) -> XCUIApplication {
    let app = XCUIApplication()
    app.launchArguments = ["-uiState", state]
    app.launch()
    return app
  }
}
