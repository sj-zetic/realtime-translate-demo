import Foundation
import ZeticMLange

protocol TranslationRuntime: AnyObject {
  func load(onProgress: @escaping @Sendable (Double) -> Void) async throws
  func translate(prompt: String) async throws -> String
  func close() async
}

enum TranslationRuntimeError: LocalizedError, Equatable {
  case missingPersonalKey
  case modelNotLoaded
  case generationFailed(Int)
  case emptyOutput

  var errorDescription: String? {
    switch self {
    case .missingPersonalKey: "The Melange personal key is not configured in this app build."
    case .modelNotLoaded: "The translation model is not loaded."
    case let .generationFailed(code): "The translation model failed with code \(code)."
    case .emptyOutput: "The translation model returned an empty result."
    }
  }
}

enum MelangeCredential {
  static let infoDictionaryKey = "MelangePersonalKey"

  static func value(from infoDictionary: [String: Any]) -> String {
    guard let value = infoDictionary[infoDictionaryKey] as? String else { return "" }
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.hasPrefix("$(") ? "" : trimmed
  }
}

struct TranslationResponseAccumulator {
  private var output = ""

  mutating func append(token: String, generatedTokens: Int, code: Int) throws -> Bool {
    guard code == 0 else { throw TranslationRuntimeError.generationFailed(code) }
    guard generatedTokens > 0 else { return false }
    output.append(token)
    return true
  }

  func finalOutput() throws -> String {
    let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { throw TranslationRuntimeError.emptyOutput }
    return trimmed
  }
}

/// The one loaded-model surface the runtime needs, so a model can come from the managed remote
/// flow or from a file already on disk.
protocol LoadedLanguageModel: AnyObject {
  func run(_ text: String) throws
  func waitForNextToken() -> LLMNextTokenResult
  func cleanUp() throws
  func close()
}

extension ZeticMLangeLLMModel: LoadedLanguageModel {}

/// The SDK's direct GGUF loader has the same run surface but releases through `forceDeinit`.
final class LlamaCppLoadedModel: LoadedLanguageModel {
  private let model: LLaMACppTargetModel
  init(_ model: LLaMACppTargetModel) { self.model = model }
  func run(_ text: String) throws { try model.run(text) }
  func waitForNextToken() -> LLMNextTokenResult { model.waitForNextToken() }
  func cleanUp() throws { try model.cleanUp() }
  func close() { model.forceDeinit() }
}

final class MelangeTranslationRuntime: TranslationRuntime, @unchecked Sendable {
  private static let modelName = "SJ_zetic/Hy-MT2-1.8B"

  private let personalKey: String
  private let queue = DispatchQueue(label: "ai.zetic.turntranslate.melange", qos: .userInitiated)
  private var model: (any LoadedLanguageModel)?
  private var loadTask: Task<Void, Error>?

  init(personalKey: String? = nil, infoDictionary: [String: Any] = Bundle.main.infoDictionary ?? [:]) {
    self.personalKey = personalKey ?? MelangeCredential.value(from: infoDictionary)
  }

  func load(onProgress: @escaping @Sendable (Double) -> Void) async throws {
    guard !personalKey.isEmpty else { throw TranslationRuntimeError.missingPersonalKey }
    // Memoized: `model != nil` is not held across the await, so overlapping calls would otherwise
    // each initialize their own copy of a 1.9 GB model.
    let task: Task<Void, Error>? = queue.sync {
      if model != nil { return nil }
      if let loadTask { return loadTask }
      let started = Task<Void, Error> { [weak self] in
        guard let self else { return }
        let loaded = try await makeModel(onProgress: onProgress)
        queue.sync { self.model = loaded; self.loadTask = nil }
      }
      loadTask = started
      return started
    }
    guard let task else { return }
    do {
      try await task.value
    } catch {
      queue.sync { loadTask = nil }
      throw error
    }
  }

  private func makeModel(onProgress: @escaping @Sendable (Double) -> Void) async throws -> any LoadedLanguageModel {
    // No download callback fires on the local path, so `onProgress` stays uncalled and the screen
    // keeps its indeterminate loading state.
    if let local = await loadLocalModel() { return local }
    return try await ZeticMLangeLLMModel(
      personalKey: personalKey,
      name: Self.modelName,
      version: nil,
      modelMode: .RUN_AUTO,
      onDownload: { progress in onProgress(Double(progress)) }
    )
  }

  /// The SDK re-derives its cache key from the presigned download URL, so a cold launch can restart
  /// a finished 1.9 GB download from zero. Loading the model already on disk avoids that; any
  /// failure here returns nil and the remote flow runs unchanged. Runs on `queue` because the local
  /// inits are synchronous and slow.
  private func loadLocalModel() async -> (any LoadedLanguageModel)? {
    await withCheckedContinuation { continuation in
      queue.async {
        LocalModelStore.sweepOrphans()
        continuation.resume(returning: Self.makeLocalModel())
      }
    }
  }

  // Order matters: the extracted module loads in seconds and needs no decryption, while the
  // archive covers a cache state where the SDK has not extracted yet (it decrypts and unpacks,
  // so it is slow and only works for model families its local loader supports). Logs stay
  // content-free: never key material.
  private static func makeLocalModel() -> (any LoadedLanguageModel)? {
    if let module = LocalModelStore.discoverExtractedModule(forModelName: modelName),
       let quantType = llamaCppQuantType(forModuleNamed: module.url.lastPathComponent) {
      for apType in [APType.GPU, APType.CPU] {
        if let model = try? LLaMACppTargetModel(module.url.path, quantType, apType) {
          NSLog("model load: reusing extracted module, no network needed")
          return LlamaCppLoadedModel(model)
        }
      }
    }
    if let archive = LocalModelStore.discoverArchive(forModelName: modelName) {
      let secretKeyHex = LocalModelStore.secretKeyHex(forArtifactID: archive.artifactID)
      if let model = try? ZeticMLangeLLMModel(
        localZtcURL: archive.url, secretKeyHex: secretKeyHex, modelKey: archive.modelKey
      ) {
        NSLog("model load: reusing downloaded archive, no network needed")
        return model
      }
    }
    NSLog("model load: no reusable local model, using remote flow")
    return nil
  }

  static func llamaCppQuantType(forModuleNamed name: String) -> LLMQuantType? {
    guard name.contains("LLAMA_CPP") else { return nil }
    let markers: [(String, LLMQuantType)] = [
      ("_Q8_0", .GGUF_QUANT_Q8_0), ("_Q6_K", .GGUF_QUANT_Q6_K), ("_Q4_K_M", .GGUF_QUANT_Q4_K_M),
      ("_Q3_K_M", .GGUF_QUANT_Q3_K_M), ("_Q2_K", .GGUF_QUANT_Q2_K), ("_BF16", .GGUF_QUANT_BF16),
      ("_F16", .GGUF_QUANT_F16),
    ]
    return markers.first { name.contains($0.0) }?.1
  }

  func translate(prompt: String) async throws -> String {
    try await withCheckedThrowingContinuation { continuation in
      queue.async { [weak self] in
        guard let self, let model = self.model else {
          continuation.resume(throwing: TranslationRuntimeError.modelNotLoaded)
          return
        }
        defer { try? model.cleanUp() }
        do {
          try model.run(prompt)
          var accumulator = TranslationResponseAccumulator()
          while true {
            let result = model.waitForNextToken()
            let hasToken = try accumulator.append(
              token: result.token, generatedTokens: result.generatedTokens, code: result.code
            )
            if !hasToken || result.isFinished { break }
          }
          continuation.resume(returning: try accumulator.finalOutput())
        } catch {
          continuation.resume(throwing: error)
        }
      }
    }
  }

  func close() async {
    await withCheckedContinuation { continuation in
      queue.async { [weak self] in
        try? self?.model?.cleanUp()
        self?.model?.close()
        self?.model = nil
        continuation.resume()
      }
    }
  }

  deinit {
    queue.sync {
      try? model?.cleanUp()
      model?.close()
      model = nil
    }
  }
}
