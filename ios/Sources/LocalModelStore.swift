import Foundation

/// Reads the model cache the Melange SDK maintains on disk so a cold launch can load an archive
/// that is already complete instead of downloading it again. The SDK mints a fresh
/// `llmTargetModel-<id>` whenever the presigned download URL it derives the cache key from is
/// re-signed, so a validated 1.9 GB archive can sit unused next to a download that restarts at zero.
///
/// Pure Foundation, no SDK types, and best effort throughout: a missing file, an unreadable
/// directory, or any schema surprise means "nothing local", never a crash and never a throw.
enum LocalModelStore {
  struct Archive {
    let url: URL
    let artifactID: String
    let modelKey: String
  }

  static var cacheRoot: URL? {
    FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
      .appendingPathComponent("ZeticMLangeCache", isDirectory: true)
  }

  /// The newest complete archive for `name`: a stored `.ztc` whose size on disk matches the size
  /// the index recorded. A truncated file would fail the local init on every launch, so only an
  /// exact match counts. Checksum-validated entries win over merely present ones.
  static func discoverArchive(forModelName name: String,
                              cacheRoot root: URL? = LocalModelStore.cacheRoot) -> Archive? {
    discoverStoredFile(forModelName: name, fileExtension: "ztc", cacheRoot: root)
  }

  /// The newest complete extracted module (the decrypted `.gguf` the SDK unpacks from the archive).
  /// Same completeness rule as the archive: exact on-disk size match against the index.
  static func discoverExtractedModule(forModelName name: String,
                                      cacheRoot root: URL? = LocalModelStore.cacheRoot) -> Archive? {
    discoverStoredFile(forModelName: name, fileExtension: "gguf", cacheRoot: root)
  }

  private static func discoverStoredFile(forModelName name: String, fileExtension: String,
                                         cacheRoot root: URL?) -> Archive? {
    guard let root, let index = readIndex(root, fileExtension: fileExtension) else { return nil }
    guard let modelKey = resolveModelKey(name, in: index) else { return nil }

    let candidates = index.entries
      .filter { $0.modelKey == modelKey }
      .sorted { lhs, rhs in
        lhs.validated == rhs.validated ? lhs.createdAt > rhs.createdAt : lhs.validated
      }
    for entry in candidates {
      let url = root.appendingPathComponent(entry.relativePath)
      guard isContained(url, in: root), url.pathExtension == fileExtension else { continue }
      guard entry.byteCount > 0, fileSize(url) == entry.byteCount else { continue }
      return Archive(url: url, artifactID: entry.id, modelKey: entry.modelKey)
    }
    return nil
  }

  /// The decryption key the SDK persisted for `artifactID`. Archives downloaded at runtime are
  /// encrypted, so the local init needs it. The value is returned to the caller and nowhere else:
  /// it must never be logged, printed, or placed in an error message.
  static func secretKeyHex(forArtifactID artifactID: String,
                           cacheRoot root: URL? = LocalModelStore.cacheRoot) -> String? {
    guard let root else { return nil }
    let folders = ["backend-selection-last-known-good", "backend-selection-responses"]
    for folder in folders {
      let directory = root.appendingPathComponent(folder, isDirectory: true)
      let files = (try? FileManager.default.contentsOfDirectory(at: directory,
                                                                includingPropertiesForKeys: nil)) ?? []
      for file in files where file.pathExtension == "json" {
        guard let record = readObject(file) else { continue }
        let candidate = (record["response"] as? [String: Any])?["candidate"] as? [String: Any]
        let names = [record["candidate_artifact_id"] as? String, candidate?["artifact_id"] as? String]
        guard names.contains(artifactID) else { continue }
        if let key = candidate?["secret_key"] as? String ?? record["secret_key"] as? String { return key }
      }
    }
    return nil
  }

  /// Removes what an interrupted key mint leaves behind: partial downloads, and the empty artifact
  /// directories the SDK creates before a download it never finishes.
  ///
  /// Safety rules, in order: only paths physically inside the root being swept (symlinks resolved),
  /// only `llmTargetModel-<16 hex>` directory names, only ids absent from the index, only genuinely
  /// empty directories. Anything unreadable, unparseable, or ambiguous is skipped. Nothing under
  /// `staging-locks` or `backend-selection-*` is ever touched, and any indexed artifact is off
  /// limits. Downloads in flight in this process cannot be affected: partials from a previous
  /// process are the only ones on disk when this runs, before any load begins.
  static func sweepOrphans(cacheRoot root: URL? = LocalModelStore.cacheRoot,
                           temporaryDirectory temporary: URL = FileManager.default.temporaryDirectory) {
    let manager = FileManager.default
    // Partials land in the app's temporary directory, and in the cache root's own `tmp` when the
    // SDK stages there; sweep both, each contained in its own root.
    var partialRoots = [temporary]
    if let root { partialRoots.append(root.appendingPathComponent("tmp", isDirectory: true)) }
    for partialRoot in partialRoots {
      let files = (try? manager.contentsOfDirectory(at: partialRoot, includingPropertiesForKeys: nil)) ?? []
      for file in files where file.lastPathComponent.hasPrefix("CFNetworkDownload_")
        && file.pathExtension == "tmp" && isContained(file, in: partialRoot) {
        try? manager.removeItem(at: file)
      }
    }

    // Without a parseable index there is no way to tell an aborted mint from the live artifact.
    guard let root, let index = readIndex(root) else { return }
    let known = Set(index.entries.map(\.id))
    let artifacts = root.appendingPathComponent("artifacts", isDirectory: true)
    let modelDirectories = (try? manager.contentsOfDirectory(at: artifacts,
                                                             includingPropertiesForKeys: nil)) ?? []
    for modelDirectory in modelDirectories {
      let entries = (try? manager.contentsOfDirectory(at: modelDirectory, includingPropertiesForKeys: nil)) ?? []
      for entry in entries {
        let name = entry.lastPathComponent
        guard isArtifactDirectoryName(name), !known.contains(name), isContained(entry, in: artifacts) else {
          continue
        }
        guard let contents = try? manager.contentsOfDirectory(atPath: entry.path), contents.isEmpty else {
          continue
        }
        try? manager.removeItem(at: entry)
      }
    }
  }

  // MARK: - Index

  private struct Entry {
    let id: String
    let modelKey: String
    let relativePath: String
    let byteCount: Int64
    let createdAt: Double
    let validated: Bool
  }

  private struct Index {
    let entries: [Entry]
    let modelKeysByName: [String: String]
  }

  /// Tolerant by design: every field is optional, every shape mismatch drops just that entry, and
  /// an index the SDK writes in some future shape simply yields nothing to load locally.
  private static func readIndex(_ root: URL, fileExtension: String = "ztc") -> Index? {
    guard let object = readObject(root.appendingPathComponent("cache-index.json")) else { return nil }

    var raw: [(key: String?, artifact: [String: Any])] = []
    if let list = object["artifacts"] as? [[String: Any]] {
      raw = list.map { (nil, $0) }
    } else if let grouped = object["artifacts"] as? [String: [[String: Any]]] {
      raw = grouped.flatMap { key, list in list.map { (key, $0) } }
    } else {
      return nil
    }

    let entries: [Entry] = raw.compactMap { key, artifact in
      guard let id = artifact["id"] as? String,
            let modelKey = artifact["modelKey"] as? String ?? key,
            let stored = artifact["storedFiles"] as? [[String: Any]] else { return nil }
      let archives = stored.filter { ($0["relativePath"] as? String)?.hasSuffix("." + fileExtension) == true }
      let file = archives.first { $0["validationState"] as? String == "checksumValidated" } ?? archives.first
      guard let file, let relativePath = file["relativePath"] as? String,
            let byteCount = (file["byteCount"] as? NSNumber)?.int64Value else { return nil }
      return Entry(
        id: id, modelKey: modelKey, relativePath: relativePath, byteCount: byteCount,
        createdAt: (artifact["createdAt"] as? NSNumber)?.doubleValue ?? 0,
        validated: file["validationState"] as? String == "checksumValidated"
      )
    }

    var names: [String: String] = [:]
    if let resolved = object["resolvedModels"] as? [[String: Any]] {
      for model in resolved {
        guard let modelKey = model["modelKey"] as? String,
              let name = (model["logicalRef"] as? [String: Any])?["name"] as? String else { continue }
        names[name] = modelKey
      }
    } else if let resolved = object["resolvedModels"] as? [String: String] {
      names = resolved
    }
    return Index(entries: entries, modelKeysByName: names)
  }

  /// The index's own name mapping, or the sole model key on disk when there is exactly one. More
  /// than one and no mapping means we cannot tell which archive belongs to this app's model.
  private static func resolveModelKey(_ name: String, in index: Index) -> String? {
    if let key = index.modelKeysByName[name] { return key }
    let keys = Set(index.entries.map(\.modelKey))
    return keys.count == 1 ? keys.first : nil
  }

  // MARK: - Filesystem helpers

  private static func readObject(_ url: URL) -> [String: Any]? {
    guard let data = try? Data(contentsOf: url),
          let object = try? JSONSerialization.jsonObject(with: data) else { return nil }
    return object as? [String: Any]
  }

  private static func fileSize(_ url: URL) -> Int64? {
    guard let values = try? url.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey]),
          values.isRegularFile == true, let size = values.fileSize else { return nil }
    return Int64(size)
  }

  /// Guards every deletion and every path built from index data: the resolved path must sit strictly
  /// below the resolved root, so a `..` component or a symlinked directory cannot escape it.
  private static func isContained(_ url: URL, in root: URL) -> Bool {
    let rootPath = root.resolvingSymlinksInPath().standardizedFileURL.path
    let path = url.resolvingSymlinksInPath().standardizedFileURL.path
    return path.hasPrefix(rootPath.hasSuffix("/") ? rootPath : rootPath + "/")
  }

  private static func isArtifactDirectoryName(_ name: String) -> Bool {
    let prefix = "llmTargetModel-"
    guard name.hasPrefix(prefix) else { return false }
    let identifier = name.dropFirst(prefix.count)
    return identifier.count == 16 && identifier.allSatisfy { $0.isHexDigit && !$0.isUppercase }
  }
}
