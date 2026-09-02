import AVFAudio
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

  // MARK: - Session comfort

  func testScreenStaysAwakeExactlyWhileASessionIsLive() {
    let live: [SessionState] = [
      .ready, .listening(.a), .listening(.b), .finalizing(.a), .translating(.b), .error("nope")
    ]
    let idle: [SessionState] = [
      .permissionRequired, .setup, .loadingModel(nil), .loadingModel(0.5),
      .modelLoadFailed("nope"), .endingSession, .ended
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
      state: .ended, items: [previewTranslatedItem], speechRecognizer: FakeSpeechRecognizer(),
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
    XCTAssertFalse(SessionState.ended.isRecognizerLive)
    XCTAssertFalse(SessionState.setup.isRecognizerLive)
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
    for state in [SessionState.setup, .ended, .loadingModel(0.5), .permissionRequired] {
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

  func testTypedInputCopyNamesBothLanguagesAndUsesNoEmDash() {
    let guidance = TypedInputCopy.guidance(speaker: .a, typing: .hyMT2Candidates[1],
                                           translatedTo: .hyMT2Candidates[9])
    XCTAssertEqual(guidance, "Speaker A types in English. It is translated into Korean for B.")
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

  func testTheStorageRowNamesTheSizeAndLocksWhileASessionHoldsTheModel() {
    let footprint = LocalModelStore.Footprint(archiveBytes: 1_000_000_000, moduleBytes: 1_000_000_000,
                                              totalBytes: 2_000_000_000)
    let size = ModelStorageCopy.size(bytes: 2_000_000_000)

    let idle = ModelStorageRow.row(footprint: footprint, isSessionLive: false)
    XCTAssertTrue(idle.isEnabled)
    XCTAssertEqual(idle.subtitle, "\(size) on this phone")
    XCTAssertTrue(idle.accessibilityLabel.contains(ModelStorageCopy.deleteAction))

    // A loaded model cannot be deleted from under the session that is using it.
    let live = ModelStorageRow.row(footprint: footprint, isSessionLive: true)
    XCTAssertFalse(live.isEnabled)
    XCTAssertTrue(live.subtitle.contains(size))
    XCTAssertTrue(live.subtitle.contains("End the session first"))

    let empty = ModelStorageRow.row(footprint: .none, isSessionLive: false)
    XCTAssertFalse(empty.isEnabled)
    XCTAssertEqual(empty.subtitle, "No model downloaded")

    for line in [ModelStorageCopy.title, ModelStorageCopy.empty, ModelStorageCopy.deleteAction,
                 ModelStorageCopy.keepAction, ModelStorageCopy.confirmationTitle,
                 ModelStorageCopy.sessionLive, ModelStorageCopy.deleted,
                 ModelStorageCopy.confirmationMessage(size), idle.subtitle, live.subtitle] {
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
    XCTAssertTrue(model.storageRow(isSessionLive: false).isEnabled)
    XCTAssertFalse(model.isConfirmingDelete)

    // The row asks. It does not delete.
    model.confirmDeleteModel()
    XCTAssertTrue(model.isConfirmingDelete)
    XCTAssertEqual(storage.deletions, 0)

    model.deleteModel()

    XCTAssertFalse(model.isConfirmingDelete)
    XCTAssertEqual(storage.deletions, 1)
    XCTAssertTrue(model.storage.isEmpty)
    XCTAssertEqual(model.storageRow(isSessionLive: false).subtitle, "No model downloaded")
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
    })

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
  private(set) var startedSources: [SpeechSourceLanguage] = []
  private(set) var finishCount = 0
  private(set) var stopCount = 0

  var permission: SpeechPermission = .granted
  var startError: Error?

  func requestPermissions() async -> SpeechPermission { permission }
  func currentPermission() -> SpeechPermission { permission }
  func availableSourceLanguages() -> [SpeechSourceLanguage] { sourceLanguages }
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

private final class FakeTranslationRuntime: TranslationRuntime {
  let result: String
  let loadError: Error?
  let translateError: Error?
  let closeDelayNanoseconds: UInt64
  private(set) var loadCount = 0
  private(set) var closeCount = 0
  private(set) var prompts: [String] = []

  init(result: String = "", loadError: Error? = nil, translateError: Error? = nil,
       closeDelayNanoseconds: UInt64 = 0) {
    self.result = result
    self.loadError = loadError
    self.translateError = translateError
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
    if let translateError { throw translateError }
    return result
  }

  func close() async {
    if closeDelayNanoseconds > 0 { try? await Task.sleep(nanoseconds: closeDelayNanoseconds) }
    closeCount += 1
  }
}
