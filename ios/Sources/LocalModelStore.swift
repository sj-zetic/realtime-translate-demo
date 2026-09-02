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
  /// only `llmTargetModel-<16 hex>` directory names, only ids absent from either index, only
  /// genuinely empty directories. Anything unreadable, unparseable, or ambiguous is skipped.
  /// Nothing under `staging-locks` or `backend-selection-*` is ever touched, and any indexed
  /// artifact is off limits.
  ///
  /// Partials are swept only from the cache root's own `tmp`, never from the app's shared
  /// temporary directory. That directory is `URLSession`'s too: a `CFNetworkDownload_*.tmp` there
  /// is as likely to be this launch's resumable 1.9 GB transfer as it is to be an abandoned one,
  /// and deleting it turns a download that could have resumed into one that starts again at zero.
  static func sweepOrphans(cacheRoot root: URL? = LocalModelStore.cacheRoot) {
    let manager = FileManager.default
    if let root {
      let partialRoot = root.appendingPathComponent("tmp", isDirectory: true)
      let files = (try? manager.contentsOfDirectory(at: partialRoot, includingPropertiesForKeys: nil)) ?? []
      for file in files where file.lastPathComponent.hasPrefix("CFNetworkDownload_")
        && file.pathExtension == "tmp" && isContained(file, in: partialRoot) {
        try? manager.removeItem(at: file)
      }
    }

    // Without a parseable index there is no way to tell an aborted mint from the live artifact.
    guard let root, let index = readIndex(root) else { return }
    // Both indexes, because they are two readings of the same file: an artifact whose only stored
    // file is the extracted `.gguf` is absent from the `.ztc` reading and would otherwise look
    // like an id nobody claims.
    let known = Set(index.entries.map(\.id))
      .union(readIndex(root, fileExtension: "gguf")?.entries.map(\.id) ?? [])
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

  // MARK: - Storage footprint

  /// Dormant, deliberately. The settings drawer's `Storage` row was removed, so nothing in the app
  /// calls the footprint reading or the delete below any more. Both are kept whole, and kept under
  /// test, because they are the hard part: the containment rules that keep a delete inside this
  /// app's own artifacts took real work to get right, and a future row, or a low-storage prompt,
  /// should find them here rather than start again.

  /// What this app's model occupies on disk, from what this store can actually discover.
  struct Footprint: Equatable {
    /// The stored `.ztc` archive, or 0 when there is none.
    let archiveBytes: Int64
    /// The extracted `.gguf` module, or 0 when there is none.
    let moduleBytes: Int64
    /// Every byte a delete would reclaim: the whole `artifacts/<modelKey>` directory, which is
    /// exactly what `deleteModel` removes. It is at least the two above and can be a little more,
    /// because the SDK keeps its own bookkeeping files in there alongside them.
    let totalBytes: Int64

    static let none = Footprint(archiveBytes: 0, moduleBytes: 0, totalBytes: 0)

    var isEmpty: Bool { totalBytes == 0 }
  }

  /// Read only, and best effort like everything else here: an unreadable directory contributes
  /// nothing rather than failing the whole reading, and a cache with no model for this name
  /// reports `.none` instead of a guess.
  static func footprint(forModelName name: String,
                        cacheRoot root: URL? = LocalModelStore.cacheRoot) -> Footprint {
    guard let root else { return .none }
    let archive = discoverArchive(forModelName: name, cacheRoot: root)
    let module = discoverExtractedModule(forModelName: name, cacheRoot: root)
    guard let modelKey = archive?.modelKey ?? module?.modelKey,
          let directory = modelDirectory(modelKey, in: root) else { return .none }
    return Footprint(
      archiveBytes: archive.flatMap { fileSize($0.url) } ?? 0,
      moduleBytes: module.flatMap { fileSize($0.url) } ?? 0,
      totalBytes: directorySize(directory)
    )
  }

  // MARK: - Deletion

  /// What a delete did. `refused` is the answer to anything ambiguous, because a cache this app
  /// only half understands is a cache it must not remove things from.
  enum Deletion: Equatable {
    case deleted
    case nothingToDelete
    case refused
  }

  /// Removes exactly this model's artifacts: the `artifacts/<modelKey>` directory holding the
  /// archive and the extracted module, and the `cache-index.json` records that name them. The
  /// index is rewritten the way `sweepOrphans` reads it, tolerantly and in place, keeping every
  /// key and every record belonging to anything else byte for byte as it was.
  ///
  /// Safety rules, in the order they are applied: the index must parse (without it there is no way
  /// to tell this app's model from anything else in the cache), the index must name this model
  /// (the sole-key guess that is good enough for loading is not good enough for removing), the
  /// model key must be a single path component, the directory must resolve strictly inside
  /// `artifacts/`, and the rewritten index must both serialize and reach the disk before anything
  /// is removed, so a failure anywhere leaves the cache as it was. Nothing under
  /// `backend-selection-*` or `staging-locks` is ever touched: those records are the SDK's, they
  /// are tiny, and a redownload rewrites them anyway.
  @discardableResult
  static func deleteModel(forModelName name: String,
                          cacheRoot root: URL? = LocalModelStore.cacheRoot) -> Deletion {
    guard let root else { return .refused }
    let indexURL = root.appendingPathComponent("cache-index.json")
    guard let object = readObject(indexURL),
          let modelKey = resolveModelKey(name, cacheRoot: root, allowSoleKeyFallback: false),
          let directory = modelDirectory(modelKey, in: root),
          let data = try? JSONSerialization.data(withJSONObject: pruning(object, modelKey: modelKey))
    else { return .refused }

    let manager = FileManager.default
    let existed = manager.fileExists(atPath: directory.path)
    // The index goes first, and its write is checked. A full disk that swallows this write after
    // the directory was already removed leaves an index promising a model that is not there and
    // whatever called this confirming a delete that only half happened.
    do {
      try data.write(to: indexURL, options: .atomic)
    } catch {
      return .refused
    }
    if existed { try? manager.removeItem(at: directory) }
    return existed ? .deleted : .nothingToDelete
  }

  /// The one path both the footprint and the delete are allowed to name, or nil when the model key
  /// is not a plain directory name or would resolve outside `artifacts/`.
  private static func modelDirectory(_ modelKey: String, in root: URL) -> URL? {
    guard !modelKey.isEmpty, modelKey != ".", modelKey != "..",
          !modelKey.contains("/"), !modelKey.contains("\\"), !modelKey.contains("\0") else {
      return nil
    }
    let artifacts = root.appendingPathComponent("artifacts", isDirectory: true)
    let directory = artifacts.appendingPathComponent(modelKey, isDirectory: true)
    return isContained(directory, in: artifacts) ? directory : nil
  }

  /// Removes every record naming `modelKey`, in whichever of the two shapes the index uses, and
  /// leaves everything else exactly as it was found, unknown keys included.
  private static func pruning(_ object: [String: Any], modelKey: String) -> [String: Any] {
    var object = object
    if let list = object["artifacts"] as? [[String: Any]] {
      object["artifacts"] = list.filter { ($0["modelKey"] as? String) != modelKey }
    } else if var grouped = object["artifacts"] as? [String: [[String: Any]]] {
      grouped.removeValue(forKey: modelKey)
      object["artifacts"] = grouped
    }
    if let list = object["resolvedModels"] as? [[String: Any]] {
      object["resolvedModels"] = list.filter { ($0["modelKey"] as? String) != modelKey }
    } else if var mapping = object["resolvedModels"] as? [String: String] {
      for (name, key) in mapping where key == modelKey { mapping.removeValue(forKey: name) }
      object["resolvedModels"] = mapping
    }
    return object
  }

  /// Every regular file below `url`, summed. A directory that cannot be enumerated reports 0
  /// rather than throwing, which keeps a storage reading from ever being the thing that fails.
  private static func directorySize(_ url: URL) -> Int64 {
    let keys: [URLResourceKey] = [.fileSizeKey, .isRegularFileKey]
    guard let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: keys)
    else { return fileSize(url) ?? 0 }
    var total: Int64 = 0
    for case let file as URL in enumerator { total += fileSize(file) ?? 0 }
    return total
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

  /// The model key for `name`, whichever kind of stored file the cache happens to hold. An index
  /// that will not parse yields nil, which is what makes both the footprint and the delete refuse
  /// a cache they cannot read.
  private static func resolveModelKey(_ name: String, cacheRoot root: URL,
                                      allowSoleKeyFallback: Bool = true) -> String? {
    for fileExtension in ["ztc", "gguf"] {
      guard let index = readIndex(root, fileExtension: fileExtension) else { return nil }
      if let key = resolveModelKey(name, in: index, allowSoleKeyFallback: allowSoleKeyFallback) {
        return key
      }
    }
    return nil
  }

  /// The index's own name mapping, or the sole model key on disk when there is exactly one. More
  /// than one and no mapping means we cannot tell which archive belongs to this app's model.
  ///
  /// The fallback is a guess, and it is only ever the right kind of guess for loading: the worst a
  /// wrong one costs there is an init that fails and a remote load that runs instead. A caller
  /// that is about to remove files by name passes `allowSoleKeyFallback: false`, because the same
  /// guess there deletes somebody else's model out of a shared cache.
  private static func resolveModelKey(_ name: String, in index: Index,
                                      allowSoleKeyFallback: Bool = true) -> String? {
    if let key = index.modelKeysByName[name] { return key }
    guard allowSoleKeyFallback else { return nil }
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
