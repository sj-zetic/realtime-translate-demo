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
    let temporary = root.appendingPathComponent("scratch", isDirectory: true)
    try manager.createDirectory(at: temporary, withIntermediateDirectories: true)
    let partial = temporary.appendingPathComponent("CFNetworkDownload_ab12cd.tmp")
    let unrelated = temporary.appendingPathComponent("keep-me.tmp")
    try Data([0]).write(to: partial)
    try Data([0]).write(to: unrelated)

    LocalModelStore.sweepOrphans(cacheRoot: root, temporaryDirectory: temporary)

    XCTAssertFalse(manager.fileExists(atPath: swept.path))
    XCTAssertFalse(manager.fileExists(atPath: partial.path))
    XCTAssertTrue(manager.fileExists(atPath: unrelated.path))
    for directory in kept { XCTAssertTrue(manager.fileExists(atPath: directory.path), directory.lastPathComponent) }
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
    let firstRun = FirstRunModel(path: FixedNetworkPath(.expensive), hasLocalModel: { false })

    firstRun.requestSessionStart { starts += 1 }
    XCTAssertEqual(starts, 0)
    XCTAssertEqual(firstRun.consent, FirstRunModel.ConsentPrompt(cellularWarning: true))

    firstRun.acceptConsent()
    XCTAssertEqual(starts, 1)
    XCTAssertNil(firstRun.consent)
  }

  func testDecliningConsentDismissesTheStepWithoutStartingTheDownload() {
    var starts = 0
    let firstRun = FirstRunModel(path: FixedNetworkPath(.unrestricted), hasLocalModel: { false })

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
    XCTAssertNil(ModelPreparationStatus.status(for: nil).progress)
    XCTAssertNil(ModelPreparationStatus.status(for: nil).detail)
    // 0 and 1 are the local-load bookends, not a download in flight.
    XCTAssertFalse(ModelPreparationStatus.status(for: 0).isDownloading)
    XCTAssertFalse(ModelPreparationStatus.status(for: 1).isDownloading)

    let downloading = ModelPreparationStatus.status(for: 0.32)
    XCTAssertTrue(downloading.isDownloading)
    XCTAssertEqual(downloading.headline, "Downloading translation model 32%")
    XCTAssertEqual(downloading.detail, "0.6 of 1.9 GB")
    XCTAssertEqual(ModelPreparationStatus.status(for: 0.5).detail, "1.0 of 1.9 GB")
    XCTAssertEqual(ModelPreparationStatus.status(for: 0.95).headline,
                   "Downloading translation model 95%")
    XCTAssertEqual(ModelPreparationStatus.status(for: 0.95).detail, "1.8 of 1.9 GB")
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
    XCTAssertEqual(FirstRunCopy.consentSize, "The translation model is about 1.9 GB.")
  }

  /// Mirrors the schema the SDK writes, with dummy checksums and a dummy secret key.
  private func makeCacheFixture(archiveByteCount: Int = 8, indexedByteCount: Int = 8) throws -> URL {
    let manager = FileManager.default
    let container = manager.temporaryDirectory.appendingPathComponent("LocalModelStore-\(UUID().uuidString)")
    let root = container.appendingPathComponent("ZeticMLangeCache", isDirectory: true)
    addTeardownBlock { try? manager.removeItem(at: container) }
    let relativePath = "artifacts/aaaa/llmTargetModel-c488c23ffebf7fd0/Hy_MT2_1.ztc"
    let archive = root.appendingPathComponent(relativePath)
    try manager.createDirectory(at: archive.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data(repeating: 0, count: archiveByteCount).write(to: archive)
    let index = """
      {"schemaVersion":1,"artifacts":[{"createdAt":809969480.2,"id":"llmTargetModel-c488c23ffebf7fd0",\
      "kind":"llmTargetModel","modelKey":"aaaa","ownedArtifactIDs":[],"primaryRelativePath":"\(relativePath)",\
      "selector":{"apType":"GPU","llmTarget":"LLAMA_CPP"},"storedFiles":[{"byteCount":\(indexedByteCount),\
      "checksum":"00000000000000000000000000000000","relativePath":"\(relativePath)",\
      "validationState":"checksumValidated"}],"updatedAt":809969480.2}],\
      "resolvedModels":[{"logicalRef":{"kind":"llm","name":"SJ_zetic/Hy-MT2-1.8B"},"modelKey":"aaaa",\
      "updatedAt":809969926.4}]}
      """
    try index.write(to: root.appendingPathComponent("cache-index.json"), atomically: true, encoding: .utf8)
    let records = root.appendingPathComponent("backend-selection-last-known-good", isDirectory: true)
    try manager.createDirectory(at: records, withIntermediateDirectories: true)
    let record = """
      {"candidate_artifact_id":"llmTargetModel-c488c23ffebf7fd0","schema_version":1,\
      "response":{"candidate":{"checksum":"00000000000000000000000000000000",\
      "secret_key":"\(String(repeating: "0", count: 64))"},"model_key":"aaaa"}}
      """
    try record.write(to: records.appendingPathComponent("dummy.json"), atomically: true, encoding: .utf8)
    return root
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

private final class FakePasteboard: SettingsPasteboard {
  private(set) var written: [String] = []
  func write(_ text: String) { written.append(text) }
}

@MainActor
private final class FakeSpeechRecognizer: SpeechRecognizing {
  private var onPartial: ((String) -> Void)?
  private var onFinal: ((String) -> Void)?
  var sourceLanguages: [SpeechSourceLanguage] = []
  private(set) var startedSources: [SpeechSourceLanguage] = []
  private(set) var finishCount = 0
  private(set) var stopCount = 0

  var permission: SpeechPermission = .granted

  func requestPermissions() async -> SpeechPermission { permission }
  func currentPermission() -> SpeechPermission { permission }
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
