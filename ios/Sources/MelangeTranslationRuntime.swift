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

final class MelangeTranslationRuntime: TranslationRuntime, @unchecked Sendable {
  private static let modelName = "SJ_zetic/Hy-MT2-1.8B"

  private let personalKey: String
  private let queue = DispatchQueue(label: "ai.zetic.turntranslate.melange", qos: .userInitiated)
  private var model: ZeticMLangeLLMModel?

  init(personalKey: String? = nil, infoDictionary: [String: Any] = Bundle.main.infoDictionary ?? [:]) {
    self.personalKey = personalKey ?? MelangeCredential.value(from: infoDictionary)
  }

  func load(onProgress: @escaping @Sendable (Double) -> Void) async throws {
    guard !personalKey.isEmpty else { throw TranslationRuntimeError.missingPersonalKey }
    if queue.sync(execute: { model != nil }) { return }

    let loaded = try await ZeticMLangeLLMModel(
      personalKey: personalKey,
      name: Self.modelName,
      version: nil,
      modelMode: .RUN_AUTO,
      onDownload: { progress in onProgress(Double(progress)) }
    )
    queue.sync { model = loaded }
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
