import Foundation
import UniformTypeIdentifiers

/// Shared by the app and its Share extension. Only completed inbox manifests
/// become visible to the app; each delivery owns a separate directory.
enum IncomingShareInbox {
  static let activationURL = URL(string: "kelivo://share")!
  static let maxFiles = 32

  enum InboxError: Error { case unavailable, invalidFile, cancelled, empty }

  static func textContents(in items: [NSExtensionItem]) -> [String] {
    // An item can carry both a caption and attachments.
    items.compactMap { $0.attributedContentText?.string }.filter { !$0.isEmpty }
  }

  static func acceptsApplicationURL(_ url: URL) -> Bool {
    guard url.isFileURL else { return false }
    let path = url.resolvingSymlinksInPath().path
    let home = URL(fileURLWithPath: NSHomeDirectory()).resolvingSymlinksInPath().path
    guard path == home || path.hasPrefix(home + "/") else { return true }
    // An external opener must not be able to name the app's private database
    // or settings. Legacy document imports copied by iOS live in Documents/Inbox.
    guard let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return false }
    let inbox = documents.appendingPathComponent("Inbox").resolvingSymlinksInPath().path
    return path.hasPrefix(inbox + "/")
  }

  /// App Groups declared by the provisioning profile embedded at signing time.
  /// `nil` means there is no readable profile (App Store and simulator builds).
  /// An extension re-signed without its own profile falls back to the host
  /// app's, which sits two levels up (`App.app/PlugIns/X.appex`).
  static func provisionedAppGroups() -> [String]? {
    let bundle = Bundle.main.bundleURL
    let profiles = [bundle, bundle.deletingLastPathComponent().deletingLastPathComponent()]
      .map { $0.appendingPathComponent("embedded.mobileprovision") }
    guard let url = profiles.first(where: { FileManager.default.fileExists(atPath: $0.path) }),
          let data = try? Data(contentsOf: url),
          let start = data.range(of: Data("<?xml".utf8)),
          let end = data.range(of: Data("</plist>".utf8)),
          start.lowerBound < end.upperBound,
          let plist = try? PropertyListSerialization.propertyList(
            from: data.subdata(in: start.lowerBound..<end.upperBound), options: [], format: nil) as? [String: Any]
    else { return nil }
    let entitlements = plist["Entitlements"] as? [String: Any]
    return entitlements?["com.apple.security.application-groups"] as? [String] ?? []
  }

  /// The configured group comes first, so correctly signed builds behave as
  /// before. A group ID belongs to the team that registered it, so a build
  /// re-signed under another team carries a different one; use that.
  static func appGroupCandidates() -> [String] {
    var groups = [String]()
    if let configured = Bundle.main.object(forInfoDictionaryKey: "KelivoShareAppGroup") as? String {
      groups.append(configured)
    }
    for group in (provisionedAppGroups() ?? []).sorted() where !groups.contains(group) {
      groups.append(group)
    }
    return groups
  }

  static func root() throws -> URL {
    var found: URL?
    for group in appGroupCandidates() {
      if let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group) {
        found = url
        break
      }
    }
    guard let container = found else { throw InboxError.unavailable }
    let root = container.appendingPathComponent("IncomingShares", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    return root
  }

  static func createDelivery() throws -> URL {
    let id = "\(Int64(Date().timeIntervalSince1970 * 1000))-\(UUID().uuidString.lowercased())"
    let directory = try root().appendingPathComponent(id, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    var excluded = directory
    var values = URLResourceValues()
    values.isExcludedFromBackup = true
    try excluded.setResourceValues(values)
    return directory
  }

  static func save(directory: URL, text: String, files: [[String: Any]], failedFiles: Int) throws {
    let payload: [String: Any] = ["id": directory.lastPathComponent, "text": text,
                                  "files": files, "failedFiles": failedFiles]
    let data = try JSONSerialization.data(withJSONObject: payload)
    try data.write(to: directory.appendingPathComponent("share.json"), options: .atomic)
  }

  static func pending() throws -> [[String: Any]] {
    let directory: URL
    do {
      directory = try root()
    } catch InboxError.unavailable {
      // Re-signed apps may lack App Group access. Passive inbox checks stay quiet.
      return []
    }
    let directories = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
    return try directories.sorted { $0.lastPathComponent < $1.lastPathComponent }.compactMap { directory in
      let manifest = directory.appendingPathComponent("share.json")
      guard FileManager.default.fileExists(atPath: manifest.path) else { return nil }
      return try JSONSerialization.jsonObject(with: Data(contentsOf: manifest)) as? [String: Any]
    }
  }

  static func acknowledge(_ ids: [String]) throws {
    let directory = try root()
    for id in ids where id.range(of: "^[0-9]+-[a-f0-9-]+$", options: .regularExpression) != nil {
      let target = directory.appendingPathComponent(id)
      if FileManager.default.fileExists(atPath: target.path) { try FileManager.default.removeItem(at: target) }
    }
  }

  static func copyFile(_ source: URL, to directory: URL, index: Int,
                       suggestedName: String? = nil, typeIdentifier: String? = nil,
                       isCancelled: () -> Bool = { false },
                       onProgress: (Int, Int?) -> Void = { _, _ in }) throws -> [String: Any] {
    guard source.isFileURL else { throw InboxError.invalidFile }
    let scoped = source.startAccessingSecurityScopedResource()
    defer { if scoped { source.stopAccessingSecurityScopedResource() } }
    var result: Result<[String: Any], Error>?
    var coordinationError: NSError?
    NSFileCoordinator().coordinate(readingItemAt: source, options: [], error: &coordinationError) { url in
      result = Result {
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        guard values.isRegularFile == true else { throw InboxError.invalidFile }
        if isCancelled() { throw InboxError.cancelled }
        var name = (suggestedName ?? source.lastPathComponent).replacingOccurrences(of: "\\", with: "/")
        name = (name as NSString).lastPathComponent.components(separatedBy: .controlCharacters).joined(separator: "_")
        if name.isEmpty || name == "." || name == ".." { name = "shared-\(index + 1)" }
        while name.utf8.count > 180 { name.removeLast() }
        let sourceType = UTType(filenameExtension: source.pathExtension)
        let type = typeIdentifier.flatMap(UTType.init) ?? sourceType
        if (name as NSString).pathExtension.isEmpty, let ext = type?.preferredFilenameExtension { name += ".\(ext)" }
        let slot = directory.appendingPathComponent(String(index), isDirectory: true)
        try FileManager.default.createDirectory(at: slot, withIntermediateDirectories: true)
        let target = slot.appendingPathComponent(name)
        do {
          let bytes = try copyBytes(from: url, to: target, isCancelled: isCancelled) { bytes in
            onProgress(bytes, values.fileSize)
          }
          let fileType = UTType(filenameExtension: (name as NSString).pathExtension) ?? type
          return ["path": target.path, "name": name,
                  "mime": fileType?.preferredMIMEType ?? "application/octet-stream", "size": bytes]
        } catch {
          try? FileManager.default.removeItem(at: target)
          throw error
        }
      }
    }
    if let error = coordinationError { throw error }
    guard let result else { throw InboxError.invalidFile }
    return try result.get()
  }

  private static func copyBytes(from source: URL, to target: URL, isCancelled: () -> Bool, onProgress: (Int) -> Void) throws -> Int {
    guard let input = InputStream(url: source), let output = OutputStream(url: target, append: false)
    else { throw InboxError.invalidFile }
    input.open()
    output.open()
    defer { input.close(); output.close() }
    var buffer = [UInt8](repeating: 0, count: 64 * 1024)
    var total = 0
    var lastProgress = Date.distantPast
    onProgress(0)
    while true {
      if isCancelled() { throw InboxError.cancelled }
      let count = input.read(&buffer, maxLength: buffer.count)
      if count < 0 { throw input.streamError ?? InboxError.invalidFile }
      if count == 0 { break }
      total += count
      try buffer.withUnsafeBufferPointer { pointer in
        var offset = 0
        while offset < count {
          let written = output.write(pointer.baseAddress!.advanced(by: offset), maxLength: count - offset)
          if written <= 0 { throw output.streamError ?? InboxError.invalidFile }
          offset += written
        }
      }
      if Date().timeIntervalSince(lastProgress) >= 0.1 {
        lastProgress = Date()
        onProgress(total)
      }
    }
    onProgress(total)
    return total
  }
}

/// Cancellation can be requested by the UI while a provider copy runs off-thread.
final class ShareCopyControl: @unchecked Sendable {
  private let lock = NSLock()
  private var cancelled = false
  var isCancelled: Bool { lock.lock(); defer { lock.unlock() }; return cancelled }
  func cancel() { lock.lock(); cancelled = true; lock.unlock() }
}
