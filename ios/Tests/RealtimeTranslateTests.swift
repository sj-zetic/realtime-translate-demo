import XCTest
import Speech
@testable import RealtimeTranslate

@MainActor
final class RealtimeTranslateTests: XCTestCase {
  func testHyMT2CandidateCatalogHas38Languages() {
    XCTAssertEqual(TargetLanguage.hyMT2Candidates.count, 38)
    XCTAssertEqual(TargetLanguage.hyMT2Candidates.first { $0.code == "tl" }?.name, "Filipino")
  }

  func testHyMT2RequestUsesOneUserPromptAndOfficialFlatTemplate() {
    let request = HyMT2Request(sourceText: "Good morning", targetLanguage: .hyMT2Candidates[2])

    let expected = "Translate the following text into French. "
      + "Note that you should only output the translated result without any additional explanation:\n\nGood morning"
    XCTAssertEqual(request.userMessage, expected)
    let expectedFlatPrompt = "<\u{FF5C}hy_begin\u{2581}of\u{2581}sentence\u{FF5C}>"
      + "<\u{FF5C}hy_User\u{FF5C}>\(expected)"
      + "<\u{FF5C}hy_Assistant\u{FF5C}>"
    XCTAssertEqual(request.flatPrompt, expectedFlatPrompt)
    XCTAssertEqual(Array(request.flatPrompt.utf8), Array(expectedFlatPrompt.utf8))
  }

  func testCompletedTurnBuildsTheOfficialHyMT2RequestAndShowsRuntimeResult() async {
    let recognizer = FakeSpeechRecognizer()
    let runtime = FakeTranslationRuntime(result: "Bonjour")
    let viewModel = readyViewModel(recognizer, runtime: runtime)
    viewModel.targetLanguageB = .hyMT2Candidates[2]

    viewModel.beginTurn(.a)
    recognizer.sendFinal("Good morning")
    viewModel.endTurn(.a)

    XCTAssertEqual(
      viewModel.mostRecentTranslationRequest,
      HyMT2Request(sourceText: "Good morning", targetLanguage: .hyMT2Candidates[2])
    )
    await waitUntil { viewModel.state == .ready }
    XCTAssertEqual(viewModel.items.last?.translation, "Bonjour")
    XCTAssertEqual(runtime.prompts.count, 1)
  }

  func testDefaultReadingLanguagesDifferSoTheFirstSessionTranslates() {
    let viewModel = RealtimeTranslateViewModel(state: .setup, speechRecognizer: FakeSpeechRecognizer())

    XCTAssertEqual(viewModel.sourceLanguageA, .automatic)
    XCTAssertEqual(viewModel.sourceLanguageB, .automatic)
    XCTAssertEqual(viewModel.targetLanguageA.code, "en")
    XCTAssertEqual(viewModel.targetLanguageB.code, "ko")
    XCTAssertTrue(viewModel.canStartSession)
  }

  func testSourceLanguagesStartWithAutomaticThenUsePlatformLocales() {
    let recognizer = FakeSpeechRecognizer()
    recognizer.sourceLanguages = [SpeechSourceLanguage(identifier: "fr-FR", name: "French (France)")]

    let viewModel = RealtimeTranslateViewModel(state: .ready, speechRecognizer: recognizer)

    XCTAssertEqual(viewModel.sourceLanguageA, .automatic)
    XCTAssertEqual(viewModel.sourceLanguageB, .automatic)
    XCTAssertEqual(viewModel.availableSourceLanguages, [.automatic, recognizer.sourceLanguages[0]])
  }

  func testPlatformSourceLanguageCatalogFiltersToOnDeviceLocales() {
    let english = Locale(identifier: "en-US")
    let french = Locale(identifier: "fr-FR")

    let languages = PlatformSpeechRecognizer.sourceLanguages(
      locales: [french, english],
      supportsOnDeviceRecognition: { $0.identifier == english.identifier },
      localizedName: { $0.identifier }
    )

    XCTAssertEqual(languages, [SpeechSourceLanguage(identifier: "en-US", name: "en-US")])
  }

  func testExplicitSourceLanguageReachesSpeechRecognizer() {
    let recognizer = FakeSpeechRecognizer()
    let language = SpeechSourceLanguage(identifier: "fr-FR", name: "French (France)")
    recognizer.sourceLanguages = [language]
    let viewModel = readyViewModel(recognizer)
    viewModel.sourceLanguageA = language

    viewModel.beginTurn(.a)

    XCTAssertEqual(recognizer.startedSources, [language])
  }

  func testAutomaticSourceUsesCurrentLocale() {
    XCTAssertEqual(SpeechSourceLanguage.automatic.locale.identifier, Locale.current.identifier)
  }

  func testOnlyOneSpeakerCanListenAtATime() {
    let recognizer = FakeSpeechRecognizer()
    let viewModel = readyViewModel(recognizer)

    viewModel.beginTurn(.a)
    viewModel.beginTurn(.b)

    XCTAssertEqual(viewModel.state, .listening(.a))
    XCTAssertEqual(recognizer.startedSources, [.automatic])
  }

  func testATurnRoutesTranslationToBLanguage() async {
    let recognizer = FakeSpeechRecognizer()
    let viewModel = readyViewModel(recognizer)

    viewModel.beginTurn(.a)
    recognizer.sendPartial("Hello")
    XCTAssertEqual(viewModel.items.last?.speaker, .a)
    XCTAssertEqual(viewModel.items.last?.transcript, "Hello")
    recognizer.sendFinal("Hello there")
    XCTAssertEqual(viewModel.state, .listening(.a))
    XCTAssertEqual(recognizer.stopCount, 0)
    viewModel.endTurn(.a)

    await waitUntil { viewModel.state == .ready }
    XCTAssertEqual(viewModel.items.last?.targetLanguage, viewModel.targetLanguageB)
    XCTAssertEqual(viewModel.state, .ready)
  }

  func testBTurnRoutesTranslationToALanguage() async {
    let recognizer = FakeSpeechRecognizer()
    let viewModel = readyViewModel(recognizer)

    viewModel.beginTurn(.b)
    recognizer.sendFinal("hello")
    XCTAssertEqual(viewModel.state, .listening(.b))
    viewModel.endTurn(.b)

    await waitUntil { viewModel.state == .ready }
    XCTAssertEqual(viewModel.items.last?.speaker, .b)
    XCTAssertEqual(viewModel.items.last?.targetLanguage, viewModel.targetLanguageA)
  }

  func testFinalBeforeReleaseDoesNotTranslateUntilRelease() async {
    let recognizer = FakeSpeechRecognizer()
    let viewModel = readyViewModel(recognizer)

    viewModel.beginTurn(.a)
    recognizer.sendFinal("Hello there")
    XCTAssertEqual(viewModel.state, .listening(.a))
    XCTAssertEqual(recognizer.stopCount, 0)

    viewModel.endTurn(.a)
    XCTAssertEqual(recognizer.finishCount, 1)

    await waitUntil { viewModel.state == .ready }
    XCTAssertEqual(viewModel.items.last?.translation, "Translated")
    viewModel.beginTurn(.b)
    XCTAssertEqual(viewModel.state, .listening(.b))
  }

  func testPartialAfterFinalKeepsPendingFinalForRelease() async {
    let recognizer = FakeSpeechRecognizer()
    let viewModel = readyViewModel(recognizer)

    viewModel.beginTurn(.a)
    recognizer.sendFinal("final transcript")
    recognizer.sendPartial("newer preview")
    XCTAssertEqual(viewModel.items.last?.transcript, "newer preview")
    XCTAssertEqual(viewModel.state, .listening(.a))

    viewModel.endTurn(.a)
    await waitUntil { viewModel.state == .ready }
    XCTAssertEqual(viewModel.items.last?.transcript, "final transcript")
    XCTAssertEqual(viewModel.state, .ready)
  }

  func testTapToggleStartsThenEndsSameSpeaker() {
    let recognizer = FakeSpeechRecognizer()
    let viewModel = readyViewModel(recognizer)

    viewModel.beginTurn(.a)
    viewModel.endTurn(.a)

    XCTAssertEqual(viewModel.state, .finalizing(.a))
  }

  func testOnDeviceSpeechRequestNeverAllowsNetworkFallback() {
    let request = SFSpeechAudioBufferRecognitionRequest()
    PlatformSpeechRecognizer.configure(request)
    XCTAssertTrue(request.requiresOnDeviceRecognition)
    XCTAssertTrue(request.shouldReportPartialResults)
  }

  func testMissingBuildCredentialIsRejected() {
    XCTAssertEqual(MelangeCredential.value(from: [:]), "")
    XCTAssertEqual(MelangeCredential.value(from: ["MelangePersonalKey": "$(MELANGE_PERSONAL_KEY)"]), "")
  }

  func testResponseAccumulatorThrowsForModelErrorCode() {
    var accumulator = TranslationResponseAccumulator()
    XCTAssertThrowsError(try accumulator.append(token: "", generatedTokens: 0, code: 7)) { error in
      XCTAssertEqual(error as? TranslationRuntimeError, .generationFailed(7))
    }
  }

  func testResponseAccumulatorRejectsEmptyOutput() {
    var accumulator = TranslationResponseAccumulator()
    XCTAssertFalse(try accumulator.append(token: "", generatedTokens: 0, code: 0))
    XCTAssertThrowsError(try accumulator.finalOutput()) { error in
      XCTAssertEqual(error as? TranslationRuntimeError, .emptyOutput)
    }
  }

  func testSessionLoadDisablesTurnsThenEnablesThemAfterRuntimeLoads() async {
    let recognizer = FakeSpeechRecognizer()
    let runtime = FakeTranslationRuntime(result: "Translated")
    let viewModel = RealtimeTranslateViewModel(
      state: .setup, speechRecognizer: recognizer, translationRuntime: runtime
    )

    viewModel.startSession()
    XCTAssertEqual(viewModel.state, .loadingModel(nil))
    XCTAssertFalse(viewModel.canEditLanguages)
    XCTAssertFalse(viewModel.canStartSession)
    await waitUntil { viewModel.state == .ready }
    XCTAssertTrue(viewModel.canEditLanguages)
    XCTAssertTrue(viewModel.isSessionLive)
    XCTAssertEqual(runtime.loadCount, 1)
  }

  func testLanguageChipsLockWhileAnUtteranceIsActiveAndUnlockAfterward() async {
    let recognizer = FakeSpeechRecognizer()
    let viewModel = readyViewModel(recognizer)

    XCTAssertTrue(viewModel.canEditLanguages)
    viewModel.beginTurn(.a)
    XCTAssertFalse(viewModel.canEditLanguages)
    recognizer.sendFinal("hello")
    viewModel.endTurn(.a)

    await waitUntil { viewModel.state == .ready }
    XCTAssertTrue(viewModel.canEditLanguages)
  }

  func testReadingLanguageChangeMidSessionAppliesWithoutReloadingTheModel() async {
    let recognizer = FakeSpeechRecognizer()
    let runtime = FakeTranslationRuntime(result: "Translated")
    let viewModel = readyViewModel(recognizer, runtime: runtime)

    XCTAssertEqual(viewModel.targetLanguageB, TargetLanguage.hyMT2Candidates[9])
    viewModel.targetLanguageB = .hyMT2Candidates[2]
    viewModel.beginTurn(.a)
    recognizer.sendFinal("hello")
    viewModel.endTurn(.a)

    await waitUntil { viewModel.state == .ready }
    XCTAssertEqual(viewModel.items.last?.targetLanguage, TargetLanguage.hyMT2Candidates[2])
    XCTAssertEqual(runtime.loadCount, 0)
  }

  func testSourceLanguageChangeMidSessionAppliesAtTheNextTurnStart() async {
    let recognizer = FakeSpeechRecognizer()
    let french = SpeechSourceLanguage(identifier: "fr-FR", name: "French (France)")
    recognizer.sourceLanguages = [french]
    let viewModel = readyViewModel(recognizer)

    viewModel.beginTurn(.a)
    recognizer.sendFinal("hello")
    viewModel.endTurn(.a)
    await waitUntil { viewModel.state == .ready }

    viewModel.sourceLanguageA = french
    viewModel.beginTurn(.a)

    XCTAssertEqual(recognizer.startedSources, [.automatic, french])
    XCTAssertEqual(viewModel.state, .listening(.a))
  }

  func testSessionLoadFailureShowsRetryState() async {
    let recognizer = FakeSpeechRecognizer()
    let runtime = FakeTranslationRuntime(loadError: TestError.failed)
    let viewModel = RealtimeTranslateViewModel(
      state: .setup, speechRecognizer: recognizer, translationRuntime: runtime
    )

    viewModel.startSession()
    await waitUntil { if case .modelLoadFailed = viewModel.state { return true }; return false }
    XCTAssertTrue(viewModel.canEditLanguages)
    XCTAssertTrue(viewModel.canStartSession)
    XCTAssertFalse(viewModel.isSessionLive)
    XCTAssertEqual(runtime.loadCount, 1)
  }

  func testEndSessionClosesRuntimeAndReturnsToTheIdleMainScreen() async {
    let recognizer = FakeSpeechRecognizer()
    let runtime = FakeTranslationRuntime(result: "Translated", closeDelayNanoseconds: 30_000_000)
    let item = ConversationItem(
      id: UUID(), speaker: .a, transcript: "Hello", targetLanguage: .hyMT2Candidates[1],
      translation: "Hello", state: .translated
    )
    let viewModel = RealtimeTranslateViewModel(
      state: .ready, items: [item], speechRecognizer: recognizer, translationRuntime: runtime
    )

    viewModel.endSession()
    XCTAssertEqual(viewModel.state, .endingSession)
    XCTAssertEqual(viewModel.items, [item])
    await waitUntil { runtime.closeCount == 1 }
    await waitUntil { viewModel.state == .setup }
    XCTAssertEqual(viewModel.state, .setup)
    XCTAssertTrue(viewModel.items.isEmpty)
    XCTAssertFalse(viewModel.isSessionLive)
    XCTAssertTrue(viewModel.canStartSession)
    XCTAssertTrue(viewModel.canEditLanguages)
  }

  func testActiveSpeakerReportsTheUtteranceOwnerForBlockedControlText() {
    XCTAssertEqual(SessionState.listening(.a).activeSpeaker, .a)
    XCTAssertEqual(SessionState.finalizing(.b).activeSpeaker, .b)
    XCTAssertEqual(SessionState.translating(.a).activeSpeaker, .a)
    XCTAssertNil(SessionState.ready.activeSpeaker)
    XCTAssertNil(SessionState.setup.activeSpeaker)
  }

  private func readyViewModel(
    _ recognizer: FakeSpeechRecognizer, runtime: FakeTranslationRuntime = FakeTranslationRuntime(result: "Translated")
  ) -> RealtimeTranslateViewModel {
    RealtimeTranslateViewModel(state: .ready, speechRecognizer: recognizer, translationRuntime: runtime)
  }

  private func waitUntil(_ condition: @escaping () -> Bool) async {
    for _ in 0 ..< 100 where !condition() {
      try? await Task.sleep(nanoseconds: 1_000_000)
    }
    XCTAssertTrue(condition())
  }
}

private enum TestError: Error { case failed }

@MainActor
private final class FakeSpeechRecognizer: SpeechRecognizing {
  private var onPartial: ((String) -> Void)?
  private var onFinal: ((String) -> Void)?
  var sourceLanguages: [SpeechSourceLanguage] = []
  private(set) var startedSources: [SpeechSourceLanguage] = []
  private(set) var finishCount = 0
  private(set) var stopCount = 0

  func requestPermissions() async -> SpeechPermission { .granted }
  func availableSourceLanguages() -> [SpeechSourceLanguage] { sourceLanguages }
  func start(source: SpeechSourceLanguage, onPartial: @escaping (String) -> Void,
             onFinal: @escaping (String) -> Void) throws {
    startedSources.append(source)
    self.onPartial = onPartial
    self.onFinal = onFinal
  }
  func finish() { finishCount += 1 }
  func stop() { stopCount += 1 }
  func sendPartial(_ transcript: String) { onPartial?(transcript) }
  func sendFinal(_ transcript: String) { onFinal?(transcript) }
}

private final class FakeTranslationRuntime: TranslationRuntime {
  let result: String
  let loadError: Error?
  let closeDelayNanoseconds: UInt64
  private(set) var loadCount = 0
  private(set) var closeCount = 0
  private(set) var prompts: [String] = []

  init(result: String = "", loadError: Error? = nil, closeDelayNanoseconds: UInt64 = 0) {
    self.result = result
    self.loadError = loadError
    self.closeDelayNanoseconds = closeDelayNanoseconds
  }

  func load(onProgress: @escaping @Sendable (Double) -> Void) async throws {
    loadCount += 1
    onProgress(0.5)
    if let loadError { throw loadError }
    onProgress(1)
  }

  func translate(prompt: String) async throws -> String {
    prompts.append(prompt)
    return result
  }

  func close() async {
    if closeDelayNanoseconds > 0 { try? await Task.sleep(nanoseconds: closeDelayNanoseconds) }
    closeCount += 1
  }
}
