import XCTest

final class RealtimeTranslateUITests: XCTestCase {
  func testListeningAShowsPTTAndDisablesB() {
    let app = launch(state: "listeningA")
    XCTAssertTrue(app.staticTexts["A is speaking"].exists)
    XCTAssertTrue(app.buttons["End A Turn"].exists)
    XCTAssertFalse(app.buttons["Start B Turn"].isEnabled)
  }

  func testFinalizingShowsActiveSourceCard() {
    let app = launch(state: "finalizingA")
    XCTAssertTrue(app.staticTexts["Finalizing A's transcript"].exists)
    XCTAssertTrue(app.staticTexts["Hello."].exists)
  }

  func testTranslationErrorKeepsCardAndEnablesNextTurn() {
    let app = launch(state: "translationError")
    XCTAssertTrue(app.staticTexts["Hello."].exists)
    XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "Hy-MT2")).firstMatch.exists)
    XCTAssertTrue(app.buttons["Start A Turn"].isEnabled)
    XCTAssertTrue(app.buttons["Start B Turn"].isEnabled)
  }

  func testEndedStateReturnsToTargetLanguageSetup() {
    let app = launch(state: "ended")
    XCTAssertTrue(app.buttons["Start Session"].exists)
    XCTAssertTrue(app.buttons["Start Session"].isEnabled)
    XCTAssertTrue(app.buttons["source-language-A"].label.contains("Automatic"))
    XCTAssertTrue(app.buttons["source-language-B"].label.contains("Automatic"))
  }

  func testModelLoadingDisablesLanguagePickers() {
    let app = launch(state: "loadingModel")
    XCTAssertFalse(app.buttons["source-language-A"].isEnabled)
    XCTAssertFalse(app.buttons["target-language-A"].isEnabled)
    XCTAssertFalse(app.buttons["source-language-B"].isEnabled)
    XCTAssertFalse(app.buttons["target-language-B"].isEnabled)
  }

  func testModelLoadFailureEnablesLanguagePickers() {
    let app = launch(state: "modelLoadFailed")
    XCTAssertTrue(app.buttons["source-language-A"].isEnabled)
    XCTAssertTrue(app.buttons["target-language-B"].isEnabled)
  }

  func testReadyControlsRemainHittableAboveTheHomeIndicator() {
    let app = launch(state: "ready")
    let endSession = app.buttons["End Session"]

    XCTAssertTrue(endSession.isHittable)
    XCTAssertLessThan(endSession.frame.maxY, app.frame.maxY)
  }

  private func launch(state: String) -> XCUIApplication {
    let app = XCUIApplication()
    app.launchArguments = ["-uiState", state]
    app.launch()
    return app
  }
}
