import AVFAudio
import UIKit
import XCTest
import Speech
import ZeticMLange
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

  func testSpokenLanguageFollowsTheReadingLanguageWhenARecognizerMatches() {
    let recognizer = FakeSpeechRecognizer()
    recognizer.sourceLanguages = [
      SpeechSourceLanguage(identifier: "en-US", name: "English (United States)"),
      SpeechSourceLanguage(identifier: "ko-KR", name: "Korean (South Korea)"),
      SpeechSourceLanguage(identifier: "fr-BE", name: "French (Belgium)"),
      SpeechSourceLanguage(identifier: "fr-FR", name: "French (France)"),
    ]

    let viewModel = RealtimeTranslateViewModel(state: .ready, speechRecognizer: recognizer)

    XCTAssertEqual(viewModel.sourceLanguageA.identifier, "en-US")
    XCTAssertEqual(viewModel.sourceLanguageB.identifier, "ko-KR")

    viewModel.targetLanguageB = TargetLanguage(code: "fr", name: "French")
    XCTAssertEqual(viewModel.sourceLanguageB.identifier, "fr-FR")
  }

  func testMatchedSourceLanguagePrefersImpliedVariantsAndScripts() {
    let languages = [
      SpeechSourceLanguage.automatic,
      SpeechSourceLanguage(identifier: "zh-CN", name: "Chinese (China)"),
      SpeechSourceLanguage(identifier: "zh-TW", name: "Chinese (Taiwan)"),
      SpeechSourceLanguage(identifier: "en-GB", name: "English (United Kingdom)"),
      SpeechSourceLanguage(identifier: "en-US", name: "English (United States)"),
    ]

    XCTAssertEqual(
      RealtimeTranslateViewModel.matchedSourceLanguage(
        for: TargetLanguage(code: "zh-Hant", name: "Traditional Chinese"), in: languages
      )?.identifier, "zh-TW")
    XCTAssertEqual(
      RealtimeTranslateViewModel.matchedSourceLanguage(
        for: TargetLanguage(code: "en", name: "English"), in: languages
      )?.identifier, "en-US")
    XCTAssertNil(
      RealtimeTranslateViewModel.matchedSourceLanguage(
        for: TargetLanguage(code: "th", name: "Thai"), in: languages))
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

  func testEndSessionKeepsTheModelLoadedAndReturnsToTheIdleMainScreen() async {
    let recognizer = FakeSpeechRecognizer()
    let runtime = FakeTranslationRuntime(result: "Translated")
    let item = ConversationItem(
      id: UUID(), speaker: .a, transcript: "Hello", targetLanguage: .hyMT2Candidates[1],
      translation: "Hello", state: .translated
    )
    let viewModel = RealtimeTranslateViewModel(
      state: .ready, items: [item], speechRecognizer: recognizer, translationRuntime: runtime
    )

    viewModel.endSession()
    XCTAssertEqual(viewModel.state, .setup)
    XCTAssertEqual(runtime.closeCount, 0)
    XCTAssertTrue(viewModel.items.isEmpty)
    XCTAssertFalse(viewModel.isSessionLive)
    XCTAssertTrue(viewModel.canStartSession)
    XCTAssertTrue(viewModel.canEditLanguages)

    viewModel.startSession()
    await waitUntil { viewModel.state == .ready }
    XCTAssertEqual(runtime.closeCount, 0)
  }

  // MARK: - A turn that recognizes nothing

  /// `finalizing` has exactly one exit, and it is a finalized transcript. An empty final is what
  /// the platform recognizer synthesizes for every recognition failure that is not a cancellation,
  /// and a silent turn produces one on its own, so dropping it there leaves the session stranded:
  /// every control blocked, and the only way out the one that wipes the conversation.
  func testATurnThatRecognizesNothingReturnsToReadyWithANoteRatherThanStranding() {
    let recognizer = FakeSpeechRecognizer()
    let earlier = previewTranslatedItem
    let viewModel = RealtimeTranslateViewModel(
      state: .ready, items: [earlier], speechRecognizer: recognizer,
      translationRuntime: FakeTranslationRuntime(result: "Translated"),
      speechOutput: FakeSpeechOutput(), audioInterruptions: FakeAudioInterruptions()
    )

    // While the microphone is still open an empty final means nothing yet, so it is dropped.
    viewModel.beginTurn(.a)
    recognizer.sendFinal("")
    XCTAssertEqual(viewModel.state, .listening(.a))
    XCTAssertNil(viewModel.notice)

    viewModel.endTurn(.a)
    XCTAssertEqual(viewModel.state, .finalizing(.a))

    // Released, the same empty final is the only answer that will ever come.
    recognizer.sendFinal("")

    XCTAssertEqual(viewModel.state, .ready)
    XCTAssertTrue(viewModel.isSessionLive)
    XCTAssertEqual(viewModel.notice, "No speech was recognized. Tap to talk again.")
    XCTAssertFalse(EmptyTurnCopy.notice.contains("\u{2014}"))
    // The bubble that was going to hold the utterance goes; every earlier one stays.
    XCTAssertEqual(viewModel.items.map(\.id), [earlier.id])

    // And the next turn works, which is the whole point of not stranding.
    viewModel.beginTurn(.b)
    XCTAssertEqual(viewModel.state, .listening(.b))
    XCTAssertNil(viewModel.notice)
  }

  // MARK: - Ending a session

  /// Cancelling the task that was watching a load is not the same as stopping the load, and a
  /// translation nobody is waiting for is a model still generating tokens after the session that
  /// asked for it is over.
  func testEndingASessionStopsTheLoadAndTheTranslationItStarted() async {
    let recognizer = FakeSpeechRecognizer()
    let loading = FakeTranslationRuntime(result: "Bonjour", loadDelayNanoseconds: 2_000_000_000)
    let viewModel = RealtimeTranslateViewModel(
      state: .setup, speechRecognizer: recognizer, translationRuntime: loading
    )

    viewModel.startSession()
    XCTAssertEqual(viewModel.state, .loadingModel(nil))
    viewModel.endSession()

    XCTAssertEqual(loading.cancelLoadCount, 1)
    XCTAssertEqual(viewModel.state, .setup)
    await waitUntil { loading.loadCancelled }
    XCTAssertFalse(loading.isModelResident)

    let translating = FakeTranslationRuntime(result: "Bonjour", translateDelayNanoseconds: 2_000_000_000)
    let live = readyViewModel(recognizer, runtime: translating)
    live.beginTurn(.a)
    recognizer.sendFinal("Good morning")
    live.endTurn(.a)
    await waitUntil { translating.translateStarted }

    live.endSession()

    await waitUntil { translating.translateCancelled }
    XCTAssertEqual(live.state, .setup)
    XCTAssertTrue(live.items.isEmpty)
  }

  func testActiveSpeakerReportsTheUtteranceOwnerForBlockedControlText() {
    XCTAssertEqual(SessionState.listening(.a).activeSpeaker, .a)
    XCTAssertEqual(SessionState.finalizing(.b).activeSpeaker, .b)
    XCTAssertEqual(SessionState.translating(.a).activeSpeaker, .a)
    XCTAssertNil(SessionState.ready.activeSpeaker)
    XCTAssertNil(SessionState.setup.activeSpeaker)
  }

  func testDiscoverArchiveReturnsTheCompleteArchiveNamedByTheCacheIndex() throws {
    let root = try makeCacheFixture()

    let archive = LocalModelStore.discoverArchive(forModelName: "SJ_zetic/Hy-MT2-1.8B", cacheRoot: root)

    XCTAssertEqual(archive?.artifactID, "llmTargetModel-c488c23ffebf7fd0")
    XCTAssertEqual(archive?.modelKey, "aaaa")
    XCTAssertEqual(archive?.url.lastPathComponent, "Hy_MT2_1.ztc")
  }

  func testDiscoverArchiveSkipsAnArchiveShorterThanTheIndexedByteCount() throws {
    let root = try makeCacheFixture(archiveByteCount: 4, indexedByteCount: 8)

    XCTAssertNil(LocalModelStore.discoverArchive(forModelName: "SJ_zetic/Hy-MT2-1.8B", cacheRoot: root))
  }

  func testDiscoverArchiveReturnsNilForAnUnrecognisedIndexInsteadOfFailing() throws {
    let root = try makeCacheFixture()
    try "{\"schemaVersion\":99,\"artifacts\":\"unexpected\"}"
      .write(to: root.appendingPathComponent("cache-index.json"), atomically: true, encoding: .utf8)

    XCTAssertNil(LocalModelStore.discoverArchive(forModelName: "SJ_zetic/Hy-MT2-1.8B", cacheRoot: root))
    XCTAssertNil(LocalModelStore.discoverArchive(forModelName: "SJ_zetic/Hy-MT2-1.8B", cacheRoot: root.appendingPathComponent("missing")))
  }

  func testSecretKeyHexComesFromTheBackendSelectionRecordForThatArtifact() throws {
    let root = try makeCacheFixture()

    XCTAssertEqual(LocalModelStore.secretKeyHex(forArtifactID: "llmTargetModel-c488c23ffebf7fd0", cacheRoot: root),
                   String(repeating: "0", count: 64))
    XCTAssertNil(LocalModelStore.secretKeyHex(forArtifactID: "llmTargetModel-0000000000000000", cacheRoot: root))
  }

  func testSweepOrphansRemovesOnlyPartialDownloadsAndEmptyUnindexedArtifactDirectories() throws {
    let root = try makeCacheFixture()
    let manager = FileManager.default
    let models = root.appendingPathComponent("artifacts/aaaa", isDirectory: true)
    let kept = [
      models.appendingPathComponent("llmTargetModel-c488c23ffebf7fd0"),
      models.appendingPathComponent("llmTargetModel-ABCDEF0123456789"),
      models.appendingPathComponent("llmTargetModel-short"),
      root.appendingPathComponent("staging-locks")
    ]
    for directory in kept.dropFirst() {
      try manager.createDirectory(at: directory, withIntermediateDirectories: true)
    }
    let swept = models.appendingPathComponent("llmTargetModel-0123456789abcdef")
    try manager.createDirectory(at: swept, withIntermediateDirectories: true)
    let temporary = root.appendingPathComponent("tmp", isDirectory: true)
    try manager.createDirectory(at: temporary, withIntermediateDirectories: true)
    let partial = temporary.appendingPathComponent("CFNetworkDownload_ab12cd.tmp")
    let unrelated = temporary.appendingPathComponent("keep-me.tmp")
    try Data([0]).write(to: partial)
    try Data([0]).write(to: unrelated)

    LocalModelStore.sweepOrphans(cacheRoot: root)

    XCTAssertFalse(manager.fileExists(atPath: swept.path))
    XCTAssertFalse(manager.fileExists(atPath: partial.path))
    XCTAssertTrue(manager.fileExists(atPath: unrelated.path))
    for directory in kept { XCTAssertTrue(manager.fileExists(atPath: directory.path), directory.lastPathComponent) }
  }

  /// The app's temporary directory is `URLSession`'s too, and a `CFNetworkDownload_*.tmp` sitting
  /// in it is as likely to be the resumable remains of this model's own 1.9 GB transfer as it is
  /// to be an abandoned one. The sweep runs at the top of every load, so deleting from there turns
  /// a download that could resume into one that starts again at zero.
  func testSweepOrphansLeavesPartialDownloadsOutsideTheCacheRootAlone() throws {
    let root = try makeCacheFixture()
    let manager = FileManager.default
    // The real shared directory, because that is the one the sweep used to reach into. The name
    // is this test's own, and it is removed however the test ends.
    let sharedPartial = manager.temporaryDirectory
      .appendingPathComponent("CFNetworkDownload_\(UUID().uuidString).tmp")
    try Data([0]).write(to: sharedPartial)
    addTeardownBlock { try? manager.removeItem(at: sharedPartial) }
    let ownPartial = root.appendingPathComponent("tmp/CFNetworkDownload_ef34ab.tmp")
    try manager.createDirectory(at: ownPartial.deletingLastPathComponent(),
                                withIntermediateDirectories: true)
    try Data([0]).write(to: ownPartial)

    LocalModelStore.sweepOrphans(cacheRoot: root)

    XCTAssertTrue(manager.fileExists(atPath: sharedPartial.path))
    XCTAssertFalse(manager.fileExists(atPath: ownPartial.path))
  }

  /// The two index readings are two views of one file. An artifact whose only stored file is the
  /// extracted `.gguf` is absent from the `.ztc` reading, and counting only that reading makes the
  /// live model's own directory look like an id nobody claims.
  func testSweepOrphansCountsAnArtifactKnownOnlyToTheModuleIndexAsKnown() throws {
    let root = try makeCacheFixture(moduleByteCount: 16)
    let manager = FileManager.default
    let directory = root.appendingPathComponent("artifacts/aaaa/llmTargetModel-c488c23ffebf7fd0")
    // An artifact the SDK has extracted and tidied up after: its index record names the `.gguf`
    // and nothing else, so the archive reading of the same file does not know the id at all.
    let indexURL = root.appendingPathComponent("cache-index.json")
    var index = try XCTUnwrap(
      JSONSerialization.jsonObject(with: Data(contentsOf: indexURL)) as? [String: Any]
    )
    var artifacts = try XCTUnwrap(index["artifacts"] as? [[String: Any]])
    artifacts[0]["storedFiles"] = (artifacts[0]["storedFiles"] as? [[String: Any]])?
      .filter { ($0["relativePath"] as? String)?.hasSuffix(".gguf") == true }
    index["artifacts"] = artifacts
    try JSONSerialization.data(withJSONObject: index).write(to: indexURL)
    XCTAssertNotNil(LocalModelStore.discoverExtractedModule(forModelName: "SJ_zetic/Hy-MT2-1.8B",
                                                            cacheRoot: root))
    // The sweep only removes empty directories, so the live artifact is emptied but kept: this is
    // the shape a mid-extraction cache has, and the id is the only thing telling them apart.
    for file in try manager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) {
      try manager.removeItem(at: file)
    }

    LocalModelStore.sweepOrphans(cacheRoot: root)

    XCTAssertTrue(manager.fileExists(atPath: directory.path))
  }

  // MARK: - Translation runtime lifecycle

  /// The interleaving: `load` starts and reaches the SDK init, `close` runs while the model is
  /// still being built, and only then does the init return. The memoized task wrote its model back
  /// unconditionally, so the close freed nothing and 1.9 GB landed in a runtime nobody wanted.
  func testClosingDuringALoadReleasesTheModelInsteadOfInstallingItIntoAClosedRuntime() async {
    let model = SpyLanguageModel(output: "Bonjour")
    let building = AsyncGate()
    let finish = AsyncGate()
    let runtime = MelangeTranslationRuntime(personalKey: "test-key", modelFactory: { _ in
      await building.open()
      await finish.wait()
      return model
    })

    let load = Task { try await runtime.load { _ in } }
    await building.wait()
    await runtime.close()
    await finish.open()
    _ = try? await load.value

    XCTAssertEqual(model.closeCount, 1)
    XCTAssertFalse(runtime.isModelResident)
    do {
      _ = try await runtime.translate(prompt: "anything")
      XCTFail("a closed runtime has no model to translate with")
    } catch {
      XCTAssertEqual(error as? TranslationRuntimeError, .modelNotLoaded)
    }
  }

  /// The other half of the same race: the finished memo. A load task left in place after a close
  /// makes the next `load` return success immediately with no model behind it, so the session
  /// reaches `ready` and the first translation throws `modelNotLoaded`.
  func testALoadAbandonedByACloseLeavesNoMemoThatFakesTheNextOne() async throws {
    let abandoned = SpyLanguageModel(output: "first")
    let adopted = SpyLanguageModel(output: "Bonjour")
    let finish = AsyncGate()
    let building = AsyncGate()
    let attempts = Counter()
    let runtime = MelangeTranslationRuntime(personalKey: "test-key", modelFactory: { _ in
      guard attempts.increment() == 1 else { return adopted }
      await building.open()
      await finish.wait()
      return abandoned
    })

    let load = Task { try await runtime.load { _ in } }
    await building.wait()
    await runtime.close()
    await finish.open()
    _ = try? await load.value

    try await runtime.load { _ in }

    XCTAssertTrue(runtime.isModelResident)
    let translation = try await runtime.translate(prompt: "Good morning")
    XCTAssertEqual(translation, "Bonjour")
    XCTAssertEqual(abandoned.closeCount, 1)
    XCTAssertEqual(adopted.closeCount, 0)
  }

  /// Cancelling a load stops the transfer and forgets it, and leaves the runtime able to load
  /// again: someone who ends a session mid-download and starts another one gets a real load.
  func testCancellingALoadForgetsItSoTheNextStartLoadsForReal() async throws {
    let model = SpyLanguageModel(output: "Bonjour")
    let finish = AsyncGate()
    let building = AsyncGate()
    let attempts = Counter()
    let runtime = MelangeTranslationRuntime(personalKey: "test-key", modelFactory: { _ in
      if attempts.increment() == 1 {
        await building.open()
        await finish.wait()
      }
      return model
    })

    let load = Task { try await runtime.load { _ in } }
    await building.wait()
    runtime.cancelLoad()
    await finish.open()
    _ = try? await load.value
    XCTAssertFalse(runtime.isModelResident)

    try await runtime.load { _ in }

    XCTAssertEqual(attempts.value, 2)
    XCTAssertTrue(runtime.isModelResident)
  }

  /// `deinit` runs exactly when the last strong reference goes away, which can be inside a block
  /// running on the runtime's own queue. Waiting for that queue from inside `deinit` is a deadlock,
  /// so the release is handed over and never waited on. The busy queue here is what a load looks
  /// like: occupied for seconds at a time.
  func testReleasingAModelHandsItToTheQueueRatherThanWaitingForIt() {
    let queue = DispatchQueue(label: "ai.zetic.turntranslate.tests.release")
    let model = SpyLanguageModel(output: "Bonjour")
    let released = expectation(description: "the model is released once the queue drains")
    model.onClose = { released.fulfill() }
    let busy = DispatchSemaphore(value: 0)
    queue.async { busy.wait() }

    let started = Date()
    MelangeTranslationRuntime.release(model, on: queue)
    let elapsed = Date().timeIntervalSince(started)

    XCTAssertLessThan(elapsed, 0.5, "the release waited for the queue")
    XCTAssertEqual(model.closeCount, 0)
    busy.signal()
    wait(for: [released], timeout: 2)
    XCTAssertEqual(model.cleanUpCount, 1)
    XCTAssertEqual(model.closeCount, 1)
  }

  // MARK: - Recognition locales

  /// About 280 ms of `SFSpeechRecognizer` work that used to run on the main actor inside a view
  /// model's `init`, before the first frame, and again after a permission grant. It cannot change
  /// while the app is running, so it is read once and reused.
  func testTheRecognitionLocaleListIsComputedOnceAndReusedAfterwards() {
    let cache = SourceLanguageCache()
    let french = SpeechSourceLanguage(identifier: "fr-FR", name: "French (France)")
    var computations = 0

    XCTAssertTrue(cache.current.isEmpty)
    XCTAssertEqual(cache.fill { computations += 1; return [french] }, [french])
    XCTAssertEqual(cache.fill { computations += 1; return [] }, [french])
    XCTAssertEqual(cache.current, [french])
    XCTAssertEqual(computations, 1)
  }

  /// The list arrives after `init` rather than during it, and adopting it re-runs the chip
  /// coupling that could not run while nothing was known. A speaker whose spoken language has
  /// since been chosen by hand keeps it.
  func testTheLocaleListArrivesAfterInitAndStillAlignsTheChips() async {
    let recognizer = FakeSpeechRecognizer()
    let french = SpeechSourceLanguage(identifier: "fr-FR", name: "French (France)")
    let korean = SpeechSourceLanguage(identifier: "ko-KR", name: "Korean")
    // Known only to the reader that runs off the main actor, which is what a cold launch looks
    // like: nothing has asked the platform yet, so `init` has nothing to seed from.
    recognizer.deferredSourceLanguages = [french, korean]

    let viewModel = RealtimeTranslateViewModel(state: .ready, speechRecognizer: recognizer)

    // The first frame is not waiting for any of it.
    XCTAssertEqual(viewModel.availableSourceLanguages, [.automatic])
    XCTAssertEqual(viewModel.sourceLanguageB, .automatic)

    await waitUntil { viewModel.availableSourceLanguages.count == 3 }
    XCTAssertEqual(viewModel.availableSourceLanguages, [.automatic, french, korean])
    // B reads Korean and was still automatic, so it follows its chip. A reads English, which no
    // recognizer here offers, so it stays automatic rather than guessing.
    XCTAssertEqual(viewModel.sourceLanguageB, korean)
    XCTAssertEqual(viewModel.sourceLanguageA, .automatic)
  }

  // MARK: - Root view construction

  /// SwiftUI rebuilds a root view struct freely and keeps only the first `StateObject` it is
  /// given. An eagerly evaluated default argument makes every one of those rebuilds construct a
  /// recognizer, a translation runtime, a set of notification registrations and an `NWPathMonitor`
  /// and then throw them away.
  @MainActor
  func testTheRootViewBuildsNeitherCollaboratorUntilSwiftUIInstallsIt() {
    let built = Counter()
    let firstRunBuilt = Counter()

    _ = RealtimeTranslateRootView(
      viewModel: Self.countedViewModel(built),
      firstRun: Self.countedFirstRun(firstRunBuilt)
    )

    XCTAssertEqual(built.value, 0)
    XCTAssertEqual(firstRunBuilt.value, 0)
  }

  private static func countedViewModel(_ counter: Counter) -> RealtimeTranslateViewModel {
    _ = counter.increment()
    return RealtimeTranslateViewModel(state: .setup, speechRecognizer: FakeSpeechRecognizer())
  }

  private static func countedFirstRun(_ counter: Counter) -> FirstRunModel {
    _ = counter.increment()
    return FirstRunModel(path: FixedNetworkPath(.unrestricted), hasLocalModel: { true })
  }

  func testSettingsDrawerOpensFromTheWordmarkAndCloses() {
    let model = SettingsDrawerModel(appInfo: .main, pasteboard: FakePasteboard())

    XCTAssertFalse(model.isOpen)
    model.open()
    XCTAssertTrue(model.isOpen)
    model.close()
    XCTAssertFalse(model.isOpen)
  }

  func testContactRowCopiesTheAddressAndAnnouncesTheToast() async {
    let pasteboard = FakePasteboard()
    var announcements: [String] = []
    let model = SettingsDrawerModel(
      appInfo: .main, pasteboard: pasteboard, toastDuration: 0.02, openURL: { _ in },
      announce: { announcements.append($0) }
    )

    model.copyContactEmail()

    XCTAssertEqual(SettingsDrawerModel.contactEmail, "contact@zetic.ai")
    XCTAssertEqual(pasteboard.written, ["contact@zetic.ai"])
    XCTAssertEqual(model.toast, "Email address copied")
    XCTAssertEqual(announcements, ["Email address copied"])

    await waitUntil { model.toast == nil }
  }

  func testVisitRowOpensTheZeticSite() {
    var opened: [URL] = []
    let model = SettingsDrawerModel(
      appInfo: .main, pasteboard: FakePasteboard(), openURL: { opened.append($0) }
    )

    model.openWebsite()

    XCTAssertEqual(opened.map(\.absoluteString), ["https://zetic.ai"])
  }

  func testAboutSectionReadsTheBundleNameAndVersion() {
    let info = AppInfo(info: [
      "CFBundleDisplayName": "Turn Translate", "CFBundleShortVersionString": "1.2", "CFBundleVersion": "7"
    ])

    XCTAssertEqual(info.displayName, "Turn Translate")
    XCTAssertEqual(info.versionLine, "Version 1.2 (7)")
    XCTAssertEqual(AppInfo(info: ["CFBundleName": "RealtimeTranslate"]).displayName, "RealtimeTranslate")
    XCTAssertEqual(AppInfo(info: nil).displayName, "Turn Translate")
    XCTAssertEqual(AppInfo(info: Bundle.main.infoDictionary).displayName, "Turn Translate")
  }

  // MARK: - First run

  func testWelcomeComesFirstAndThePrimingOnlyWhilePermissionIsUnanswered() {
    XCTAssertEqual(
      FirstRunStep.step(welcomeSeen: false, primingSeen: false, permissionNeeded: true), .welcome)
    XCTAssertEqual(
      FirstRunStep.step(welcomeSeen: false, primingSeen: true, permissionNeeded: false), .welcome)
    XCTAssertEqual(
      FirstRunStep.step(welcomeSeen: true, primingSeen: false, permissionNeeded: true),
      .permissionPriming)
    // A returning user whose permissions are already granted skips the priming silently.
    XCTAssertEqual(
      FirstRunStep.step(welcomeSeen: true, primingSeen: false, permissionNeeded: false), .none)
    XCTAssertEqual(
      FirstRunStep.step(welcomeSeen: true, primingSeen: true, permissionNeeded: true), .none)
  }

  func testConsentIsSkippedWhenTheModelIsAlreadyOnDiskAndAskedWhenItIsNot() {
    XCTAssertEqual(
      ModelDownloadConsent.decision(hasLocalModel: true, cost: .unrestricted), .startImmediately)
    // A local model means no transfer at all, so an expensive path is beside the point.
    XCTAssertEqual(
      ModelDownloadConsent.decision(hasLocalModel: true, cost: .expensive), .startImmediately)
    XCTAssertEqual(
      ModelDownloadConsent.decision(hasLocalModel: false, cost: .unrestricted),
      .ask(cellularWarning: false))
    XCTAssertEqual(
      ModelDownloadConsent.decision(hasLocalModel: false, cost: .expensive),
      .ask(cellularWarning: true))
    XCTAssertEqual(
      ModelDownloadConsent.decision(hasLocalModel: false, cost: .constrained),
      .ask(cellularWarning: true))
  }

  func testSessionStartRunsStraightThroughWhenTheModelIsLocal() {
    var starts = 0
    let firstRun = FirstRunModel(path: FixedNetworkPath(.expensive), hasLocalModel: { true })

    firstRun.requestSessionStart { starts += 1 }

    XCTAssertEqual(starts, 1)
    XCTAssertNil(firstRun.consent)
  }

  func testSessionStartHoldsForConsentAndRunsOnlyWhenAccepted() {
    var starts = 0
    // The key is stated rather than read: a simulator build carries no Melange personal key, and a
    // build that cannot download at all is a different decision (see the test further down).
    let firstRun = FirstRunModel(path: FixedNetworkPath(.expensive), hasLocalModel: { false },
                                 hasPersonalKey: { true })

    firstRun.requestSessionStart { starts += 1 }
    XCTAssertEqual(starts, 0)
    XCTAssertEqual(firstRun.consent, FirstRunModel.ConsentPrompt(cellularWarning: true))

    firstRun.acceptConsent()
    XCTAssertEqual(starts, 1)
    XCTAssertNil(firstRun.consent)
  }

  /// A build with no Melange personal key cannot download anything. Offering `Download now`
  /// promises a 1.9 GB transfer that ends a frame later in the missing-key failure, so the start
  /// runs instead and that failure is reported where every other model failure is: the banner.
  func testConsentIsNotOfferedOnABuildThatCannotDownloadAnything() {
    XCTAssertEqual(
      ModelDownloadConsent.decision(hasLocalModel: false, cost: .unrestricted, hasPersonalKey: false),
      .startImmediately
    )
    XCTAssertEqual(
      ModelDownloadConsent.decision(hasLocalModel: false, cost: .expensive, hasPersonalKey: false),
      .startImmediately
    )
    XCTAssertEqual(
      ModelDownloadConsent.decision(hasLocalModel: false, cost: .expensive, hasPersonalKey: true),
      .ask(cellularWarning: true)
    )

    let firstRun = FirstRunModel(path: FixedNetworkPath(.expensive), hasLocalModel: { false },
                                 hasPersonalKey: { false })
    var started = 0
    firstRun.requestSessionStart { started += 1 }

    XCTAssertEqual(started, 1)
    XCTAssertNil(firstRun.consent)
  }

  func testDecliningConsentDismissesTheStepWithoutStartingTheDownload() {
    var starts = 0
    let firstRun = FirstRunModel(path: FixedNetworkPath(.unrestricted), hasLocalModel: { false },
                                 hasPersonalKey: { true })

    firstRun.requestSessionStart { starts += 1 }
    XCTAssertEqual(firstRun.consent, FirstRunModel.ConsentPrompt(cellularWarning: false))
    firstRun.declineConsent()

    XCTAssertEqual(starts, 0)
    XCTAssertNil(firstRun.consent)
    // The declined start is dropped, not queued behind the next one.
    firstRun.acceptConsent()
    XCTAssertEqual(starts, 0)
  }

  func testDownloadProgressIsNamedOnlyWhileBytesAreActuallyMoving() {
    XCTAssertEqual(ModelPreparationStatus.status(for: nil).headline, "Preparing translation model")
    // The status strip is driven from the same status, so the two lines cannot disagree.
    XCTAssertEqual(SessionState.loadingModel(nil).title, "Preparing translation model")
    XCTAssertEqual(SessionState.loadingModel(0.32).title, "Downloading translation model 32%")
    XCTAssertNil(ModelPreparationStatus.status(for: nil).progress)
    XCTAssertNil(ModelPreparationStatus.status(for: nil).detail)
    // 0 and 1 are the local-load bookends, not a download in flight.
    XCTAssertFalse(ModelPreparationStatus.status(for: 0).isDownloading)
    XCTAssertFalse(ModelPreparationStatus.status(for: 1).isDownloading)

    let downloading = ModelPreparationStatus.status(for: 0.32)
    XCTAssertTrue(downloading.isDownloading)
    XCTAssertEqual(downloading.headline, "Downloading translation model 32%")
    XCTAssertEqual(downloading.detail, "610.7 MB of 1.91 GB")
    XCTAssertEqual(ModelPreparationStatus.status(for: 0.5).detail, "954.3 MB of 1.91 GB")
    XCTAssertEqual(ModelPreparationStatus.status(for: 0.95).headline,
                   "Downloading translation model 95%")
    XCTAssertEqual(ModelPreparationStatus.status(for: 0.95).detail, "1.81 GB of 1.91 GB")
  }

  func testLaunchArgumentsForceEachFirstRunStateAndResetTheFlags() throws {
    let suite = "first-run-\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    addTeardownBlock { defaults.removePersistentDomain(forName: suite) }

    FirstRunDefaults.applyLaunchArguments(["-firstRun", "returning"], to: defaults)
    XCTAssertTrue(defaults.bool(forKey: FirstRunDefaults.welcomeSeenKey))
    XCTAssertTrue(defaults.bool(forKey: FirstRunDefaults.permissionPrimingSeenKey))

    FirstRunDefaults.applyLaunchArguments(["-resetFirstRun"], to: defaults)
    XCTAssertFalse(defaults.bool(forKey: FirstRunDefaults.welcomeSeenKey))
    XCTAssertFalse(defaults.bool(forKey: FirstRunDefaults.permissionPrimingSeenKey))

    FirstRunDefaults.applyLaunchArguments(["-firstRun", "consentNeeded"], to: defaults)
    XCTAssertTrue(defaults.bool(forKey: FirstRunDefaults.welcomeSeenKey))
    FirstRunDefaults.applyLaunchArguments(["-firstRun", "fresh"], to: defaults)
    XCTAssertFalse(defaults.bool(forKey: FirstRunDefaults.welcomeSeenKey))

    XCTAssertEqual(FirstRunDefaults.value(named: "-uiState", in: ["-uiState", "ready"]), "ready")
    XCTAssertNil(FirstRunDefaults.value(named: "-uiState", in: ["-uiState"]))
  }

  func testConsentNeededLaunchArgumentForcesAMissingModelAndACellularPath() {
    let consentNeeded = FirstRunModel.fromLaunchArguments(["-firstRun", "consentNeeded", "-firstRunCellular"])
    consentNeeded.requestSessionStart {}
    XCTAssertEqual(consentNeeded.consent, FirstRunModel.ConsentPrompt(cellularWarning: true))

    var starts = 0
    let returning = FirstRunModel.fromLaunchArguments(["-firstRun", "returning"])
    returning.requestSessionStart { starts += 1 }
    XCTAssertNil(returning.consent)
    XCTAssertEqual(starts, 1)
  }

  func testAlreadyGrantedPermissionSkipsThePrimingAndOpensTheIdleScreen() {
    let recognizer = FakeSpeechRecognizer()
    recognizer.permission = .required
    let viewModel = RealtimeTranslateViewModel(
      state: .permissionRequired, speechRecognizer: recognizer,
      translationRuntime: FakeTranslationRuntime()
    )

    XCTAssertTrue(viewModel.needsPermissionPriming)
    viewModel.adoptExistingPermission()
    XCTAssertEqual(viewModel.state, .permissionRequired)

    recognizer.permission = .granted
    viewModel.adoptExistingPermission()

    XCTAssertFalse(viewModel.needsPermissionPriming)
    XCTAssertEqual(viewModel.state, .setup)
  }

  func testAdoptingPermissionNeverDisturbsAStateTheAppHasMovedPast() {
    let recognizer = FakeSpeechRecognizer()
    let viewModel = RealtimeTranslateViewModel(
      state: .ready, speechRecognizer: recognizer, translationRuntime: FakeTranslationRuntime()
    )

    viewModel.adoptExistingPermission()

    XCTAssertEqual(viewModel.state, .ready)
  }

  func testFirstRunCopyUsesNoEmDash() {
    let copy = [
      FirstRunCopy.welcomeTitle, FirstRunCopy.welcomeTagline, FirstRunCopy.welcomePrivacy,
      FirstRunCopy.welcomeAction, FirstRunCopy.primingTitle, FirstRunCopy.primingMicrophone,
      FirstRunCopy.primingSpeech, FirstRunCopy.primingPrivacy, FirstRunCopy.primingNext,
      FirstRunCopy.primingAction, FirstRunCopy.primingDecline, FirstRunCopy.consentTitle,
      FirstRunCopy.consentSize, FirstRunCopy.consentOnce, FirstRunCopy.consentCellular,
      FirstRunCopy.consentAction, FirstRunCopy.consentDecline, FirstRunCopy.preparingModel,
      FirstRunCopy.downloadingModel
    ]

    for line in copy {
      XCTAssertFalse(line.contains("\u{2014}"), line)
      XCTAssertFalse(line.contains("\u{2013}"), line)
      XCTAssertFalse(line.isEmpty)
    }
    XCTAssertEqual(FirstRunCopy.consentSize, "The translation model is 1.91 GB.")
  }

  // MARK: - Session comfort

  func testScreenStaysAwakeExactlyWhileASessionIsLive() {
    let live: [SessionState] = [
      .ready, .listening(.a), .listening(.b), .finalizing(.a), .translating(.b), .error(.runtime("nope"))
    ]
    let idle: [SessionState] = [
      .permissionRequired, .setup, .loadingModel(nil), .loadingModel(0.5),
      .modelLoadFailed("nope")
    ]

    for state in live {
      XCTAssertTrue(ScreenAwakePolicy.shouldKeepAwake(state: state, isForeground: true), "\(state)")
      // Backgrounding hands the idle timer back whatever the session is doing.
      XCTAssertFalse(ScreenAwakePolicy.shouldKeepAwake(state: state, isForeground: false), "\(state)")
    }
    for state in idle {
      XCTAssertFalse(ScreenAwakePolicy.shouldKeepAwake(state: state, isForeground: true), "\(state)")
      XCTAssertFalse(ScreenAwakePolicy.shouldKeepAwake(state: state, isForeground: false), "\(state)")
    }
  }

  func testKeepAwakeDecisionMatchesTheLiveSessionFlagTheControlsUse() {
    let viewModel = RealtimeTranslateViewModel(
      state: .ready, speechRecognizer: FakeSpeechRecognizer(), translationRuntime: FakeTranslationRuntime()
    )

    XCTAssertTrue(viewModel.isSessionLive)
    XCTAssertEqual(
      viewModel.isSessionLive,
      ScreenAwakePolicy.shouldKeepAwake(state: .ready, isForeground: true)
    )
  }

  func testIdleTimerIsOnlyWrittenWhenTheDecisionActuallyChanges() {
    let timer = FakeIdleTimer()
    let controller = ScreenAwakeController(idleTimer: timer)

    controller.update(state: .setup, isForeground: true)
    XCTAssertEqual(timer.written, [])

    controller.update(state: .ready, isForeground: true)
    // A live session redraws on every partial transcript; the value is written once, not per frame.
    controller.update(state: .listening(.a), isForeground: true)
    controller.update(state: .translating(.a), isForeground: true)
    XCTAssertEqual(timer.written, [true])
    XCTAssertTrue(controller.isKeepingAwake)

    controller.update(state: .listening(.a), isForeground: false)
    XCTAssertEqual(timer.written, [true, false])
    XCTAssertFalse(controller.isKeepingAwake)

    controller.update(state: .listening(.a), isForeground: true)
    controller.release()
    XCTAssertEqual(timer.written, [true, false, true, false])
    controller.release()
    XCTAssertEqual(timer.written, [true, false, true, false])
  }

  func testHapticEventsMapToSubtleFeedbackAndOnlyOneErrorNotification() {
    XCTAssertEqual(HapticEvent.turnBegan.feedback, .impact(.medium))
    XCTAssertEqual(HapticEvent.turnEnded.feedback, .impact(.light))
    XCTAssertEqual(HapticEvent.translationDelivered.feedback, .impact(.soft))
    XCTAssertEqual(HapticEvent.sessionError.feedback, .notification(.error))
  }

  func testATurnTapsOnPressReleaseAndDelivery() async {
    let haptics = FakeHaptics()
    let recognizer = FakeSpeechRecognizer()
    let viewModel = RealtimeTranslateViewModel(
      state: .ready, speechRecognizer: recognizer,
      translationRuntime: FakeTranslationRuntime(result: "Bonjour."), haptics: haptics,
      speechOutput: FakeSpeechOutput()
    )

    viewModel.beginTurn(.a)
    XCTAssertEqual(haptics.played, [.turnBegan])

    recognizer.sendPartial("Hello")
    XCTAssertEqual(haptics.played, [.turnBegan])

    viewModel.endTurn(.a)
    XCTAssertEqual(haptics.played, [.turnBegan, .turnEnded])

    recognizer.sendFinal("Hello.")
    await waitUntil { viewModel.state == .ready }
    XCTAssertEqual(haptics.played, [.turnBegan, .turnEnded, .translationDelivered])
  }

  func testAFailedTranslationStaysSilentAndAFailedStartUsesTheErrorNotification() async {
    let quiet = FakeHaptics()
    let recognizer = FakeSpeechRecognizer()
    let failing = RealtimeTranslateViewModel(
      state: .ready, speechRecognizer: recognizer,
      translationRuntime: FakeTranslationRuntime(translateError: TestError.failed), haptics: quiet,
      speechOutput: FakeSpeechOutput()
    )

    failing.beginTurn(.b)
    failing.endTurn(.b)
    recognizer.sendFinal("Hello.")
    await waitUntil { failing.state == .ready }
    // The bubble carries the failure; the session keeps going, so it does not buzz.
    XCTAssertEqual(quiet.played, [.turnBegan, .turnEnded])

    let loud = FakeHaptics()
    let broken = FakeSpeechRecognizer()
    broken.startError = TestError.failed
    let erroring = RealtimeTranslateViewModel(
      state: .ready, speechRecognizer: broken, translationRuntime: FakeTranslationRuntime(),
      haptics: loud
    )

    erroring.beginTurn(.a)

    XCTAssertEqual(loud.played, [.sessionError])
    XCTAssertEqual(erroring.items.count, 0)
  }

  func testABubbleCopiesItsTranslationOnceThereIsOneAndItsTranscriptUntilThen() {
    let language = TargetLanguage.hyMT2Candidates[2]
    func item(_ transcript: String, _ translation: String?,
              _ state: ConversationItem.DeliveryState) -> ConversationItem {
      ConversationItem(id: UUID(), speaker: .a, transcript: transcript, targetLanguage: language,
                       translation: translation, state: state)
    }

    XCTAssertEqual(item("Hello.", "Bonjour.", .translated).copyableText, "Bonjour.")
    XCTAssertEqual(item("Hello.", nil, .partial).copyableText, "Hello.")
    XCTAssertEqual(item("Hello.", nil, .finalizing).copyableText, "Hello.")
    XCTAssertEqual(item("Hello.", nil, .translationFailed("nope")).copyableText, "Hello.")
    // A translated bubble with no text to show falls back rather than copying nothing.
    XCTAssertEqual(item("Hello.", nil, .translated).copyableText, "Hello.")
    // The bubble that is still saying "Listening..." has nothing to copy.
    XCTAssertNil(item("", nil, .partial).copyableText)
  }

  func testCopyingABubblePutsItOnTheClipboardAndShowsTheCopiedToast() async {
    let pasteboard = FakePasteboard()
    var announcements: [String] = []
    let model = ConversationCopyModel(
      pasteboard: pasteboard,
      toasts: ToastCenter(duration: 0.02, announce: { announcements.append($0) })
    )
    let translated = ConversationItem(
      id: UUID(), speaker: .b, transcript: "Hello.", targetLanguage: TargetLanguage.hyMT2Candidates[9],
      translation: "\u{c548}\u{b155}.", state: .translated
    )

    model.copy(translated)

    XCTAssertEqual(pasteboard.written, ["\u{c548}\u{b155}."])
    XCTAssertEqual(model.toasts.message, "Copied")
    XCTAssertEqual(announcements, ["Copied"])
    XCTAssertEqual(ConversationCopyModel.confirmation, "Copied")
    XCTAssertEqual(ConversationCopyModel.action, "Copy")
    XCTAssertFalse(ConversationCopyModel.confirmation.contains("\u{2014}"))

    // An empty bubble copies nothing at all, not an empty string.
    let empty = ConversationItem(
      id: UUID(), speaker: .a, transcript: "", targetLanguage: TargetLanguage.hyMT2Candidates[1],
      translation: nil, state: .partial
    )
    model.copy(empty)
    XCTAssertEqual(pasteboard.written, ["\u{c548}\u{b155}."])

    await waitUntil { model.toasts.message == nil }
  }

  // MARK: - Spoken translation

  func testAFinishedTranslationIsSpokenOnceInTheTargetLanguage() async {
    let speech = FakeSpeechOutput()
    let recognizer = FakeSpeechRecognizer()
    let viewModel = RealtimeTranslateViewModel(
      state: .ready, speechRecognizer: recognizer,
      translationRuntime: FakeTranslationRuntime(result: "\u{c548}\u{b155}."), speechOutput: speech,
      isMuted: false
    )

    viewModel.beginTurn(.a)
    recognizer.sendFinal("Hello.")
    viewModel.endTurn(.a)
    await waitUntil { viewModel.state == .ready }

    // Korean is speaker B's reading language, so an A turn is read in Korean.
    XCTAssertEqual(speech.spoken.map(\.text), ["\u{c548}\u{b155}."])
    XCTAssertEqual(speech.spoken.map(\.languageCode), ["ko"])
  }

  func testAFailedTranslationSpeaksNothing() async {
    let speech = FakeSpeechOutput()
    let recognizer = FakeSpeechRecognizer()
    let viewModel = RealtimeTranslateViewModel(
      state: .ready, speechRecognizer: recognizer,
      translationRuntime: FakeTranslationRuntime(translateError: TestError.failed), speechOutput: speech
    )

    viewModel.beginTurn(.b)
    recognizer.sendFinal("Hello.")
    viewModel.endTurn(.b)
    await waitUntil { viewModel.state == .ready }

    XCTAssertTrue(speech.spoken.isEmpty)
  }

  func testTheNewestTranslationCancelsTheOneBeingSpoken() async {
    let speech = FakeSpeechOutput()
    let recognizer = FakeSpeechRecognizer()
    let viewModel = RealtimeTranslateViewModel(
      state: .ready, speechRecognizer: recognizer,
      translationRuntime: FakeTranslationRuntime(result: "Bonjour."), speechOutput: speech,
      isMuted: false
    )
    viewModel.targetLanguageB = .hyMT2Candidates[2]

    for _ in 0 ..< 2 {
      viewModel.beginTurn(.a)
      recognizer.sendFinal("Hello.")
      viewModel.endTurn(.a)
      await waitUntil { viewModel.state == .ready }
    }

    XCTAssertEqual(speech.spoken.count, 2)
    // Each utterance is preceded by a stop, so a conversation never queues a backlog: one stop
    // for the turn that begins, one for the translation that replaces the previous sentence.
    XCTAssertEqual(speech.stopCount, 4)
    XCTAssertEqual(speech.events.last, .speak)
  }

  func testMutingSuppressesTheAnnouncementAndTheReplayAndStopsWhatIsPlaying() async {
    let speech = FakeSpeechOutput()
    let recognizer = FakeSpeechRecognizer()
    let viewModel = RealtimeTranslateViewModel(
      state: .ready, speechRecognizer: recognizer,
      translationRuntime: FakeTranslationRuntime(result: "Bonjour."), speechOutput: speech,
      isMuted: false
    )

    viewModel.setMuted(true)
    XCTAssertTrue(viewModel.isMuted)
    // Reaching for the toggle is how someone makes the phone stop talking mid-sentence.
    XCTAssertEqual(speech.stopCount, 1)

    viewModel.beginTurn(.a)
    recognizer.sendFinal("Hello.")
    viewModel.endTurn(.a)
    await waitUntil { viewModel.state == .ready }
    XCTAssertTrue(speech.spoken.isEmpty)

    viewModel.replay(viewModel.items.last ?? previewTranslatedItem)
    XCTAssertTrue(speech.spoken.isEmpty)

    viewModel.setMuted(false)
    viewModel.replay(viewModel.items.last ?? previewTranslatedItem)
    XCTAssertEqual(speech.spoken.map(\.text), ["Bonjour."])
  }

  func testBeginningATurnStopsSpeechBeforeTheRecognizerStarts() {
    let speech = FakeSpeechOutput()
    let recognizer = FakeSpeechRecognizer()
    let viewModel = RealtimeTranslateViewModel(
      state: .ready, speechRecognizer: recognizer, translationRuntime: FakeTranslationRuntime(),
      speechOutput: speech
    )

    viewModel.beginTurn(.a)

    XCTAssertEqual(speech.stopCount, 1)
    XCTAssertEqual(viewModel.state, .listening(.a))
    // Nothing is spoken over an open microphone, replay included.
    viewModel.replay(previewTranslatedItem)
    XCTAssertTrue(speech.spoken.isEmpty)
  }

  func testEndingASessionStopsSpeech() {
    let speech = FakeSpeechOutput()
    let viewModel = RealtimeTranslateViewModel(
      state: .ready, speechRecognizer: FakeSpeechRecognizer(),
      translationRuntime: FakeTranslationRuntime(), speechOutput: speech
    )

    viewModel.endSession()

    XCTAssertEqual(speech.stopCount, 1)
  }

  func testReplayingATranslatedBubbleSpeaksItAgainInItsOwnLanguage() {
    let speech = FakeSpeechOutput()
    let viewModel = RealtimeTranslateViewModel(
      state: .setup, items: [previewTranslatedItem], speechRecognizer: FakeSpeechRecognizer(),
      translationRuntime: FakeTranslationRuntime(), speechOutput: speech, isMuted: false
    )

    viewModel.replay(previewTranslatedItem)
    viewModel.replay(previewTranslatedItem)

    XCTAssertEqual(speech.spoken.map(\.text), ["Bonjour.", "Bonjour."])
    XCTAssertEqual(speech.spoken.map(\.languageCode), ["fr", "fr"])
  }

  func testOnlyAFinishedTranslationCanBeSpokenOrOfferAReplayControl() {
    let language = TargetLanguage.hyMT2Candidates[2]
    func item(_ translation: String?, _ state: ConversationItem.DeliveryState) -> ConversationItem {
      ConversationItem(id: UUID(), speaker: .a, transcript: "Hello.", targetLanguage: language,
                       translation: translation, state: state)
    }

    XCTAssertEqual(item("Bonjour.", .translated).speakableTranslation, "Bonjour.")
    XCTAssertNil(item(nil, .partial).speakableTranslation)
    XCTAssertNil(item(nil, .finalizing).speakableTranslation)
    XCTAssertNil(item(nil, .translationFailed("nope")).speakableTranslation)
    XCTAssertNil(item(nil, .translated).speakableTranslation)
    // Whitespace is not a sentence, so it neither speaks nor earns a control.
    XCTAssertNil(item("  \n ", .translated).speakableTranslation)

    XCTAssertEqual(SpokenTranslation.decision(for: item("Bonjour.", .translated), isMuted: false),
                   .speak(text: "Bonjour.", languageCode: "fr"))
    XCTAssertEqual(SpokenTranslation.decision(for: item("Bonjour.", .translated), isMuted: true),
                   .silent)
    XCTAssertEqual(SpokenTranslation.decision(for: item(nil, .finalizing), isMuted: false), .silent)
  }

  func testNothingIsSpokenWhileTheRecognizerHoldsTheMicrophone() {
    XCTAssertTrue(SessionState.listening(.a).isRecognizerLive)
    XCTAssertTrue(SessionState.finalizing(.b).isRecognizerLive)
    // Translating is not one of them: the recognizer has already been stopped by then, which is
    // exactly why the translation can be read out the moment it lands.
    XCTAssertFalse(SessionState.translating(.a).isRecognizerLive)
    XCTAssertFalse(SessionState.ready.isRecognizerLive)
        XCTAssertFalse(SessionState.setup.isRecognizerLive)
  }

  /// `speak` refuses while the recognizer owns the audio session, so a replay glyph left enabled
  /// there answers a tap with nothing at all, which reads as a broken control rather than a busy
  /// one. Muting already disabled it; this is the other half of the same rule.
  func testTheReplayControlIsDisabledWhileTheRecognizerHoldsTheMicrophone() {
    let recognizer = FakeSpeechRecognizer()
    let speech = FakeSpeechOutput()
    let viewModel = readyViewModel(recognizer, speechOutput: speech)

    XCTAssertTrue(viewModel.canReplay)

    viewModel.beginTurn(.a)
    XCTAssertFalse(viewModel.canReplay)
    viewModel.replay(previewTranslatedItem)
    XCTAssertTrue(speech.spoken.isEmpty)

    // Still the recognizer's session while the transcript finalizes.
    viewModel.endTurn(.a)
    XCTAssertEqual(viewModel.state, .finalizing(.a))
    XCTAssertFalse(viewModel.canReplay)

    // Translating is not: the microphone was handed back before the request went out.
    recognizer.sendFinal("hello")
    XCTAssertEqual(viewModel.state, .translating(.a))
    XCTAssertTrue(viewModel.canReplay)

    viewModel.setMuted(true)
    XCTAssertFalse(viewModel.canReplay)
  }

  func testVoiceMatchingPrefersTheExactCodeThenTheImpliedVariantThenAnyVoice() {
    let installed = ["en-US", "en-GB", "ko-KR", "zh-CN", "zh-TW", "fr-CA", "fr-FR", "pt-BR"]

    XCTAssertEqual(SpeechVoice.match(for: "ko", in: installed), "ko-KR")
    XCTAssertEqual(SpeechVoice.match(for: "en", in: installed), "en-US")
    XCTAssertEqual(SpeechVoice.match(for: "fr", in: installed), "fr-FR")
    XCTAssertEqual(SpeechVoice.match(for: "zh", in: installed), "zh-CN")
    XCTAssertEqual(SpeechVoice.match(for: "zh-Hant", in: installed), "zh-TW")
    // An exact code wins over any resolution.
    XCTAssertEqual(SpeechVoice.match(for: "pt-BR", in: installed), "pt-BR")
    // One voice for the language is the language-only fallback: the region is not checked.
    XCTAssertEqual(SpeechVoice.match(for: "pt", in: installed), "pt-BR")
    // No voice at all means silence, never the wrong language.
    XCTAssertNil(SpeechVoice.match(for: "bo", in: installed))
    XCTAssertNil(SpeechVoice.match(for: "ko", in: []))
  }

  func testSpeakingClaimsThePlaybackSessionOnceAndHandsItBackOnce() {
    let session = FakeSpeechAudioSession()
    let coordinator = SpeechAudioCoordinator(session: session)

    XCTAssertTrue(coordinator.beginPlayback())
    // A translation that replaces another must not tear the session down and rebuild it.
    XCTAssertTrue(coordinator.beginPlayback())
    XCTAssertEqual(session.events, [.activate])

    coordinator.endPlayback()
    XCTAssertEqual(session.events, [.activate, .deactivate])
    // The delegate callback for the cancelled utterance arrives after the recognizer may already
    // hold the session; ending twice must never deactivate a session speech no longer owns.
    coordinator.endPlayback()
    XCTAssertEqual(session.events, [.activate, .deactivate])
    XCTAssertFalse(coordinator.isPlaybackActive)
  }

  func testASessionThatRefusesToActivateSpeaksNothingAndRetriesNextTime() {
    let session = FakeSpeechAudioSession()
    session.activationError = TestError.failed
    let coordinator = SpeechAudioCoordinator(session: session)

    XCTAssertFalse(coordinator.beginPlayback())
    XCTAssertFalse(coordinator.isPlaybackActive)
    // Nothing was claimed, so nothing is handed back.
    coordinator.endPlayback()
    XCTAssertEqual(session.events, [.activate])

    session.activationError = nil
    XCTAssertTrue(coordinator.beginPlayback())
    XCTAssertEqual(session.events, [.activate, .activate])
  }

  func testSpokenOutputCopyUsesNoEmDash() {
    let copy = [
      SpeechOutputCopy.replayAction, SpeechOutputCopy.replayHint, SpeechOutputCopy.soundOnLabel,
      SpeechOutputCopy.soundOffLabel, SpeechOutputCopy.soundOnHint, SpeechOutputCopy.soundOffHint
    ]

    for line in copy {
      XCTAssertFalse(line.contains("\u{2014}"), line)
      XCTAssertFalse(line.contains("\u{2013}"), line)
      XCTAssertFalse(line.isEmpty)
    }
    XCTAssertEqual(SpeechOutputCopy.replayAction, "Play translation")
    XCTAssertNotEqual(SpeechOutputCopy.soundOnLabel, SpeechOutputCopy.soundOffLabel)
  }

  // MARK: - Remembered languages

  func testLanguageRestoreHonoursAnOverrideAndReDerivesEverythingElse() {
    let available: [SpeechSourceLanguage] = [
      .automatic,
      SpeechSourceLanguage(identifier: "en-GB", name: "English (United Kingdom)"),
      SpeechSourceLanguage(identifier: "en-US", name: "English (United States)"),
      SpeechSourceLanguage(identifier: "ko-KR", name: "Korean (South Korea)")
    ]
    let english = TargetLanguage(code: "en", name: "English")
    func resolve(_ reading: String?, _ spoken: String?) -> LanguageSelection {
      LanguageRestore.selection(storedReading: reading, storedSpoken: spoken,
                                fallbackReading: english, fallbackSpoken: .automatic,
                                available: available)
    }

    // Nothing remembered: the caller's chip, with the spoken language derived from it.
    XCTAssertEqual(resolve(nil, nil), LanguageSelection(reading: english, spoken: available[2]))
    // A remembered reading language drives a fresh derivation rather than a stored one.
    XCTAssertEqual(resolve("ko", nil).reading.code, "ko")
    XCTAssertEqual(resolve("ko", nil).spoken.identifier, "ko-KR")
    // An explicit override differs from the derived default, so it survives.
    XCTAssertEqual(resolve("en", "en-GB").spoken.identifier, "en-GB")
    // A stale recognizer id re-derives instead of pinning a locale the device cannot hear.
    XCTAssertEqual(resolve("en", "en-AU").spoken.identifier, "en-US")
    // `Automatic` was never an override; it means "follow the chip".
    XCTAssertEqual(resolve("ko", "automatic").spoken.identifier, "ko-KR")
    // A reading code this build no longer offers falls back rather than vanishing.
    XCTAssertEqual(resolve("xx", nil).reading, english)
  }

  func testBothSpeakersLanguagesSurviveARelaunch() {
    let store = EphemeralLanguagePreferences()
    let recognizer = FakeSpeechRecognizer()
    recognizer.sourceLanguages = [
      SpeechSourceLanguage(identifier: "en-US", name: "English (United States)"),
      SpeechSourceLanguage(identifier: "ja-JP", name: "Japanese (Japan)"),
      SpeechSourceLanguage(identifier: "ko-KR", name: "Korean (South Korea)")
    ]

    let first = RealtimeTranslateViewModel(state: .setup, speechRecognizer: recognizer,
                                           preferences: store)
    first.targetLanguageA = TargetLanguage(code: "ja", name: "Japanese")
    XCTAssertEqual(first.sourceLanguageA.identifier, "ja-JP")

    let relaunched = RealtimeTranslateViewModel(state: .setup, speechRecognizer: recognizer,
                                                preferences: store)
    XCTAssertEqual(relaunched.targetLanguageA.code, "ja")
    XCTAssertEqual(relaunched.sourceLanguageA.identifier, "ja-JP")
    // B was never touched, so it comes back as the default pair rather than as nothing.
    XCTAssertEqual(relaunched.targetLanguageB.code, "ko")
    XCTAssertEqual(relaunched.sourceLanguageB.identifier, "ko-KR")
  }

  func testAnExplicitSpokenOverrideSurvivesAndAStaleOneReDerives() {
    let store = EphemeralLanguagePreferences()
    let recognizer = FakeSpeechRecognizer()
    recognizer.sourceLanguages = [
      SpeechSourceLanguage(identifier: "en-US", name: "English (United States)"),
      SpeechSourceLanguage(identifier: "fr-BE", name: "French (Belgium)"),
      SpeechSourceLanguage(identifier: "fr-FR", name: "French (France)")
    ]

    let first = RealtimeTranslateViewModel(state: .setup, speechRecognizer: recognizer,
                                           preferences: store)
    first.targetLanguageB = TargetLanguage(code: "fr", name: "French")
    XCTAssertEqual(first.sourceLanguageB.identifier, "fr-FR")
    first.sourceLanguageB = SpeechSourceLanguage(identifier: "fr-BE", name: "French (Belgium)")

    let sameDevice = RealtimeTranslateViewModel(state: .setup, speechRecognizer: recognizer,
                                                preferences: store)
    XCTAssertEqual(sameDevice.targetLanguageB.code, "fr")
    XCTAssertEqual(sameDevice.sourceLanguageB.identifier, "fr-BE")

    // The Belgian recognizer is gone on this launch, so the chip re-derives.
    let narrowed = FakeSpeechRecognizer()
    narrowed.sourceLanguages = [
      SpeechSourceLanguage(identifier: "en-US", name: "English (United States)"),
      SpeechSourceLanguage(identifier: "fr-FR", name: "French (France)")
    ]
    let migrated = RealtimeTranslateViewModel(state: .setup, speechRecognizer: narrowed,
                                              preferences: store)
    XCTAssertEqual(migrated.targetLanguageB.code, "fr")
    XCTAssertEqual(migrated.sourceLanguageB.identifier, "fr-FR")
  }

  func testLanguagePreferencesRoundTripThroughPlatformDefaultsAndReset() throws {
    let suite = "LanguagePreferences-\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    addTeardownBlock { UserDefaults.standard.removePersistentDomain(forName: suite) }
    let store = UserDefaultsLanguagePreferences(defaults: defaults)

    store.setReadingCode("ja", for: .a)
    store.setSpokenIdentifier("ja-JP", for: .a)
    XCTAssertEqual(store.readingCode(for: .a), "ja")
    XCTAssertEqual(store.spokenIdentifier(for: .a), "ja-JP")
    XCTAssertNil(store.readingCode(for: .b))

    LanguagePreferenceDefaults.applyLaunchArguments([], to: defaults)
    XCTAssertEqual(store.readingCode(for: .a), "ja")

    LanguagePreferenceDefaults.applyLaunchArguments(["-resetLanguages"], to: defaults)
    XCTAssertNil(store.readingCode(for: .a))
    XCTAssertNil(store.spokenIdentifier(for: .a))
  }

  /// The store is injected at the app's composition root and nowhere else, which is what keeps one
  /// test's language change out of the next test's view model, and the host app's remembered
  /// choices out of both.
  func testAPlainViewModelNeverWritesToPlatformPreferences() {
    LanguagePreferenceDefaults.reset()
    addTeardownBlock { LanguagePreferenceDefaults.reset() }
    let viewModel = RealtimeTranslateViewModel(state: .setup, speechRecognizer: FakeSpeechRecognizer())

    viewModel.targetLanguageA = TargetLanguage(code: "ja", name: "Japanese")

    XCTAssertNil(UserDefaultsLanguagePreferences().readingCode(for: .a))
    XCTAssertEqual(
      RealtimeTranslateViewModel(state: .setup, speechRecognizer: FakeSpeechRecognizer())
        .targetLanguageA.code, "en")
  }

  // MARK: - Typed input

  func testATypedTurnBuildsExactlyTheRequestTheSpeechPathBuilds() async {
    let recognizer = FakeSpeechRecognizer()
    let spokenRuntime = FakeTranslationRuntime(result: "Bonjour")
    let spoken = readyViewModel(recognizer, runtime: spokenRuntime)
    spoken.targetLanguageB = .hyMT2Candidates[2]
    spoken.beginTurn(.a)
    recognizer.sendFinal("Good morning")
    spoken.endTurn(.a)
    await waitUntil { spoken.state == .ready }

    let typedRuntime = FakeTranslationRuntime(result: "Bonjour")
    let speechOutput = FakeSpeechOutput()
    let typed = RealtimeTranslateViewModel(
      state: .ready, speechRecognizer: FakeSpeechRecognizer(), translationRuntime: typedRuntime,
      speechOutput: speechOutput
    )
    typed.targetLanguageB = .hyMT2Candidates[2]

    // Trimmed on the way in, so a stray trailing newline never reaches the model.
    typed.submitTypedTranscript("  Good morning \n", speaker: .a)
    await waitUntil { typed.state == .ready }

    XCTAssertEqual(typed.mostRecentTranslationRequest, spoken.mostRecentTranslationRequest)
    XCTAssertEqual(typedRuntime.prompts, spokenRuntime.prompts)
    XCTAssertEqual(typedRuntime.prompts.count, 1)
    XCTAssertEqual(typed.items.count, 1)
    XCTAssertEqual(typed.items.last?.speaker, .a)
    XCTAssertEqual(typed.items.last?.transcript, "Good morning")
    XCTAssertEqual(typed.items.last?.translation, "Bonjour")
    XCTAssertEqual(typed.items.last?.targetLanguage.code, "fr")
    // The same bubble is spoken, in the same voice language, as a recognized one.
    XCTAssertEqual(speechOutput.spoken.map(\.languageCode), ["fr"])
    XCTAssertEqual(speechOutput.spoken.map(\.text), ["Bonjour"])
  }

  func testATypedTurnTapsOnSubmitAndOnDelivery() async {
    let haptics = FakeHaptics()
    let viewModel = RealtimeTranslateViewModel(
      state: .ready, speechRecognizer: FakeSpeechRecognizer(),
      translationRuntime: FakeTranslationRuntime(result: "Bonjour"), haptics: haptics,
      speechOutput: FakeSpeechOutput()
    )

    viewModel.submitTypedTranscript("Good morning", speaker: .a)
    await waitUntil { viewModel.state == .ready }

    XCTAssertEqual(haptics.played, [.turnEnded, .translationDelivered])
  }

  func testTypedInputIsGatedExactlyLikePushToTalk() {
    let recognizer = FakeSpeechRecognizer()
    let runtime = FakeTranslationRuntime(result: "Bonjour")
    let viewModel = readyViewModel(recognizer, runtime: runtime)
    XCTAssertTrue(viewModel.canSubmitTypedTranscript)

    viewModel.beginTurn(.a)
    XCTAssertFalse(viewModel.canSubmitTypedTranscript)
    viewModel.submitTypedTranscript("Hello", speaker: .b)
    XCTAssertEqual(viewModel.items.count, 1)
    XCTAssertNil(viewModel.mostRecentTranslationRequest)
    XCTAssertEqual(runtime.prompts, [])

    // Nothing can be typed before the model is loaded, or after the session ends, either.
    for state in [SessionState.setup, .loadingModel(0.5), .permissionRequired] {
      let idle = RealtimeTranslateViewModel(state: state, speechRecognizer: FakeSpeechRecognizer(),
                                            translationRuntime: FakeTranslationRuntime())
      XCTAssertFalse(idle.canSubmitTypedTranscript, "\(state)")
      idle.submitTypedTranscript("Hello", speaker: .a)
      XCTAssertTrue(idle.items.isEmpty, "\(state)")
    }
  }

  func testAWhitespaceOnlyDraftIsNotATurn() {
    let runtime = FakeTranslationRuntime(result: "Bonjour")
    let viewModel = readyViewModel(FakeSpeechRecognizer(), runtime: runtime)

    viewModel.submitTypedTranscript("   \n\t ", speaker: .a)

    XCTAssertTrue(viewModel.items.isEmpty)
    XCTAssertEqual(viewModel.state, .ready)
    XCTAssertEqual(runtime.prompts, [])
  }

  func testTypedInputSheetSendsOnlyARealDraftAndRemembersTheSpeakerNotTheText() {
    let model = TypedInputModel()

    XCTAssertFalse(model.isPresented)
    model.open()
    XCTAssertTrue(model.isPresented)
    XCTAssertFalse(model.hasDraft)
    model.text = "   \n "
    XCTAssertFalse(model.hasDraft)
    model.text = "  Good morning  "
    XCTAssertTrue(model.hasDraft)
    XCTAssertEqual(model.trimmedText, "Good morning")

    model.speaker = .b
    model.close()
    XCTAssertFalse(model.isPresented)
    model.open()
    XCTAssertEqual(model.speaker, .b)
    XCTAssertEqual(model.text, "")
  }

  /// A typed turn takes the audio handoff seriously in both directions: it stops whatever is being
  /// spoken before it takes the turn, the way a push-to-talk press does, and it never stops a
  /// recognizer it did not start. That second stop deactivates the audio session, which on a typed
  /// turn is the session the spoken output is about to use.
  func testATypedTurnStopsSpokenOutputAndLeavesTheIdleRecognizerAlone() async {
    let recognizer = FakeSpeechRecognizer()
    let speech = FakeSpeechOutput()
    let viewModel = readyViewModel(recognizer, speechOutput: speech)

    viewModel.submitTypedTranscript("Good morning", speaker: .a)

    XCTAssertEqual(speech.events.first, .stop)
    XCTAssertEqual(recognizer.stopCount, 0)
    XCTAssertEqual(recognizer.finishCount, 0)

    await waitUntil { viewModel.state == .ready }
    XCTAssertEqual(recognizer.stopCount, 0)
    XCTAssertEqual(speech.spoken.count, 1)
    XCTAssertEqual(viewModel.items.last?.translation, "Translated")
  }

  /// A spoken turn still releases its recognizer, which is the half the guard must not break.
  func testASpokenTurnStillReleasesItsRecognizerWhenTheTranslationStarts() async {
    let recognizer = FakeSpeechRecognizer()
    let viewModel = readyViewModel(recognizer)

    viewModel.beginTurn(.a)
    recognizer.sendFinal("Good morning")
    viewModel.endTurn(.a)

    XCTAssertEqual(recognizer.stopCount, 1)
    await waitUntil { viewModel.state == .ready }
  }

  func testTypedInputCopyNamesBothLanguagesAndUsesNoEmDash() {
    let guidance = TypedInputCopy.guidance(speaker: .a, typing: .hyMT2Candidates[1],
                                           translatedTo: .hyMT2Candidates[9])
    XCTAssertEqual(guidance, "Speaker A types in English. It is translated into Korean for Speaker B.")
    XCTAssertEqual(TypedInputCopy.placeholder(for: .hyMT2Candidates[9]), "Type in Korean")

    let copy = [
      TypedInputCopy.action, TypedInputCopy.hint, TypedInputCopy.blockedHint, TypedInputCopy.send,
      TypedInputCopy.cancel, TypedInputCopy.speakerPickerLabel, TypedInputCopy.fieldLabel, guidance,
      SettingsDrawerModel.clearConversationTitle, SettingsDrawerModel.clearConversationSubtitle,
      SettingsDrawerModel.clearConversationConfirmation
    ]
    for line in copy {
      XCTAssertFalse(line.contains("\u{2014}"), line)
      XCTAssertFalse(line.contains("\u{2013}"), line)
      XCTAssertFalse(line.isEmpty)
    }
  }

  // MARK: - Clearing the conversation

  func testClearingTheConversationEmptiesTheTranscriptAndLeavesTheSessionLive() {
    let speechOutput = FakeSpeechOutput()
    let viewModel = RealtimeTranslateViewModel(
      state: .ready, items: [previewTranslatedItem], speechRecognizer: FakeSpeechRecognizer(),
      translationRuntime: FakeTranslationRuntime(), speechOutput: speechOutput
    )

    XCTAssertTrue(viewModel.canClearConversation)
    viewModel.clearConversation()

    XCTAssertTrue(viewModel.items.isEmpty)
    XCTAssertEqual(viewModel.state, .ready)
    XCTAssertTrue(viewModel.isSessionLive)
    XCTAssertNil(viewModel.mostRecentTranslationRequest)
    // Whatever was being read aloud belonged to a bubble that just went away.
    XCTAssertEqual(speechOutput.stopCount, 1)

    // An empty transcript has nothing to clear, so a second call is a no-op, not a second toast.
    XCTAssertFalse(viewModel.canClearConversation)
    viewModel.clearConversation()
    XCTAssertEqual(speechOutput.stopCount, 1)
  }

  /// The note belongs to the conversation, not to the session: every other entry point that starts
  /// something new clears it, and leaving it behind strands `Tap to talk again` over an empty
  /// transcript that has nothing to do with the interruption that wrote it.
  func testClearingTheConversationAlsoClearsTheNote() {
    let recognizer = FakeSpeechRecognizer()
    let interruptions = FakeAudioInterruptions()
    let earlier = previewTranslatedItem
    let viewModel = RealtimeTranslateViewModel(
      state: .ready, items: [earlier], speechRecognizer: recognizer,
      translationRuntime: FakeTranslationRuntime(result: "Translated"),
      speechOutput: FakeSpeechOutput(), audioInterruptions: interruptions
    )
    viewModel.beginTurn(.a)
    recognizer.sendPartial("Half a sen")

    interruptions.send(.began)
    XCTAssertNotNil(viewModel.notice)
    XCTAssertEqual(viewModel.items.map(\.id), [earlier.id])

    viewModel.clearConversation()

    XCTAssertTrue(viewModel.items.isEmpty)
    XCTAssertNil(viewModel.notice)
  }

  func testClearingIsUnavailableWhileAnUtteranceIsInFlight() {
    let recognizer = FakeSpeechRecognizer()
    let viewModel = readyViewModel(recognizer)

    viewModel.beginTurn(.a)
    recognizer.sendPartial("Good morning")

    XCTAssertFalse(viewModel.canClearConversation)
    viewModel.clearConversation()
    XCTAssertEqual(viewModel.items.count, 1)
  }

  func testTheDrawersClearRowRunsTheClearClosesTheDrawerAndConfirmsIt() async {
    var cleared = 0
    var announcements: [String] = []
    let model = SettingsDrawerModel(
      appInfo: .main, pasteboard: FakePasteboard(), toastDuration: 0.02, openURL: { _ in },
      announce: { announcements.append($0) }
    )
    model.open()

    model.clearConversation { cleared += 1 }

    XCTAssertEqual(cleared, 1)
    XCTAssertFalse(model.isOpen)
    XCTAssertEqual(model.toast, "Conversation cleared")
    XCTAssertEqual(announcements, ["Conversation cleared"])

    await waitUntil { model.toast == nil }
  }

  // MARK: - Audio interruptions

  func testTheInterruptionTableTurnsOnWhatWasUsingAudioAtThatInstant() {
    // Listening and finalizing are the two states holding the microphone, so those are the two
    // that lose their utterance. Everything else either loses a sentence of speech or nothing.
    let table: [(AudioInterruptionEvent, SessionState, Bool, AudioInterruptionResponse)] = [
      (.began, .listening(.a), false, .abandonUtterance),
      (.began, .finalizing(.b), false, .abandonUtterance),
      // Speaking cannot happen over an open microphone, but the decision must not depend on that.
      (.began, .listening(.a), true, .abandonUtterance),
      (.began, .ready, true, .stopSpeech),
      (.began, .ready, false, .ignore),
      // The recognizer was released before the request went out, so a call costs nothing here.
      (.began, .translating(.a), false, .ignore),
      (.began, .loadingModel(0.5), false, .ignore),
      (.began, .setup, false, .ignore),
      (.routeLost, .listening(.b), false, .abandonUtterance),
      (.routeLost, .ready, true, .stopSpeech),
      (.routeLost, .ready, false, .ignore)
    ]
    for (event, state, isSpeaking, expected) in table {
      XCTAssertEqual(
        AudioInterruptionPolicy.response(to: event, state: state, isSpeaking: isSpeaking), expected,
        "\(event) in \(state) while speaking=\(isSpeaking)"
      )
    }
  }

  func testAnInterruptionEndingNeverRestartsAnythingEvenWhenTheSystemSaysItCould() {
    for state in [SessionState.ready, .listening(.a), .finalizing(.a), .setup] {
      for shouldResume in [true, false] {
        XCTAssertEqual(
          AudioInterruptionPolicy.response(to: .ended(shouldResume: shouldResume), state: state,
                                           isSpeaking: false), .ignore
        )
      }
    }
  }

  func testInterruptionPayloadsAreReadOrIgnoredRatherThanGuessed() {
    let began = AudioInterruptionEvent.fromInterruption(
      [AVAudioSessionInterruptionTypeKey: AVAudioSession.InterruptionType.began.rawValue]
    )
    XCTAssertEqual(began, .began)
    let resumable = AudioInterruptionEvent.fromInterruption([
      AVAudioSessionInterruptionTypeKey: AVAudioSession.InterruptionType.ended.rawValue,
      AVAudioSessionInterruptionOptionKey: AVAudioSession.InterruptionOptions.shouldResume.rawValue
    ])
    XCTAssertEqual(resumable, .ended(shouldResume: true))
    XCTAssertEqual(
      AudioInterruptionEvent.fromInterruption(
        [AVAudioSessionInterruptionTypeKey: AVAudioSession.InterruptionType.ended.rawValue]
      ),
      .ended(shouldResume: false)
    )
    XCTAssertNil(AudioInterruptionEvent.fromInterruption(nil))
    XCTAssertNil(AudioInterruptionEvent.fromInterruption(["unrelated": 1]))

    XCTAssertEqual(
      AudioInterruptionEvent.fromRouteChange(
        [AVAudioSessionRouteChangeReasonKey: AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue]
      ),
      .routeLost
    )
    // A headset arriving, or this app's own category change, is not an interruption.
    for reason in [AVAudioSession.RouteChangeReason.newDeviceAvailable, .categoryChange, .override] {
      XCTAssertNil(AudioInterruptionEvent.fromRouteChange([AVAudioSessionRouteChangeReasonKey: reason.rawValue]))
    }
    XCTAssertNil(AudioInterruptionEvent.fromRouteChange(nil))
  }

  func testAnInterruptionWhileListeningDiscardsTheUtteranceAndKeepsTheSessionLive() {
    let recognizer = FakeSpeechRecognizer()
    let interruptions = FakeAudioInterruptions()
    let earlier = previewTranslatedItem
    let viewModel = RealtimeTranslateViewModel(
      state: .ready, items: [earlier], speechRecognizer: recognizer,
      translationRuntime: FakeTranslationRuntime(result: "Translated"),
      speechOutput: FakeSpeechOutput(), audioInterruptions: interruptions
    )
    viewModel.beginTurn(.a)
    recognizer.sendPartial("Half a sen")
    XCTAssertEqual(viewModel.items.count, 2)

    interruptions.send(.began)

    // The half-written bubble is gone the way a failed start's bubble goes; the earlier one stays.
    XCTAssertEqual(viewModel.items.count, 1)
    XCTAssertEqual(viewModel.items.first?.id, earlier.id)
    XCTAssertEqual(viewModel.state, .ready)
    XCTAssertTrue(viewModel.isSessionLive)
    XCTAssertEqual(viewModel.notice, "Interrupted. Tap to talk again.")
    XCTAssertGreaterThan(recognizer.stopCount, 0)
  }

  func testAnInterruptionWhileFinalizingDiscardsTheUtteranceToo() {
    let recognizer = FakeSpeechRecognizer()
    let interruptions = FakeAudioInterruptions()
    let viewModel = readyViewModel(recognizer, interruptions: interruptions)
    viewModel.beginTurn(.b)
    recognizer.sendPartial("Nearly done")
    viewModel.endTurn(.b)
    XCTAssertEqual(viewModel.state, .finalizing(.b))

    interruptions.send(.routeLost)

    XCTAssertTrue(viewModel.items.isEmpty)
    XCTAssertEqual(viewModel.state, .ready)
    XCTAssertNotNil(viewModel.notice)
  }

  func testAnInterruptionWhileIdleOnlyStopsWhatWasBeingSpoken() {
    let speechOutput = FakeSpeechOutput()
    let interruptions = FakeAudioInterruptions()
    let viewModel = RealtimeTranslateViewModel(
      state: .ready, items: [previewTranslatedItem], speechRecognizer: FakeSpeechRecognizer(),
      translationRuntime: FakeTranslationRuntime(), speechOutput: speechOutput,
      audioInterruptions: interruptions
    )
    viewModel.replay(previewTranslatedItem)
    XCTAssertTrue(speechOutput.isSpeaking)

    interruptions.send(.began)

    XCTAssertFalse(speechOutput.isSpeaking)
    // The transcript is untouched: the bubble and its replay glyph are still there.
    XCTAssertEqual(viewModel.items.count, 1)
    XCTAssertNil(viewModel.notice)
    XCTAssertEqual(viewModel.state, .ready)

    // Nothing playing, nothing recording: an interruption changes nothing at all.
    interruptions.send(.began)
    XCTAssertNil(viewModel.notice)
  }

  func testTheNextPushToTalkWorksAfterAnInterruptionAndClearsTheNote() {
    let recognizer = FakeSpeechRecognizer()
    let interruptions = FakeAudioInterruptions()
    let viewModel = readyViewModel(recognizer, interruptions: interruptions)
    viewModel.beginTurn(.a)
    interruptions.send(.began)
    // The system's hint that audio could resume is deliberately not acted on.
    interruptions.send(.ended(shouldResume: true))
    XCTAssertEqual(viewModel.state, .ready)
    XCTAssertEqual(recognizer.startedSources.count, 1)

    viewModel.beginTurn(.a)

    XCTAssertEqual(viewModel.state, .listening(.a))
    XCTAssertEqual(recognizer.startedSources.count, 2)
    XCTAssertNil(viewModel.notice)
  }

  func testAudioInterruptionCopyUsesNoEmDash() {
    XCTAssertFalse(AudioInterruptionCopy.notice.contains("\u{2014}"))
    XCTAssertFalse(AudioInterruptionCopy.notice.isEmpty)
  }

  // MARK: - Model storage

  func testFootprintNamesTheArchiveTheModuleAndEverythingADeleteWouldReclaim() throws {
    let root = try makeCacheFixture(archiveByteCount: 8, indexedByteCount: 8, moduleByteCount: 16)

    let footprint = LocalModelStore.footprint(forModelName: "SJ_zetic/Hy-MT2-1.8B", cacheRoot: root)

    XCTAssertEqual(footprint.archiveBytes, 8)
    XCTAssertEqual(footprint.moduleBytes, 16)
    // The whole model directory, counted once, which is exactly what the delete removes.
    XCTAssertEqual(footprint.totalBytes, 24)
    XCTAssertFalse(footprint.isEmpty)

    // An archive on its own still reports, and an empty cache reports nothing rather than failing.
    let archiveOnly = try makeCacheFixture()
    XCTAssertEqual(
      LocalModelStore.footprint(forModelName: "SJ_zetic/Hy-MT2-1.8B", cacheRoot: archiveOnly).moduleBytes, 0
    )
    XCTAssertTrue(
      LocalModelStore.footprint(forModelName: "SJ_zetic/Hy-MT2-1.8B",
                                cacheRoot: root.appendingPathComponent("missing")).isEmpty
    )
    XCTAssertTrue(LocalModelStore.footprint(forModelName: "SJ_zetic/Hy-MT2-1.8B", cacheRoot: nil).isEmpty)
  }

  func testDeletingRemovesExactlyThisModelsArtifactsAndIndexEntries() throws {
    let root = try makeCacheFixture(moduleByteCount: 16)
    let manager = FileManager.default
    let neighbour = root.appendingPathComponent("artifacts/bbbb/llmTargetModel-1111111111111111",
                                                isDirectory: true)
    try manager.createDirectory(at: neighbour, withIntermediateDirectories: true)

    XCTAssertEqual(LocalModelStore.deleteModel(forModelName: "SJ_zetic/Hy-MT2-1.8B", cacheRoot: root),
                   .deleted)

    // The model's own directory is gone, and so are the index records naming it.
    XCTAssertFalse(manager.fileExists(atPath: root.appendingPathComponent("artifacts/aaaa").path))
    XCTAssertNil(LocalModelStore.discoverArchive(forModelName: "SJ_zetic/Hy-MT2-1.8B", cacheRoot: root))
    XCTAssertNil(LocalModelStore.discoverExtractedModule(forModelName: "SJ_zetic/Hy-MT2-1.8B", cacheRoot: root))
    XCTAssertTrue(LocalModelStore.footprint(forModelName: "SJ_zetic/Hy-MT2-1.8B", cacheRoot: root).isEmpty)
    let index = try JSONSerialization.jsonObject(
      with: Data(contentsOf: root.appendingPathComponent("cache-index.json"))
    ) as? [String: Any]
    XCTAssertEqual((index?["artifacts"] as? [[String: Any]])?.count, 0)
    XCTAssertEqual((index?["resolvedModels"] as? [[String: Any]])?.count, 0)
    XCTAssertEqual(index?["schemaVersion"] as? Int, 1)

    // Everything the SDK owns is left alone: another model's artifacts, the backend-selection
    // records the decryption key lives in, and the staging locks.
    XCTAssertTrue(manager.fileExists(atPath: neighbour.path))
    XCTAssertTrue(manager.fileExists(atPath: root.appendingPathComponent("staging-locks").path))
    XCTAssertTrue(manager.fileExists(
      atPath: root.appendingPathComponent("backend-selection-last-known-good/dummy.json").path
    ))

    // A second delete finds an index that no longer names this model. There is nothing left to
    // identify, so it refuses rather than guessing at a directory.
    XCTAssertEqual(LocalModelStore.deleteModel(forModelName: "SJ_zetic/Hy-MT2-1.8B", cacheRoot: root),
                   .refused)

    // An index that still names a model whose directory is already gone is the one case that is
    // neither a delete nor a refusal: the stale records are swept and nothing is removed.
    let stale = try makeCacheFixture()
    try manager.removeItem(at: stale.appendingPathComponent("artifacts/aaaa"))
    XCTAssertEqual(LocalModelStore.deleteModel(forModelName: "SJ_zetic/Hy-MT2-1.8B", cacheRoot: stale),
                   .nothingToDelete)
    XCTAssertNil(LocalModelStore.discoverArchive(forModelName: "SJ_zetic/Hy-MT2-1.8B", cacheRoot: stale))
  }

  func testDeletingRefusesAnIndexItCannotReadOrAModelKeyThatEscapesTheArtifactsRoot() throws {
    let manager = FileManager.default
    let unparseable = try makeCacheFixture()
    let indexURL = unparseable.appendingPathComponent("cache-index.json")
    try "{\"schemaVersion\":99,\"artifacts\":\"unexpected\"}"
      .write(to: indexURL, atomically: true, encoding: .utf8)

    XCTAssertEqual(LocalModelStore.deleteModel(forModelName: "SJ_zetic/Hy-MT2-1.8B", cacheRoot: unparseable),
                   .refused)
    XCTAssertTrue(manager.fileExists(atPath: unparseable.appendingPathComponent("artifacts/aaaa").path))

    // A key that is not a plain directory name is refused before any path is built from it, so a
    // model key of ".." cannot reach the cache root or anything beside it.
    for escape in ["..", "../escape", "nested/key", ""] {
      let container = manager.temporaryDirectory.appendingPathComponent("Escape-\(UUID().uuidString)")
      let root = container.appendingPathComponent("ZeticMLangeCache", isDirectory: true)
      addTeardownBlock { try? manager.removeItem(at: container) }
      try manager.createDirectory(at: root.appendingPathComponent("artifacts", isDirectory: true),
                                  withIntermediateDirectories: true)
      let sibling = container.appendingPathComponent("escape", isDirectory: true)
      try manager.createDirectory(at: sibling, withIntermediateDirectories: true)
      let index = """
        {"schemaVersion":1,"artifacts":[],"resolvedModels":[{"logicalRef":{"kind":"llm",\
        "name":"SJ_zetic/Hy-MT2-1.8B"},"modelKey":"\(escape)"}]}
        """
      try index.write(to: root.appendingPathComponent("cache-index.json"), atomically: true,
                      encoding: .utf8)

      XCTAssertEqual(LocalModelStore.deleteModel(forModelName: "SJ_zetic/Hy-MT2-1.8B", cacheRoot: root),
                     .refused, escape)
      XCTAssertTrue(manager.fileExists(atPath: sibling.path), escape)
      XCTAssertTrue(manager.fileExists(atPath: root.appendingPathComponent("artifacts").path), escape)
    }

    // No cache directory at all is refused too, rather than reaching for a default root.
    XCTAssertEqual(LocalModelStore.deleteModel(forModelName: "SJ_zetic/Hy-MT2-1.8B", cacheRoot: nil), .refused)
  }

  /// The index is rewritten before anything is removed, and the write is checked. A cache root
  /// that cannot be written to stands in for the disk-full case: without the check, the model
  /// directory is already gone by the time the write fails, leaving an index that promises a model
  /// that is not there and a drawer confirming a delete that only half happened.
  func testADeleteWhoseIndexWriteFailsRefusesAndLeavesTheModelWhereItWas() throws {
    let root = try makeCacheFixture(moduleByteCount: 16)
    let manager = FileManager.default
    let directory = root.appendingPathComponent("artifacts/aaaa")
    try manager.setAttributes([.posixPermissions: 0o500], ofItemAtPath: root.path)
    addTeardownBlock {
      try? manager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: root.path)
    }

    XCTAssertEqual(LocalModelStore.deleteModel(forModelName: "SJ_zetic/Hy-MT2-1.8B", cacheRoot: root),
                   .refused)

    XCTAssertTrue(manager.fileExists(atPath: directory.path))
    XCTAssertNotNil(LocalModelStore.discoverArchive(forModelName: "SJ_zetic/Hy-MT2-1.8B", cacheRoot: root))
    XCTAssertFalse(LocalModelStore.footprint(forModelName: "SJ_zetic/Hy-MT2-1.8B", cacheRoot: root).isEmpty)
  }

  /// The sole-key guess is good enough to load with: the worst a wrong one costs is an init that
  /// fails and a remote load that runs instead. It is not good enough to delete with, where the
  /// same guess removes whatever single model a shared cache happens to hold.
  func testDeletingRefusesACacheWhoseIndexDoesNotNameThisModel() throws {
    let root = try makeCacheFixture()
    let manager = FileManager.default
    let indexURL = root.appendingPathComponent("cache-index.json")
    var index = try XCTUnwrap(
      JSONSerialization.jsonObject(with: Data(contentsOf: indexURL)) as? [String: Any]
    )
    index["resolvedModels"] = [[String: Any]]()
    try JSONSerialization.data(withJSONObject: index).write(to: indexURL)

    // Loading still takes the guess, which is what keeps a cold launch off the network.
    XCTAssertNotNil(LocalModelStore.discoverArchive(forModelName: "SJ_zetic/Hy-MT2-1.8B", cacheRoot: root))

    XCTAssertEqual(LocalModelStore.deleteModel(forModelName: "SJ_zetic/Hy-MT2-1.8B", cacheRoot: root),
                   .refused)
    XCTAssertTrue(manager.fileExists(atPath: root.appendingPathComponent("artifacts/aaaa").path))
  }

  /// The row locks on what is holding the model, not on what is on screen. The states this covers
  /// are the two `isSessionLive` misses, and both are produced by a real view model rather than
  /// passed in as a boolean: the model being mapped during a load, and the model deliberately kept
  /// resident after `End Session` so the next start is instant.
  func testTheStorageRowLocksOnWhatHoldsTheModelRatherThanOnWhatIsOnScreen() async {
    let footprint = LocalModelStore.Footprint(archiveBytes: 8, moduleBytes: 8, totalBytes: 16)
    let runtime = FakeTranslationRuntime(result: "Translated")
    let viewModel = RealtimeTranslateViewModel(
      state: .setup, speechRecognizer: FakeSpeechRecognizer(), translationRuntime: runtime
    )

    XCTAssertEqual(viewModel.modelHold, .free)
    XCTAssertTrue(ModelStorageRow.row(footprint: footprint, hold: viewModel.modelHold).isEnabled)

    // Loading: the file is being mapped, and `isSessionLive` is false for all of it.
    viewModel.startSession()
    XCTAssertFalse(viewModel.isSessionLive)
    XCTAssertEqual(viewModel.modelHold, .memory)
    XCTAssertFalse(ModelStorageRow.row(footprint: footprint, hold: viewModel.modelHold).isEnabled)

    await waitUntil { viewModel.state == .ready }
    XCTAssertEqual(viewModel.modelHold, .session)

    // Ended: no session on screen, and 1.9 GB still mapped. Deleting here is the repro, the next
    // start short-circuits on the resident model and the app translates from a model it has
    // already thrown away.
    viewModel.endSession()
    XCTAssertFalse(viewModel.isSessionLive)
    XCTAssertTrue(runtime.isModelResident)
    XCTAssertEqual(viewModel.modelHold, .memory)
    let row = ModelStorageRow.row(footprint: footprint, hold: viewModel.modelHold)
    XCTAssertFalse(row.isEnabled)
    XCTAssertTrue(row.subtitle.contains(ModelStorageCopy.modelInMemory))
  }

  func testTheStorageRowNamesTheSizeAndLocksWhileASessionHoldsTheModel() {
    let footprint = LocalModelStore.Footprint(archiveBytes: 1_000_000_000, moduleBytes: 1_000_000_000,
                                              totalBytes: 2_000_000_000)
    let size = ModelStorageCopy.size(bytes: 2_000_000_000)

    let idle = ModelStorageRow.row(footprint: footprint, hold: .free)
    XCTAssertTrue(idle.isEnabled)
    XCTAssertEqual(idle.subtitle, "\(size) on this phone")
    XCTAssertTrue(idle.accessibilityLabel.contains(ModelStorageCopy.deleteAction))

    // A loaded model cannot be deleted from under the session that is using it.
    let live = ModelStorageRow.row(footprint: footprint, hold: .session)
    XCTAssertFalse(live.isEnabled)
    XCTAssertTrue(live.subtitle.contains(size))
    XCTAssertTrue(live.subtitle.contains("End the session first"))

    let empty = ModelStorageRow.row(footprint: .none, hold: .free)
    XCTAssertFalse(empty.isEnabled)
    XCTAssertEqual(empty.subtitle, "No model downloaded")

    for line in [ModelStorageCopy.title, ModelStorageCopy.empty, ModelStorageCopy.deleteAction,
                 ModelStorageCopy.keepAction, ModelStorageCopy.confirmationTitle,
                 ModelStorageCopy.sessionLive, ModelStorageCopy.modelInMemory,
                 ModelStorageCopy.deleted, ModelStorageCopy.confirmationMessage(size),
                 idle.subtitle, live.subtitle,
                 ModelStorageRow.row(footprint: footprint, hold: .memory).subtitle] {
      XCTAssertFalse(line.contains("\u{2014}"), line)
      XCTAssertFalse(line.isEmpty)
    }
  }

  func testTheDrawerAsksBeforeDeletingAndThenReportsAnEmptyStore() async {
    let stored = LocalModelStore.Footprint(archiveBytes: 8, moduleBytes: 0, totalBytes: 8)
    let storage = FixedModelStorage(stored)
    var announcements: [String] = []
    let model = SettingsDrawerModel(
      appInfo: .main, pasteboard: FakePasteboard(), toastDuration: 0.02, openURL: { _ in },
      announce: { announcements.append($0) }, modelStorage: storage
    )

    // Opening is what reads the disk, so a download that finished since the last look is seen.
    model.open()
    XCTAssertEqual(model.storage, stored)
    XCTAssertTrue(model.storageRow(hold: .free).isEnabled)
    XCTAssertFalse(model.isConfirmingDelete)

    // The row asks. It does not delete.
    model.confirmDeleteModel()
    XCTAssertTrue(model.isConfirmingDelete)
    XCTAssertEqual(storage.deletions, 0)

    model.deleteModel()

    XCTAssertFalse(model.isConfirmingDelete)
    XCTAssertEqual(storage.deletions, 1)
    XCTAssertTrue(model.storage.isEmpty)
    XCTAssertEqual(model.storageRow(hold: .free).subtitle, "No model downloaded")
    XCTAssertEqual(model.toast, "Model deleted")
    XCTAssertEqual(announcements, ["Model deleted"])
    // The drawer stays open on purpose: the row itself is the confirmation.
    XCTAssertTrue(model.isOpen)

    await waitUntil { model.toast == nil }
  }

  func testARefusedDeleteChangesNothingAndSaysNothing() {
    let stored = LocalModelStore.Footprint(archiveBytes: 8, moduleBytes: 0, totalBytes: 8)
    let storage = FixedModelStorage(stored, outcome: .refused)
    let model = SettingsDrawerModel(appInfo: .main, pasteboard: FakePasteboard(),
                                    toastDuration: 0.02, openURL: { _ in }, announce: { _ in },
                                    modelStorage: storage)
    model.open()

    model.deleteModel()

    XCTAssertEqual(model.storage, stored)
    XCTAssertNil(model.toast)
    XCTAssertFalse(model.isConfirmingDelete)
  }

  func testTheDownloadConsentGateReArmsOnceTheModelIsDeleted() throws {
    let root = try makeCacheFixture(moduleByteCount: 16)
    let name = "SJ_zetic/Hy-MT2-1.8B"
    let firstRun = FirstRunModel(path: FixedNetworkPath(.unrestricted), hasLocalModel: {
      LocalModelStore.discoverExtractedModule(forModelName: name, cacheRoot: root) != nil
        || LocalModelStore.discoverArchive(forModelName: name, cacheRoot: root) != nil
    }, hasPersonalKey: { true })

    // With the model on disk the start runs straight through, exactly as it does today.
    var started = 0
    firstRun.requestSessionStart { started += 1 }
    XCTAssertEqual(started, 1)
    XCTAssertNil(firstRun.consent)

    XCTAssertEqual(LocalModelStore.deleteModel(forModelName: name, cacheRoot: root), .deleted)

    // The very next start is a first download again, so it has to ask.
    firstRun.requestSessionStart { started += 1 }
    XCTAssertEqual(started, 1)
    XCTAssertEqual(firstRun.consent, FirstRunModel.ConsentPrompt(cellularWarning: false))
    firstRun.acceptConsent()
    XCTAssertEqual(started, 2)
  }

  func testTheStorageLaunchArgumentPutsAModelOnTheRowWithoutOneExisting() {
    XCTAssertNil(FixedModelStorage.fromLaunchArguments([]))
    XCTAssertNil(FixedModelStorage.fromLaunchArguments(["-modelStorage", "not-a-number"]))

    let storage = FixedModelStorage.fromLaunchArguments(["-modelStorage", "2039431168"])

    XCTAssertEqual(storage?.footprint().totalBytes, 2_039_431_168)
    XCTAssertEqual(storage?.deleteModel(), .deleted)
    XCTAssertEqual(storage?.footprint(), LocalModelStore.Footprint.none)
  }

  // MARK: - Localization

  /// The override is two writes that have to stay in step: the app's own remembered value, and the
  /// `AppleLanguages` key iOS reads while it builds `Bundle.main` at launch.
  func testChoosingAnAppLanguageWritesBothTheStoredValueAndAppleLanguages() throws {
    let scratch = try makeScratchDefaults()

    XCTAssertEqual(AppLanguageDefaults.stored(scratch.defaults), .system)
    XCTAssertNil(scratch.appleLanguages)

    AppLanguageDefaults.apply(.french, to: scratch.defaults)

    XCTAssertEqual(AppLanguageDefaults.stored(scratch.defaults), .french)
    XCTAssertEqual(scratch.appleLanguages, ["fr"])

    AppLanguageDefaults.apply(.spanish, to: scratch.defaults)

    XCTAssertEqual(scratch.appleLanguages, ["es"])
  }

  /// `System` removes the key rather than pinning the current device language, so a phone that
  /// changes its language later is followed instead of frozen.
  func testChoosingSystemRemovesTheAppleLanguagesOverrideRatherThanPinningALanguage() throws {
    let scratch = try makeScratchDefaults()
    AppLanguageDefaults.apply(.english, to: scratch.defaults)
    XCTAssertEqual(scratch.appleLanguages, ["en"])

    AppLanguageDefaults.apply(.system, to: scratch.defaults)

    XCTAssertEqual(AppLanguageDefaults.stored(scratch.defaults), .system)
    XCTAssertNil(scratch.appleLanguages)
  }

  func testAnUnknownStoredLanguageFallsBackToTheDeviceLanguage() throws {
    let scratch = try makeScratchDefaults()
    scratch.defaults.set("klingon", forKey: AppLanguageDefaults.storageKey)

    XCTAssertEqual(AppLanguageDefaults.stored(scratch.defaults), .system)
    XCTAssertEqual(AppLanguage.named(nil), .system)
    XCTAssertNil(AppLanguage.system.localeIdentifier)
    XCTAssertEqual(AppLanguage.allCases.compactMap(\.localeIdentifier), ["en", "fr", "es"])
  }

  func testTheResetLaunchArgumentClearsBothHalvesOfTheOverride() throws {
    let scratch = try makeScratchDefaults()
    AppLanguageDefaults.apply(.french, to: scratch.defaults)

    AppLanguageDefaults.applyLaunchArguments([], to: scratch.defaults)
    XCTAssertEqual(AppLanguageDefaults.stored(scratch.defaults), .french)

    AppLanguageDefaults.applyLaunchArguments(["-resetAppLanguage"], to: scratch.defaults)

    XCTAssertEqual(AppLanguageDefaults.stored(scratch.defaults), .system)
    XCTAssertNil(scratch.appleLanguages)
  }

  /// The drawer's side of it: the row writes through the model, which confirms with the same toast
  /// behaviour every other drawer action uses, and says nothing when the choice did not change.
  func testTheLanguageRowConfirmsAChangeAndStaysQuietWhenNothingChanged() throws {
    let scratch = try makeScratchDefaults()
    var announcements: [String] = []
    let model = SettingsDrawerModel(toastDuration: 60, announce: { announcements.append($0) },
                                    modelStorage: FixedModelStorage(.none),
                                    languageDefaults: scratch.defaults)

    model.selectAppLanguage(.system)
    XCTAssertNil(model.toast)
    XCTAssertEqual(announcements, [])

    model.selectAppLanguage(.spanish)

    XCTAssertEqual(model.appLanguage, .spanish)
    XCTAssertEqual(model.toast, "Language applies fully after reopening the app")
    XCTAssertEqual(announcements, ["Language applies fully after reopening the app"])
    XCTAssertFalse(AppLanguageCopy.restartNotice.contains("\u{2014}"))
  }

  /// Proves the catalog is actually wired up, rather than every lookup quietly falling through to
  /// its own key. Each of these has an explicit key, so a missing or uncompiled catalog would make
  /// the assertion read `status.listening` instead of `A is speaking`.
  func testExplicitCatalogKeysResolveToTheirEnglishStrings() {
    XCTAssertEqual(SessionState.listening(.a).title, "Speaker A is speaking")
    XCTAssertEqual(SessionState.finalizing(.b).title, "Finalizing Speaker B's transcript")
    XCTAssertEqual(SessionState.translating(.a).title, "Translating for Speaker B")
    XCTAssertEqual(ModelStorageCopy.onThisPhone("1.9 GB"), "1.9 GB on this phone")
    XCTAssertEqual(ModelStorageCopy.confirmationMessage("1.9 GB"),
                   "This frees 1.9 GB. The next session downloads the model again.")
    XCTAssertEqual(ModelDownloadSize.total, "1.91 GB")
    XCTAssertEqual(AppInfo(info: ["CFBundleShortVersionString": "1.2", "CFBundleVersion": "7"]).versionLine,
                   "Version 1.2 (7)")
    XCTAssertEqual(TypedInputCopy.placeholder(for: .hyMT2Candidates[9]), "Type in Korean")
    XCTAssertEqual(
      TranslationFailureCopy.message(for: TranslationRuntimeError.generationFailed(3)),
      "The translation did not finish."
    )
  }

  /// The other half of the same proof: strings whose key is their own English text. A build with no
  /// catalog would still pass these, so the explicit-key test above is the one that catches a
  /// missing catalog; this one catches a wording change that was made in only one of two places.
  func testCatalogBackedCopyStillReadsInEnglish() {
    XCTAssertEqual(SessionState.ready.title, "Ready to talk")
    XCTAssertEqual(SettingsDrawerModel.clearConversationTitle, "Clear conversation")
    XCTAssertEqual(ModelStorageCopy.title, "Storage")
    XCTAssertEqual(SpeechOutputCopy.replayAction, "Play translation")
    XCTAssertEqual(AudioInterruptionCopy.notice, "Interrupted. Tap to talk again.")
    XCTAssertEqual(AppLanguageCopy.title, "App language")
    XCTAssertEqual(SpeechSourceLanguage.automatic.name, "Automatic")
    XCTAssertEqual(AppText.productName, "Turn Translate")
  }

  /// The compiled catalog has to reach the app bundle, not just the source tree. Only the entries
  /// whose key differs from their English value produce a line here; the rest resolve to their key.
  func testTheCompiledEnglishCatalogIsInTheAppBundle() throws {
    let url = try XCTUnwrap(
      Bundle.main.url(forResource: "Localizable", withExtension: "strings", subdirectory: "en.lproj"),
      "en.lproj/Localizable.strings is missing from the app bundle"
    )
    let compiled = try XCTUnwrap(
      PropertyListSerialization.propertyList(from: Data(contentsOf: url), format: nil) as? [String: String]
    )

    XCTAssertEqual(compiled["status.listening"], "Speaker %@ is speaking")
    XCTAssertEqual(compiled["storage.onThisPhone"], "%@ on this phone")
    XCTAssertFalse(compiled.isEmpty)
    for (key, value) in compiled {
      XCTAssertFalse(value.contains("\u{2014}"), key)
    }
  }

  /// The whole catalog, read as the file the language experts hand back. Every entry carries a
  /// comment so a translator is never guessing what a string is for, every value is free of em and
  /// en dashes in every language, and nothing is left in a state that would be dropped at compile.
  func testTheStringCatalogIsFullyCommentedAndFreeOfEmDashesInEveryLanguage() throws {
    let catalog = try Self.stringCatalog()

    XCTAssertEqual(catalog.sourceLanguage, "en")
    XCTAssertFalse(catalog.strings.isEmpty)
    for (key, entry) in catalog.strings {
      XCTAssertFalse(key.contains("\u{2014}"), key)
      XCTAssertFalse(key.contains("\u{2013}"), key)
      XCTAssertFalse(entry.comment?.isEmpty ?? true, "\(key) has no translator comment")
      XCTAssertNotEqual(entry.extractionState, "stale", "\(key) is no longer used in source")
      for (language, value) in entry.values {
        XCTAssertTrue(Self.shippingLanguages.contains(language),
                      "\(key) carries an unexpected language \(language)")
        XCTAssertFalse(value.contains("\u{2014}"), "\(key): \(value)")
        XCTAssertFalse(value.contains("\u{2013}"), "\(key): \(value)")
        XCTAssertFalse(value.contains("\u{2212}"), "\(key): \(value)")
        XCTAssertFalse(value.isEmpty, key)
      }
      // The one that bites after a re-sync: `xcstringstool sync` marks a freshly extracted entry
      // `new`, and `xcstringstool compile` silently drops anything that is not `translated`, so an
      // unreviewed entry ships as its own raw key.
      for (language, state) in entry.states {
        XCTAssertEqual(state, "translated", "\(key) is \(state) in \(language) and will not compile")
      }
    }
  }

  /// French and Spanish are complete: every key for every key, none silently left to fall back to
  /// English.
  /// A missing key is not a build error and not a crash, it is one English line in the middle of a
  /// translated screen, which is exactly the kind of thing only a count catches.
  func testFrenchAndSpanishCoverEveryKeyInTheCatalog() throws {
    let catalog = try Self.stringCatalog()

    for language in ["fr", "es"] {
      let missing = catalog.strings
        .filter { $0.value.values[language] == nil }
        .keys.sorted()
      XCTAssertEqual(missing, [], "\(language) is missing \(missing.count) keys")
      let untranslated = catalog.strings
        .filter { $0.value.states[language] != "translated" }
        .keys.sorted()
      XCTAssertEqual(untranslated, [], "\(language) has entries that will not compile")
      XCTAssertEqual(catalog.strings.compactMap { $0.value.values[language] }.count,
                     catalog.strings.count)
    }
  }

  /// Format arguments are the one translation error that crashes rather than reads oddly: a value
  /// with an extra `%@`, or `%lld` where English has `%@`, is a mismatched `String(format:)`. The
  /// comparison ignores positional indices, because a translation is free to reorder arguments and
  /// several deliberately do.
  func testEveryTranslationCarriesTheSameFormatSpecifiersAsEnglish() throws {
    let catalog = try Self.stringCatalog()

    for (key, entry) in catalog.strings {
      // An entry whose key is its own English value has no `en` localization to read.
      let english = Self.formatSpecifiers(in: entry.values["en"] ?? key)
      for language in ["fr", "es"] {
        guard let value = entry.values[language] else { continue }
        XCTAssertEqual(Self.formatSpecifiers(in: value), english,
                       "\(key) in \(language): \(value)")
      }
    }
  }

  /// French typography survives the round trip through the catalog file. These are invisible
  /// characters, so nothing on screen says they have been eaten: a pipeline that trims or
  /// normalises whitespace silently turns `Micro : pour...` into the wrong French, and the
  /// percentage in the download headline loses the space French sets before `%`.
  func testFrenchKeepsItsNoBreakSpacesAndTypographicApostrophes() throws {
    let catalog = try Self.stringCatalog()
    let french = catalog.strings.compactMapValues { $0.values["fr"] }

    XCTAssertEqual(french.values.map { $0.filter { $0 == "\u{00A0}" }.count }.reduce(0, +), 9)
    XCTAssertEqual(french.values.map { $0.filter { $0 == "\u{202F}" }.count }.reduce(0, +), 1)
    // Espace mot insecable before the colon, espace fine insecable before the question mark.
    XCTAssertEqual(french["Session status: %@"], "\u{c9}tat de la session\u{00A0}: %@")
    XCTAssertEqual(french["Delete the downloaded model?"],
                   "Supprimer le mod\u{e8}le t\u{e9}l\u{e9}charg\u{e9}\u{202F}?")
    XCTAssertEqual(french["modelPreparation.downloading"],
                   "T\u{e9}l\u{e9}chargement du mod\u{e8}le de traduction %lld\u{00A0}%%")
    // Every French apostrophe is U+2019, which is what a French reviewer expects to see.
    for (key, value) in french {
      XCTAssertFalse(value.contains("'"), "\(key) uses a straight apostrophe: \(value)")
    }
    XCTAssertTrue(french["App language"]?.contains("\u{2019}") ?? false)
  }

  /// The compiled French and Spanish catalogs have to reach the app bundle, and a lookup in each
  /// has to answer with the expert's wording rather than falling through to English or to the key.
  /// `xcstringstool compile` drops any unit that is not `translated`, so this is where that trap
  /// shows up as a real failure.
  func testFrenchAndSpanishResolveThroughTheirBundleLocalizations() throws {
    let french = try Self.localizedBundle("fr")
    XCTAssertEqual(french.localizedString(forKey: "Start session", value: nil, table: nil),
                   "D\u{e9}marrer la session")
    XCTAssertEqual(french.localizedString(forKey: "status.listening", value: nil, table: nil),
                   "L\u{2019}interlocuteur %@ parle")
    XCTAssertEqual(french.localizedString(forKey: "Storage", value: nil, table: nil), "Stockage")
    XCTAssertEqual(french.localizedString(forKey: "storage.onThisPhone", value: nil, table: nil),
                   "%@ sur ce t\u{e9}l\u{e9}phone")

    let spanish = try Self.localizedBundle("es")
    XCTAssertEqual(spanish.localizedString(forKey: "Start session", value: nil, table: nil),
                   "Empezar sesi\u{f3}n")
    XCTAssertEqual(spanish.localizedString(forKey: "status.listening", value: nil, table: nil),
                   "El hablante %@ est\u{e1} hablando")
    XCTAssertEqual(spanish.localizedString(forKey: "Storage", value: nil, table: nil),
                   "Almacenamiento")
    XCTAssertEqual(spanish.localizedString(forKey: "storage.onThisPhone", value: nil, table: nil),
                   "%@ en este tel\u{e9}fono")
  }

  /// A `UserDefaults` domain of this test's own. Nothing here may touch `.standard`: the host app
  /// and the UI tests run out of it, and an `AppleLanguages` value left behind would put the next
  /// UI test run into another language.
  private func makeScratchDefaults() throws -> ScratchDefaults {
    let name = "ai.zetic.turntranslate.tests.\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
    addTeardownBlock { UserDefaults.standard.removePersistentDomain(forName: name) }
    return ScratchDefaults(name: name, defaults: defaults)
  }

  private var previewTranslatedItem: ConversationItem {
    ConversationItem(
      id: UUID(), speaker: .a, transcript: "Hello.", targetLanguage: .hyMT2Candidates[2],
      translation: "Bonjour.", state: .translated
    )
  }

  /// Mirrors the schema the SDK writes, with dummy checksums and a dummy secret key. Passing
  /// `moduleByteCount` adds the extracted `.gguf` beside the archive, which is what a cache looks
  /// like once a model has actually been loaded once.
  private func makeCacheFixture(archiveByteCount: Int = 8, indexedByteCount: Int = 8,
                                moduleByteCount: Int? = nil) throws -> URL {
    let modelKey = "aaaa"
    let manager = FileManager.default
    let container = manager.temporaryDirectory.appendingPathComponent("LocalModelStore-\(UUID().uuidString)")
    let root = container.appendingPathComponent("ZeticMLangeCache", isDirectory: true)
    addTeardownBlock { try? manager.removeItem(at: container) }
    let relativePath = "artifacts/\(modelKey)/llmTargetModel-c488c23ffebf7fd0/Hy_MT2_1.ztc"
    let archive = root.appendingPathComponent(relativePath)
    try manager.createDirectory(at: archive.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data(repeating: 0, count: archiveByteCount).write(to: archive)
    var storedFiles = [
      """
      {"byteCount":\(indexedByteCount),"checksum":"00000000000000000000000000000000",\
      "relativePath":"\(relativePath)","validationState":"checksumValidated"}
      """
    ]
    if let moduleByteCount {
      let modulePath = "artifacts/\(modelKey)/llmTargetModel-c488c23ffebf7fd0/Hy_MT2_1.gguf"
      let module = root.appendingPathComponent(modulePath)
      try Data(repeating: 0, count: moduleByteCount).write(to: module)
      storedFiles.append(
        """
        {"byteCount":\(moduleByteCount),"checksum":"00000000000000000000000000000000",\
        "relativePath":"\(modulePath)","validationState":"checksumValidated"}
        """
      )
    }
    let index = """
      {"schemaVersion":1,"artifacts":[{"createdAt":809969480.2,"id":"llmTargetModel-c488c23ffebf7fd0",\
      "kind":"llmTargetModel","modelKey":"\(modelKey)","ownedArtifactIDs":[],"primaryRelativePath":"\(relativePath)",\
      "selector":{"apType":"GPU","llmTarget":"LLAMA_CPP"},"storedFiles":[\(storedFiles.joined(separator: ","))],\
      "updatedAt":809969480.2}],\
      "resolvedModels":[{"logicalRef":{"kind":"llm","name":"SJ_zetic/Hy-MT2-1.8B"},"modelKey":"\(modelKey)",\
      "updatedAt":809969926.4}]}
      """
    try index.write(to: root.appendingPathComponent("cache-index.json"), atomically: true, encoding: .utf8)
    let records = root.appendingPathComponent("backend-selection-last-known-good", isDirectory: true)
    try manager.createDirectory(at: records, withIntermediateDirectories: true)
    let record = """
      {"candidate_artifact_id":"llmTargetModel-c488c23ffebf7fd0","schema_version":1,\
      "response":{"candidate":{"checksum":"00000000000000000000000000000000",\
      "secret_key":"\(String(repeating: "0", count: 64))"},"model_key":"\(modelKey)"}}
      """
    try record.write(to: records.appendingPathComponent("dummy.json"), atomically: true, encoding: .utf8)
    try manager.createDirectory(at: root.appendingPathComponent("staging-locks", isDirectory: true),
                                withIntermediateDirectories: true)
    return root
  }

  // MARK: - Designer review fixes

  /// The empty transcript said "Choose the languages above, then start the session." at every
  /// moment a session was not live, which during a 1.9 GB download pointed at locked chips and
  /// told someone to start a session that had already started. It is a different sentence per
  /// state now, and no sentence at all where the banner above is already explaining.
  func testTheEmptyTranscriptHintIsPerStateAndSilentBehindABanner() {
    XCTAssertEqual(ConversationEmptyHint.text(for: .setup),
                   "Choose the languages above, then start the session.")
    for live: SessionState in [.ready, .listening(.a), .finalizing(.b), .translating(.a)] {
      XCTAssertEqual(ConversationEmptyHint.text(for: live),
                     "Speaker A or B can begin speaking.", "\(live)")
    }
    for explained: SessionState in [.permissionRequired, .loadingModel(nil), .loadingModel(0.4),
                                    .modelLoadFailed("nope"), .error(.runtime("nope"))] {
      XCTAssertNil(ConversationEmptyHint.text(for: explained), "\(explained)")
    }
  }

  /// One byte count, one formatter, one string. The consent card used to promise a hand-written
  /// "about 1.9 GB" and the storage row then reported the measured bytes as something else.
  func testTheConsentCardAndTheStorageRowNameTheSameSize() {
    XCTAssertEqual(ModelDownloadSize.bytes, 1_908_528_832)
    XCTAssertEqual(ModelDownloadSize.total, ModelStorageCopy.size(bytes: ModelDownloadSize.bytes))
    XCTAssertEqual(ModelDownloadSize.total, "1.91 GB")
    XCTAssertTrue(FirstRunCopy.consentSize.contains(ModelDownloadSize.total))
    XCTAssertTrue(
      ModelStorageRow.row(
        footprint: LocalModelStore.Footprint(archiveBytes: ModelDownloadSize.bytes, moduleBytes: 0,
                                             totalBytes: ModelDownloadSize.bytes),
        hold: .free
      ).subtitle.contains(ModelDownloadSize.total)
    )
    // And the progress line under the bar, so no two numbers on the download screen disagree.
    XCTAssertEqual(ModelPreparationStatus.status(for: 0.5).detail, "954.3 MB of 1.91 GB")
  }

  /// A state toggle and an action cannot be the same drawing. The status strip's speaker says
  /// whether the app is silent; a bubble's control says "read this one again".
  func testTheReplayActionIsNotTheMuteStatesGlyph() {
    XCTAssertEqual(SpeechGlyph.replay, "play.circle")
    XCTAssertNotEqual(SpeechGlyph.replay, SpeechGlyph.soundOn)
    XCTAssertNotEqual(SpeechGlyph.replay, SpeechGlyph.soundOff)
    for glyph in [SpeechGlyph.replay, SpeechGlyph.soundOn, SpeechGlyph.soundOff,
                  ZeticWordmarkGlyph.settings] {
      XCTAssertNotNil(UIImage(systemName: glyph), "\(glyph) is not an SF Symbol on this platform")
    }
  }

  /// `.endingSession` was never assigned and `.ended` was reachable only from a launch argument,
  /// so both were dead: a status title, a banner branch, a hint, a disabled clause, and three
  /// catalog entries kept alive for states the app could not enter.
  func testTheDeadSessionStatesTookTheirCatalogEntriesWithThem() throws {
    let catalog = try Self.stringCatalog()
    for key in ["Closing Translation Session", "Closing translation session...", "Session Ended",
                "Wait while the session ends."] {
      XCTAssertNil(catalog.strings[key], "\(key) belongs to a state the app cannot enter")
    }
    // And the jargon the failure copy used to carry, plus the duplicated banner line.
    for key in ["The Hy-MT2 translation model could not complete this request.",
                "translationFailure.generationFailed", "modelSize.approximate",
                "The Melange personal key is not configured in this app build.",
                "Speaker controls unlock when the model is ready.",
                "Start Session", "End Session"] {
      XCTAssertNil(catalog.strings[key], "\(key) is no longer reachable from source")
    }
    XCTAssertNotNil(catalog.strings["Start session"])
    XCTAssertNotNil(catalog.strings["End session"])
    XCTAssertEqual(SessionActionCopy.start, "Start session")
    XCTAssertEqual(SessionActionCopy.end, "End session")
  }

  /// A failed turn used to be the end of the road: the words were said, the transcript was on
  /// screen, and nothing anywhere would send it again. The retry re-runs that bubble's own
  /// transcript against that bubble's own reading language.
  func testAFailedTranslationCanBeRunAgainFromItsOwnBubble() async {
    let runtime = FakeTranslationRuntime(result: "Bonjour")
    runtime.queuedTranslateErrors = [TranslationRuntimeError.generationFailed(3)]
    let viewModel = readyViewModel(FakeSpeechRecognizer(), runtime: runtime)

    viewModel.submitTypedTranscript("Hello", speaker: .a)
    await waitUntil { viewModel.state == .ready }
    let failed = try? XCTUnwrap(viewModel.items.first)
    guard let failed else { return XCTFail("no bubble") }
    XCTAssertEqual(failed.state, .translationFailed("The translation did not finish."))
    XCTAssertTrue(viewModel.canRetryTranslation)

    viewModel.retryTranslation(failed)

    XCTAssertEqual(viewModel.state, .translating(.a))
    XCTAssertEqual(viewModel.items.first?.state, .finalizing)
    await waitUntil { viewModel.state == .ready }
    XCTAssertEqual(viewModel.items.count, 1, "a retry re-runs the bubble, it does not add one")
    XCTAssertEqual(viewModel.items.first?.translation, "Bonjour")
    XCTAssertEqual(viewModel.items.first?.state, .translated)
    // Same transcript, same reading language: the second request is the first one again.
    XCTAssertEqual(runtime.prompts.count, 2)
    XCTAssertEqual(runtime.prompts[0], runtime.prompts[1])
  }

  /// A retry is gated exactly like a new utterance, and a bubble that did not fail has nothing to
  /// retry, so neither can land on top of someone who is mid-sentence.
  func testARetryIsRefusedMidUtteranceAndOnABubbleThatDidNotFail() async {
    let recognizer = FakeSpeechRecognizer()
    let runtime = FakeTranslationRuntime(result: "Bonjour")
    runtime.queuedTranslateErrors = [TranslationRuntimeError.emptyOutput]
    let viewModel = readyViewModel(recognizer, runtime: runtime)

    viewModel.submitTypedTranscript("Hello", speaker: .a)
    await waitUntil { viewModel.state == .ready }
    guard let failed = viewModel.items.first else { return XCTFail("no bubble") }

    viewModel.beginTurn(.b)
    XCTAssertFalse(viewModel.canRetryTranslation)
    viewModel.retryTranslation(failed)
    XCTAssertEqual(runtime.prompts.count, 1)
    XCTAssertEqual(viewModel.state, .listening(.b))

    // A translated bubble is not a failure, so it is not retryable either.
    let translated = ConversationItem(id: UUID(), speaker: .a, transcript: "Hello",
                                      targetLanguage: .hyMT2Candidates[2], translation: "Bonjour",
                                      state: .translated)
    let idle = readyViewModel(FakeSpeechRecognizer(), runtime: FakeTranslationRuntime(result: "x"))
    idle.retryTranslation(translated)
    XCTAssertEqual(idle.state, .ready)
  }

  /// The error banner's one button used to re-request the microphone whatever had gone wrong,
  /// which for a runtime failure asked for a permission the app already held and dropped the live
  /// session, and its loaded model's session, back to `setup` for nothing.
  func testARuntimeErrorReturnsToTheLiveSessionAndOnlyAPermissionOneGoesBackToSetup() async {
    let recognizer = FakeSpeechRecognizer(startError: PlatformSpeechError.unavailable("Busy."))
    let viewModel = readyViewModel(recognizer)

    viewModel.beginTurn(.a)
    XCTAssertEqual(viewModel.state, .error(SessionFailure(message: "Busy.", cause: .runtime)))

    viewModel.recoverFromError()

    XCTAssertEqual(viewModel.state, .ready, "the model is still loaded, so the session comes back")

    let refused = FakeSpeechRecognizer(startError: PlatformSpeechError.microphonePermissionRequired,
                                       permission: .required)
    let denied = readyViewModel(refused)
    denied.beginTurn(.a)
    guard case let .error(failure) = denied.state else { return XCTFail("expected an error") }
    XCTAssertEqual(failure.cause, .permission)
    XCTAssertEqual(failure.message, "Microphone permission is required.")

    denied.recoverFromError()
    await waitUntil { denied.state == .permissionRequired }
  }

  /// Cancelling a model preparation is the same path `End session` already took, under the name
  /// it has while a model is being prepared. It has to work for a local load too, where there is
  /// no transfer to stop and the load is simply abandoned.
  func testAModelPreparationCanBeCancelledFromTheBottomBarInBothItsForms() async {
    for delay: UInt64 in [2_000_000_000, 0] {
      let runtime = FakeTranslationRuntime(result: "Bonjour", loadDelayNanoseconds: delay)
      let viewModel = RealtimeTranslateViewModel(
        state: .setup, speechRecognizer: FakeSpeechRecognizer(), translationRuntime: runtime
      )

      viewModel.startSession()
      XCTAssertTrue(viewModel.canCancelModelPreparation)
      XCTAssertFalse(viewModel.isSessionLive)

      viewModel.endSession()

      XCTAssertEqual(viewModel.state, .setup)
      XCTAssertFalse(viewModel.canCancelModelPreparation)
      XCTAssertTrue(viewModel.canStartSession)
      XCTAssertEqual(runtime.cancelLoadCount, 1)
    }
    // Nothing else offers to cancel: the slot is Start, End, or Cancel, never two of them.
    for state: SessionState in [.setup, .ready, .permissionRequired, .modelLoadFailed("nope")] {
      let idle = RealtimeTranslateViewModel(state: state, speechRecognizer: FakeSpeechRecognizer(),
                                            translationRuntime: FakeTranslationRuntime())
      XCTAssertFalse(idle.canCancelModelPreparation, "\(state)")
    }
  }

  /// Every one of the 38 reading languages has to have a name in every language this app ships,
  /// and none of them may fall back to a raw code. `zh-Hant` is the one the language-code lookup
  /// gets wrong on its own: it answers `Chinese`, which is already what `zh` is called.
  func testEveryReadingLanguageIsNamedInEveryShippingLanguage() {
    for identifier in ["en", "fr", "es"] {
      let locale = Locale(identifier: identifier)
      var seen: [String: String] = [:]
      for language in TargetLanguage.hyMT2Candidates {
        let name = try? XCTUnwrap(TargetLanguage.localizedName(for: language.code, in: locale),
                                  "\(language.code) has no name in \(identifier)")
        guard let name else { continue }
        XCTAssertFalse(name.isEmpty)
        XCTAssertNotEqual(name, language.code, "\(language.code) fell back to its raw code")
        XCTAssertNil(seen[name], "\(identifier): \(name) names both \(seen[name] ?? "") and \(language.code)")
        seen[name] = language.code
      }
      XCTAssertEqual(seen.count, 38)
    }
    XCTAssertEqual(TargetLanguage.localizedName(for: "zh-Hant", in: Locale(identifier: "en")),
                   "Chinese, Traditional")
    XCTAssertEqual(TargetLanguage.localizedName(for: "yue", in: Locale(identifier: "fr")),
                   "cantonais")
    // A code the platform cannot name keeps the English name rather than showing a raw code.
    XCTAssertNil(TargetLanguage.localizedName(for: "zzz", in: Locale(identifier: "en")))
    XCTAssertEqual(TargetLanguage(("zzz", "Nowherese")).displayName, "Nowherese")
    // Mid-sentence as the locale spells it, standalone with only the first letter raised.
    XCTAssertEqual(TargetLanguage.sentenceCased("chinois traditionnel"), "Chinois traditionnel")
    XCTAssertEqual(TargetLanguage.hyMT2Candidates[1].menuName, "English")
  }

  /// Catalogue order put Ukrainian at number 33 of 38 in a menu with no search. The two languages
  /// the conversation is using come first, then the phone's own, then the rest alphabetically by
  /// the name on screen rather than by the English name nobody is reading.
  func testTheReadingMenuPinsTheConversationsLanguagesThenSortsByTheNameOnScreen() {
    let english = TargetLanguage.hyMT2Candidates[1]
    let korean = TargetLanguage.hyMT2Candidates[9]
    let order = TargetLanguage.menuOrder(pinning: [korean, english], deviceLanguageCode: "fr")

    XCTAssertEqual(order.count, 38, "every language is still offered, exactly once")
    XCTAssertEqual(Set(order), Set(TargetLanguage.hyMT2Candidates))
    XCTAssertEqual(order.prefix(3).map(\.code), ["ko", "en", "fr"])

    let rest = order.dropFirst(3)
    XCTAssertEqual(rest.map(\.displayName),
                   rest.map(\.displayName).sorted { $0.localizedStandardCompare($1) == .orderedAscending })
    // A device language already in the pinned pair is not offered twice.
    let deduped = TargetLanguage.menuOrder(pinning: [english, korean], deviceLanguageCode: "en")
    XCTAssertEqual(deduped.prefix(2).map(\.code), ["en", "ko"])
    XCTAssertEqual(deduped.count, 38)
    // A device language the model cannot read is simply not pinned.
    XCTAssertEqual(TargetLanguage.menuOrder(pinning: [english], deviceLanguageCode: "sw").first?.code,
                   "en")
  }

  private func readyViewModel(
    _ recognizer: FakeSpeechRecognizer,
    runtime: FakeTranslationRuntime = FakeTranslationRuntime(result: "Translated"),
    speechOutput: FakeSpeechOutput? = nil,
    interruptions: FakeAudioInterruptions? = nil
  ) -> RealtimeTranslateViewModel {
    // Spoken output is faked everywhere a translation completes, so the suite never claims the
    // host's audio session on its way past a delivered turn.
    RealtimeTranslateViewModel(state: .ready, speechRecognizer: recognizer,
                               translationRuntime: runtime,
                               speechOutput: speechOutput ?? FakeSpeechOutput(),
                               audioInterruptions: interruptions ?? FakeAudioInterruptions())
  }

  private func waitUntil(_ condition: @escaping () -> Bool) async {
    for _ in 0 ..< 100 where !condition() {
      try? await Task.sleep(nanoseconds: 1_000_000)
    }
    XCTAssertTrue(condition())
  }
}

private enum TestError: Error { case failed }

/// A throwaway `UserDefaults` suite, plus the one reading that has to bypass the search list.
///
/// `AppleLanguages` lives in the global domain on every device, so `array(forKey:)` on a suite
/// falls through and answers with the phone's own language order whatever the suite holds. Reading
/// the suite's persistent domain is the only way to see what this app actually wrote.
private struct ScratchDefaults {
  let name: String
  let defaults: UserDefaults

  var appleLanguages: [String]? {
    UserDefaults.standard.persistentDomain(forName: name)?[AppLanguageDefaults.appleLanguagesKey]
      as? [String]
  }
}

/// `Sources/Localizable.xcstrings`, read as JSON.
///
/// The catalog is a build input, not a bundled resource: what ships is the compiled
/// `en.lproj/Localizable.strings`, which cannot answer questions about comments, extraction state,
/// or which languages are populated. So this reads the source file from the checkout, located from
/// `#filePath`, which is where the language experts will read it from too.
struct StringCatalogFixture {
  struct Entry {
    let comment: String?
    let extractionState: String?
    /// Language to value. Empty for an entry whose key is its own English value.
    let values: [String: String]
    /// Language to translation state. `xcstringstool compile` emits only `translated` entries.
    let states: [String: String]
  }

  let sourceLanguage: String
  let strings: [String: Entry]
}

extension RealtimeTranslateTests {
  /// The languages the catalog is allowed to carry. A fourth one appearing here means someone
  /// started a pass without the plumbing (`project.yml`, the drawer row) that goes with it.
  static let shippingLanguages: Set<String> = ["en", "fr", "es"]

  /// The `%@` / `%lld` / `%%` specifiers in a value, positional indices stripped, sorted. A
  /// translation may reorder its arguments, so only the multiset has to match English.
  static func formatSpecifiers(in value: String) -> [String] {
    let pattern = try! NSRegularExpression(pattern: "%(?:\\d+\\$)?(?:lld|@)|%%")
    let range = NSRange(value.startIndex ..< value.endIndex, in: value)
    return pattern.matches(in: value, range: range)
      .compactMap { Range($0.range, in: value).map { String(value[$0]) } }
      .map { $0.replacingOccurrences(of: "\\d+\\$", with: "", options: .regularExpression) }
      .sorted()
  }

  /// The compiled `.lproj` inside the app bundle, which is what a lookup actually reads. Going
  /// through the bundle rather than the source catalog is the point: it proves the entries
  /// survived `xcstringstool compile` and shipped.
  static func localizedBundle(_ language: String) throws -> Bundle {
    let url = try XCTUnwrap(Bundle.main.url(forResource: language, withExtension: "lproj"),
                            "\(language).lproj is missing from the app bundle")
    return try XCTUnwrap(Bundle(url: url), "\(language).lproj is not loadable as a bundle")
  }

  static func stringCatalog(file: StaticString = #filePath) throws -> StringCatalogFixture {
    let url = URL(fileURLWithPath: "\(file)")
      .deletingLastPathComponent()      // Tests
      .deletingLastPathComponent()      // ios
      .appendingPathComponent("Sources/Localizable.xcstrings")
    let root = try XCTUnwrap(
      JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any],
      "Localizable.xcstrings is not readable at \(url.path)"
    )
    let strings = try XCTUnwrap(root["strings"] as? [String: [String: Any]])
    return StringCatalogFixture(
      sourceLanguage: try XCTUnwrap(root["sourceLanguage"] as? String),
      strings: strings.mapValues { entry in
        let localizations = entry["localizations"] as? [String: [String: Any]] ?? [:]
        return StringCatalogFixture.Entry(
          comment: entry["comment"] as? String,
          extractionState: entry["extractionState"] as? String,
          values: localizations.compactMapValues { ($0["stringUnit"] as? [String: Any])?["value"] as? String },
          states: localizations.compactMapValues { ($0["stringUnit"] as? [String: Any])?["state"] as? String }
        )
      }
    )
  }
}

private final class FakePasteboard: SettingsPasteboard {
  private(set) var written: [String] = []
  func write(_ text: String) { written.append(text) }
}

private final class FakeIdleTimer: IdleTimerControlling {
  private(set) var written: [Bool] = []
  func setIdleTimerDisabled(_ disabled: Bool) { written.append(disabled) }
}

@MainActor
private final class FakeHaptics: HapticSink {
  private(set) var played: [HapticEvent] = []
  func play(_ event: HapticEvent) { played.append(event) }
}

@MainActor
private final class FakeSpeechOutput: SpeechOutput {
  enum Event: Equatable { case speak, stop }

  private(set) var spoken: [(text: String, languageCode: String)] = []
  private(set) var stopCount = 0
  private(set) var events: [Event] = []
  var isSpeaking = false

  func speak(text: String, languageCode: String) {
    spoken.append((text: text, languageCode: languageCode))
    events.append(.speak)
    isSpeaking = true
  }

  func stop() {
    stopCount += 1
    events.append(.stop)
    isSpeaking = false
  }
}

private final class FakeSpeechAudioSession: SpeechAudioSession {
  enum Event: Equatable { case activate, deactivate }

  private(set) var events: [Event] = []
  var activationError: Error?

  func activatePlayback() throws {
    events.append(.activate)
    if let activationError { throw activationError }
  }

  func deactivate() { events.append(.deactivate) }
}

@MainActor
private final class FakeAudioInterruptions: AudioInterruptionObserving {
  private var handler: ((AudioInterruptionEvent) -> Void)?

  func observe(_ handler: @escaping (AudioInterruptionEvent) -> Void) { self.handler = handler }

  /// Stands in for the phone call, the alarm, or the unplugged headset.
  func send(_ event: AudioInterruptionEvent) { handler?(event) }
}

@MainActor
private final class FakeSpeechRecognizer: SpeechRecognizing {
  private var onPartial: ((String) -> Void)?
  private var onFinal: ((String) -> Void)?
  var sourceLanguages: [SpeechSourceLanguage] = []
  /// What only the off-the-main-actor reader knows, standing in for a launch that has not asked
  /// the platform yet. Absent, both readers answer with `sourceLanguages`.
  var deferredSourceLanguages: [SpeechSourceLanguage]?
  private(set) var startedSources: [SpeechSourceLanguage] = []
  private(set) var finishCount = 0
  private(set) var stopCount = 0

  var permission: SpeechPermission = .granted
  var startError: Error?

  init(startError: Error? = nil, permission: SpeechPermission = .granted) {
    self.startError = startError
    self.permission = permission
  }

  func requestPermissions() async -> SpeechPermission { permission }
  func currentPermission() -> SpeechPermission { permission }
  func availableSourceLanguages() -> [SpeechSourceLanguage] { sourceLanguages }
  nonisolated func loadAvailableSourceLanguages() async -> [SpeechSourceLanguage] {
    await MainActor.run { deferredSourceLanguages ?? sourceLanguages }
  }
  func start(source: SpeechSourceLanguage, onPartial: @escaping (String) -> Void,
             onFinal: @escaping (String) -> Void) throws {
    if let startError { throw startError }
    startedSources.append(source)
    self.onPartial = onPartial
    self.onFinal = onFinal
  }
  func finish() { finishCount += 1 }
  func stop() { stopCount += 1 }
  func sendPartial(_ transcript: String) { onPartial?(transcript) }
  func sendFinal(_ transcript: String) { onFinal?(transcript) }
}

/// The runtime seam, with enough of the real one's lifecycle to be worth asserting against: a
/// model that becomes resident when a load finishes and stays resident until it is closed, a load
/// that can be cancelled, and a translation slow enough to still be in flight when a session ends.
private final class FakeTranslationRuntime: TranslationRuntime {
  let result: String
  let loadError: Error?
  let translateError: Error?
  let closeDelayNanoseconds: UInt64
  let loadDelayNanoseconds: UInt64
  let translateDelayNanoseconds: UInt64
  private(set) var loadCount = 0
  private(set) var closeCount = 0
  private(set) var cancelLoadCount = 0
  private(set) var loadCancelled = false
  private(set) var translateStarted = false
  private(set) var translateCancelled = false
  private(set) var prompts: [String] = []
  /// Errors handed out one per call, ahead of `translateError`, so a retry test can fail the first
  /// attempt and let the second one through.
  var queuedTranslateErrors: [Error?] = []
  /// Mirrors the real runtime: set when a load installs a model, cleared only by `close`, and in
  /// particular not cleared by ending a session.
  private(set) var isModelResident = false

  init(result: String = "", loadError: Error? = nil, translateError: Error? = nil,
       closeDelayNanoseconds: UInt64 = 0, loadDelayNanoseconds: UInt64 = 0,
       translateDelayNanoseconds: UInt64 = 0) {
    self.result = result
    self.loadError = loadError
    self.translateError = translateError
    self.closeDelayNanoseconds = closeDelayNanoseconds
    self.loadDelayNanoseconds = loadDelayNanoseconds
    self.translateDelayNanoseconds = translateDelayNanoseconds
  }

  func load(onProgress: @escaping @Sendable (Double) -> Void) async throws {
    loadCount += 1
    onProgress(0.5)
    if loadDelayNanoseconds > 0 {
      do {
        try await Task.sleep(nanoseconds: loadDelayNanoseconds)
      } catch {
        loadCancelled = true
        throw error
      }
    }
    if let loadError { throw loadError }
    onProgress(1)
    isModelResident = true
  }

  func translate(prompt: String) async throws -> String {
    prompts.append(prompt)
    translateStarted = true
    let queued = queuedTranslateErrors.isEmpty ? nil : queuedTranslateErrors.removeFirst()
    if translateDelayNanoseconds > 0 {
      do {
        try await Task.sleep(nanoseconds: translateDelayNanoseconds)
      } catch {
        translateCancelled = true
        throw error
      }
    }
    if let queued { throw queued }
    if let translateError { throw translateError }
    return result
  }

  func cancelLoad() { cancelLoadCount += 1 }

  func close() async {
    if closeDelayNanoseconds > 0 { try? await Task.sleep(nanoseconds: closeDelayNanoseconds) }
    closeCount += 1
    isModelResident = false
  }
}

/// A counter shared with `@Sendable` closures, so a test can watch how many times something was
/// built or attempted without capturing `inout` state.
private final class Counter: @unchecked Sendable {
  private let lock = NSLock()
  private var count = 0

  var value: Int {
    lock.lock()
    defer { lock.unlock() }
    return count
  }

  @discardableResult
  func increment() -> Int {
    lock.lock()
    defer { lock.unlock() }
    count += 1
    return count
  }
}

/// A one-way gate, so a test can hold a model build open across a `close` and let it finish
/// afterwards. This is the only way to express the close-during-load interleaving: the race is
/// between an SDK init that takes minutes and a session that ends in the middle of it.
private actor AsyncGate {
  private var isOpen = false
  private var waiters: [CheckedContinuation<Void, Never>] = []

  func open() {
    guard !isOpen else { return }
    isOpen = true
    let resuming = waiters
    waiters = []
    for waiter in resuming { waiter.resume() }
  }

  func wait() async {
    guard !isOpen else { return }
    await withCheckedContinuation { waiters.append($0) }
  }
}

/// A loaded model that records what the runtime did to it. Enough of the real surface to be run
/// through `translate`: one token, then finished.
private final class SpyLanguageModel: LoadedLanguageModel, @unchecked Sendable {
  var onClose: (() -> Void)?

  private let output: String
  private let lock = NSLock()
  private var tokensDelivered = 0
  private var cleanUps = 0
  private var closes = 0

  init(output: String) { self.output = output }

  var cleanUpCount: Int {
    lock.lock()
    defer { lock.unlock() }
    return cleanUps
  }

  var closeCount: Int {
    lock.lock()
    defer { lock.unlock() }
    return closes
  }

  func run(_ text: String) throws {
    lock.lock()
    tokensDelivered = 0
    lock.unlock()
  }

  func waitForNextToken() -> LLMNextTokenResult {
    lock.lock()
    tokensDelivered += 1
    let first = tokensDelivered == 1
    lock.unlock()
    return LLMNextTokenResult(token: first ? output : "", generatedTokens: first ? 1 : 0,
                              code: 0, isFinal: true)
  }

  func cleanUp() throws {
    lock.lock()
    cleanUps += 1
    lock.unlock()
  }

  func close() {
    lock.lock()
    closes += 1
    lock.unlock()
    onClose?()
  }
}
