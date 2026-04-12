import UIKit
import Flutter
import UniformTypeIdentifiers

@UIApplicationMain
@objc class AppDelegate: FlutterAppDelegate {
  private var workspaceBridge: IOSWorkspaceBridge?
  private var gitBridge: IOSGitNetworkBridge?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    if let controller = window?.rootViewController as? FlutterViewController {
      let workspaceBridge = IOSWorkspaceBridge(controller: controller)
      workspaceBridge.attach(binaryMessenger: controller.binaryMessenger)
      self.workspaceBridge = workspaceBridge

      let gitBridge = IOSGitNetworkBridge()
      gitBridge.attach(binaryMessenger: controller.binaryMessenger)
      self.gitBridge = gitBridge
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}

private final class IOSWorkspaceBridge: NSObject, UIDocumentPickerDelegate {
  private weak var controller: FlutterViewController?
  private var pendingPickerResult: FlutterResult?
  private var activeBookmarkRoots: [String: URL] = [:]
  private let bookmarkDefaultsKey = "mobile_agent.workspaceBookmarks"

  init(controller: FlutterViewController) {
    self.controller = controller
    super.init()
  }

  func attach(binaryMessenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(
      name: "mobile_agent/workspace",
      binaryMessenger: binaryMessenger
    )
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self else {
        result(FlutterError(code: "workspace_error", message: "Workspace bridge unavailable", details: nil))
        return
      }
      self.handle(call: call, result: result)
    }
  }

  private func handle(call: FlutterMethodCall, result: @escaping FlutterResult) {
    do {
      switch call.method {
      case "pickWorkspace":
        try pickWorkspace(result: result)
      case "listDirectory":
        result(try listDirectory(arguments: Self.arguments(from: call)))
      case "getEntry":
        result(try getEntry(arguments: Self.arguments(from: call)))
      case "searchEntries":
        result(try searchEntries(arguments: Self.arguments(from: call)))
      case "grepText":
        result(try grepText(arguments: Self.arguments(from: call)))
      case "readText":
        result(try readText(arguments: Self.arguments(from: call)))
      case "readBytes":
        result(FlutterStandardTypedData(bytes: try readBytes(arguments: Self.arguments(from: call))))
      case "writeText":
        try writeText(arguments: Self.arguments(from: call))
        result(nil)
      case "writeBytes":
        try writeBytes(arguments: Self.arguments(from: call))
        result(nil)
      case "deleteEntry":
        result(try deleteEntry(arguments: Self.arguments(from: call)))
      case "renameEntry":
        result(try renameEntry(arguments: Self.arguments(from: call)))
      case "moveEntry":
        result(try moveEntry(arguments: Self.arguments(from: call)))
      case "copyEntry":
        result(try copyEntry(arguments: Self.arguments(from: call)))
      case "resolveFilesystemPath":
        result(try resolveFilesystemPath(arguments: Self.arguments(from: call)))
      default:
        result(FlutterMethodNotImplemented)
      }
    } catch let error as WorkspaceBridgeError {
      result(error.flutterError)
    } catch {
      result(FlutterError(code: "workspace_error", message: error.localizedDescription, details: nil))
    }
  }

  private func pickWorkspace(result: @escaping FlutterResult) throws {
    guard pendingPickerResult == nil else {
      throw WorkspaceBridgeError(code: "busy", message: "Workspace picker already active")
    }
    guard let controller else {
      throw WorkspaceBridgeError(code: "picker_unavailable", message: "Root view controller unavailable")
    }
    pendingPickerResult = result
    let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.folder], asCopy: false)
    picker.delegate = self
    picker.allowsMultipleSelection = false
    controller.present(picker, animated: true)
  }

  func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
    finishPicker(result: nil)
  }

  func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
    guard let url = urls.first else {
      finishPicker(result: nil)
      return
    }
    do {
      let treeUri = try persistBookmark(for: url)
      finishPicker(result: [
        "treeUri": treeUri,
        "displayName": url.lastPathComponent,
      ])
    } catch let error as WorkspaceBridgeError {
      finishPicker(error: error.flutterError)
    } catch {
      finishPicker(error: FlutterError(code: "workspace_error", message: error.localizedDescription, details: nil))
    }
  }

  private func finishPicker(result: Any? = nil, error: FlutterError? = nil) {
    guard let pending = pendingPickerResult else {
      return
    }
    pendingPickerResult = nil
    if let error {
      pending(error)
    } else {
      pending(result)
    }
  }

  private func persistBookmark(for url: URL) throws -> String {
    let id = UUID().uuidString.lowercased()
      let data = try url.bookmarkData(
      options: [],
      includingResourceValuesForKeys: nil,
      relativeTo: nil
    )
    var bookmarks = loadBookmarks()
    bookmarks[id] = data
    saveBookmarks(bookmarks)
    try activateBookmark(id: id)
    return "bookmark://\(id)"
  }

  private func loadBookmarks() -> [String: Data] {
    guard let dict = UserDefaults.standard.dictionary(forKey: bookmarkDefaultsKey) as? [String: Data] else {
      return [:]
    }
    return dict
  }

  private func saveBookmarks(_ bookmarks: [String: Data]) {
    UserDefaults.standard.set(bookmarks, forKey: bookmarkDefaultsKey)
  }

  private func activateBookmark(id: String) throws {
    if activeBookmarkRoots[id] != nil {
      return
    }
    let bookmarks = loadBookmarks()
    guard let data = bookmarks[id] else {
      throw WorkspaceBridgeError(code: "not_found", message: "Workspace bookmark not found")
    }
    var stale = false
    let url = try URL(
      resolvingBookmarkData: data,
      options: [],
      relativeTo: nil,
      bookmarkDataIsStale: &stale
    )
    if !url.startAccessingSecurityScopedResource() {
      throw WorkspaceBridgeError(code: "permission_denied", message: "Could not access workspace")
    }
    if stale {
      let refreshed = try url.bookmarkData(
        options: [],
        includingResourceValuesForKeys: nil,
        relativeTo: nil
      )
      var bookmarks = loadBookmarks()
      bookmarks[id] = refreshed
      saveBookmarks(bookmarks)
    }
    activeBookmarkRoots[id] = url
  }

  private func rootURL(for treeUri: String) throws -> URL {
    if treeUri.hasPrefix("/") {
      return URL(fileURLWithPath: treeUri, isDirectory: true)
    }
    if let url = URL(string: treeUri), url.isFileURL {
      return url
    }
    guard
      let components = URLComponents(string: treeUri),
      components.scheme == "bookmark",
      let id = components.host,
      !id.isEmpty
    else {
      throw WorkspaceBridgeError(code: "unsupported_workspace", message: "Unsupported workspace: \(treeUri)")
    }
    try activateBookmark(id: id)
    guard let url = activeBookmarkRoots[id] else {
      throw WorkspaceBridgeError(code: "not_found", message: "Workspace bookmark not active")
    }
    return url
  }

  private func entryURL(treeUri: String, relativePath: String) throws -> URL {
    let root = try rootURL(for: treeUri)
    let normalized = Self.normalize(relativePath)
    if normalized.isEmpty {
      return root
    }
    let segments = normalized.split(separator: "/").map(String.init)
    if segments.contains("..") {
      throw WorkspaceBridgeError(code: "invalid_path", message: "Path escapes workspace")
    }
    return segments.reduce(root) { partial, segment in
      partial.appendingPathComponent(segment, isDirectory: false)
    }
  }

  private func listDirectory(arguments: [String: Any]) throws -> [[String: Any?]] {
    let treeUri = try Self.requiredString("treeUri", in: arguments)
    let relativePath = (arguments["relativePath"] as? String) ?? ""
    let offset = max(1, (arguments["offset"] as? Int) ?? 1)
    let limit = arguments["limit"] as? Int
    let url = try entryURL(treeUri: treeUri, relativePath: relativePath)
    var isDirectory: ObjCBool = false
    guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue else {
      throw WorkspaceBridgeError(code: "not_directory", message: "Target is not a directory")
    }
    let children = try FileManager.default.contentsOfDirectory(
      at: url,
      includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey, .fileSizeKey, .typeIdentifierKey],
      options: [.skipsHiddenFiles]
    )
    let root = try rootURL(for: treeUri)
    let sorted = try children.map { try entry(for: $0, root: root) }.sorted { lhs, rhs in
      if lhs.isDirectory != rhs.isDirectory {
        return lhs.isDirectory && !rhs.isDirectory
      }
      return lhs.path.lowercased() < rhs.path.lowercased()
    }
    let start = min(sorted.count, max(0, offset - 1))
    let end = limit == nil || limit! <= 0 ? sorted.count : min(sorted.count, start + limit!)
    return sorted[start..<end].map(\.json)
  }

  private func getEntry(arguments: [String: Any]) throws -> [String: Any?] {
    let treeUri = try Self.requiredString("treeUri", in: arguments)
    let relativePath = (arguments["relativePath"] as? String) ?? ""
    let root = try rootURL(for: treeUri)
    let url = try entryURL(treeUri: treeUri, relativePath: relativePath)
    guard FileManager.default.fileExists(atPath: url.path) else {
      throw WorkspaceBridgeError(code: "not_found", message: "Unable to resolve entry")
    }
    return try entry(for: url, root: root).json
  }

  private func searchEntries(arguments: [String: Any]) throws -> [[String: Any?]] {
    let treeUri = try Self.requiredString("treeUri", in: arguments)
    let relativePath = (arguments["relativePath"] as? String) ?? ""
    let pattern = ((arguments["pattern"] as? String) ?? "*").trimmingCharacters(in: .whitespacesAndNewlines)
    let limit = (arguments["limit"] as? Int) ?? 100
    let filesOnly = (arguments["filesOnly"] as? Bool) ?? true
    let ignorePatterns = arguments["ignorePatterns"] as? [String] ?? []
    let root = try rootURL(for: treeUri)
    let base = try entryURL(treeUri: treeUri, relativePath: relativePath)
    var isDirectory: ObjCBool = false
    guard FileManager.default.fileExists(atPath: base.path, isDirectory: &isDirectory), isDirectory.boolValue else {
      throw WorkspaceBridgeError(code: "not_directory", message: "Target is not a directory")
    }
    let regex = try globRegex(pattern)
    let basePath = Self.normalize(relativePath)
    let enumerator = FileManager.default.enumerator(
      at: base,
      includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey, .fileSizeKey, .typeIdentifierKey],
      options: [.skipsHiddenFiles]
    )
    var results: [WorkspaceEntryPayload] = []
    while let next = enumerator?.nextObject() as? URL {
      let entry = try entry(for: next, root: root)
      if shouldIgnore(path: entry.path, isDirectory: entry.isDirectory, ignorePatterns: ignorePatterns) {
        if entry.isDirectory {
          enumerator?.skipDescendants()
        }
        continue
      }
      let relativeToRoot: String
      if basePath.isEmpty {
        relativeToRoot = entry.path
      } else if entry.path.hasPrefix(basePath + "/") {
        relativeToRoot = String(entry.path.dropFirst(basePath.count + 1))
      } else {
        relativeToRoot = entry.name
      }
      if (!filesOnly || !entry.isDirectory) && regex.firstMatch(in: relativeToRoot, options: [], range: NSRange(location: 0, length: relativeToRoot.utf16.count)) != nil {
        results.append(entry)
        if results.count >= limit {
          break
        }
      }
    }
    results.sort { ($0.lastModified ?? 0) > ($1.lastModified ?? 0) }
    return results.map(\.json)
  }

  private func grepText(arguments: [String: Any]) throws -> [[String: Any]] {
    let treeUri = try Self.requiredString("treeUri", in: arguments)
    let relativePath = (arguments["relativePath"] as? String) ?? ""
    let pattern = try Self.requiredString("pattern", in: arguments)
    let include = (arguments["include"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
    let limit = (arguments["limit"] as? Int) ?? 100
    let maxLineLength = (arguments["maxLineLength"] as? Int) ?? 2000
    let ignorePatterns = arguments["ignorePatterns"] as? [String] ?? []
    let root = try rootURL(for: treeUri)
    let base = try entryURL(treeUri: treeUri, relativePath: relativePath)
    var isDirectory: ObjCBool = false
    guard FileManager.default.fileExists(atPath: base.path, isDirectory: &isDirectory), isDirectory.boolValue else {
      throw WorkspaceBridgeError(code: "not_directory", message: "Target is not a directory")
    }
    let regex = try NSRegularExpression(pattern: pattern)
    let includeRegex = include?.isEmpty == false ? try globRegex(include!) : nil
    let enumerator = FileManager.default.enumerator(
      at: base,
      includingPropertiesForKeys: [.isDirectoryKey, .typeIdentifierKey],
      options: [.skipsHiddenFiles]
    )
    var output: [[String: Any]] = []
    while let next = enumerator?.nextObject() as? URL {
      let entry = try entry(for: next, root: root)
      if shouldIgnore(path: entry.path, isDirectory: entry.isDirectory, ignorePatterns: ignorePatterns) {
        if entry.isDirectory {
          enumerator?.skipDescendants()
        }
        continue
      }
      if entry.isDirectory {
        continue
      }
      if let includeRegex {
        let range = NSRange(location: 0, length: entry.path.utf16.count)
        if includeRegex.firstMatch(in: entry.path, options: [], range: range) == nil {
          continue
        }
      }
      if looksBinary(url: next) {
        continue
      }
      let text = try String(contentsOf: next, encoding: .utf8)
      let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
      for (index, line) in lines.enumerated() {
        let value = String(line)
        let range = NSRange(location: 0, length: value.utf16.count)
        if regex.firstMatch(in: value, options: [], range: range) == nil {
          continue
        }
        output.append([
          "path": entry.path,
          "line": index + 1,
          "text": value.count > maxLineLength ? String(value.prefix(maxLineLength)) + "..." : value,
        ])
        if output.count >= limit {
          return output
        }
      }
    }
    return output
  }

  private func readText(arguments: [String: Any]) throws -> String {
    let treeUri = try Self.requiredString("treeUri", in: arguments)
    let relativePath = try Self.requiredString("relativePath", in: arguments)
    let url = try entryURL(treeUri: treeUri, relativePath: relativePath)
    var isDirectory: ObjCBool = false
    guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), !isDirectory.boolValue else {
      throw WorkspaceBridgeError(code: "not_file", message: "Target is not a file")
    }
    return try String(contentsOf: url, encoding: .utf8)
  }

  private func readBytes(arguments: [String: Any]) throws -> Data {
    let treeUri = try Self.requiredString("treeUri", in: arguments)
    let relativePath = try Self.requiredString("relativePath", in: arguments)
    let url = try entryURL(treeUri: treeUri, relativePath: relativePath)
    var isDirectory: ObjCBool = false
    guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), !isDirectory.boolValue else {
      throw WorkspaceBridgeError(code: "not_file", message: "Target is not a file")
    }
    return try Data(contentsOf: url)
  }

  private func writeText(arguments: [String: Any]) throws {
    let treeUri = try Self.requiredString("treeUri", in: arguments)
    let relativePath = try Self.requiredString("relativePath", in: arguments)
    let content = (arguments["content"] as? String) ?? ""
    let url = try entryURL(treeUri: treeUri, relativePath: relativePath)
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try content.write(to: url, atomically: true, encoding: .utf8)
  }

  private func writeBytes(arguments: [String: Any]) throws {
    let treeUri = try Self.requiredString("treeUri", in: arguments)
    let relativePath = try Self.requiredString("relativePath", in: arguments)
    let bytes = (arguments["bytes"] as? FlutterStandardTypedData)?.data ?? Data()
    let url = try entryURL(treeUri: treeUri, relativePath: relativePath)
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try bytes.write(to: url, options: .atomic)
  }

  private func deleteEntry(arguments: [String: Any]) throws -> Bool {
    let treeUri = try Self.requiredString("treeUri", in: arguments)
    let relativePath = try Self.requiredString("relativePath", in: arguments)
    let url = try entryURL(treeUri: treeUri, relativePath: relativePath)
    guard FileManager.default.fileExists(atPath: url.path) else {
      throw WorkspaceBridgeError(code: "missing_entry", message: "Unable to resolve entry")
    }
    try FileManager.default.removeItem(at: url)
    return true
  }

  private func renameEntry(arguments: [String: Any]) throws -> [String: Any?] {
    let treeUri = try Self.requiredString("treeUri", in: arguments)
    let relativePath = try Self.requiredString("relativePath", in: arguments)
    let newName = try Self.requiredSegment("newName", in: arguments)
    let root = try rootURL(for: treeUri)
    let source = try entryURL(treeUri: treeUri, relativePath: relativePath)
    guard FileManager.default.fileExists(atPath: source.path) else {
      throw WorkspaceBridgeError(code: "not_found", message: "Unable to resolve entry")
    }
    let destination = source.deletingLastPathComponent().appendingPathComponent(newName)
    if FileManager.default.fileExists(atPath: destination.path) {
      throw WorkspaceBridgeError(code: "exists", message: "Destination already exists")
    }
    try FileManager.default.moveItem(at: source, to: destination)
    return try entry(for: destination, root: root).json
  }

  private func moveEntry(arguments: [String: Any]) throws -> [String: Any?] {
    let treeUri = try Self.requiredString("treeUri", in: arguments)
    let fromPath = try Self.requiredString("fromPath", in: arguments)
    let toPath = try Self.requiredString("toPath", in: arguments)
    let normalizedFrom = Self.normalize(fromPath)
    let normalizedTo = Self.normalize(toPath)
    guard !normalizedFrom.isEmpty, !normalizedTo.isEmpty else {
      throw WorkspaceBridgeError(code: "invalid_path", message: "Paths must not be empty")
    }
    if normalizedTo.hasPrefix(normalizedFrom + "/") {
      throw WorkspaceBridgeError(code: "invalid_move", message: "Cannot move a path into itself")
    }
    let root = try rootURL(for: treeUri)
    let source = try entryURL(treeUri: treeUri, relativePath: normalizedFrom)
    let destination = try entryURL(treeUri: treeUri, relativePath: normalizedTo)
    guard FileManager.default.fileExists(atPath: source.path) else {
      throw WorkspaceBridgeError(code: "not_found", message: "Source not found")
    }
    if FileManager.default.fileExists(atPath: destination.path) {
      throw WorkspaceBridgeError(code: "exists", message: "Destination already exists")
    }
    try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
    try FileManager.default.moveItem(at: source, to: destination)
    return try entry(for: destination, root: root).json
  }

  private func copyEntry(arguments: [String: Any]) throws -> [String: Any?] {
    let treeUri = try Self.requiredString("treeUri", in: arguments)
    let fromPath = try Self.requiredString("fromPath", in: arguments)
    let toPath = try Self.requiredString("toPath", in: arguments)
    let normalizedFrom = Self.normalize(fromPath)
    let normalizedTo = Self.normalize(toPath)
    guard !normalizedFrom.isEmpty, !normalizedTo.isEmpty else {
      throw WorkspaceBridgeError(code: "invalid_path", message: "Paths must not be empty")
    }
    if normalizedTo.hasPrefix(normalizedFrom + "/") {
      throw WorkspaceBridgeError(code: "invalid_copy", message: "Cannot copy a path into itself")
    }
    let root = try rootURL(for: treeUri)
    let source = try entryURL(treeUri: treeUri, relativePath: normalizedFrom)
    let destination = try entryURL(treeUri: treeUri, relativePath: normalizedTo)
    guard FileManager.default.fileExists(atPath: source.path) else {
      throw WorkspaceBridgeError(code: "not_found", message: "Source not found")
    }
    if FileManager.default.fileExists(atPath: destination.path) {
      throw WorkspaceBridgeError(code: "exists", message: "Destination already exists")
    }
    try copyRecursively(from: source, to: destination, depth: 0, fileCount: 0)
    return try entry(for: destination, root: root).json
  }

  private func resolveFilesystemPath(arguments: [String: Any]) throws -> String? {
    let treeUri = try Self.requiredString("treeUri", in: arguments)
    return try rootURL(for: treeUri).path
  }

  private func entry(for url: URL, root: URL) throws -> WorkspaceEntryPayload {
    let values = try url.resourceValues(forKeys: [
      .isDirectoryKey,
      .contentModificationDateKey,
      .fileSizeKey,
      .typeIdentifierKey,
    ])
    let relative = url.path == root.path
      ? ""
      : url.path.replacingOccurrences(of: root.path + "/", with: "")
    return WorkspaceEntryPayload(
      path: relative,
      name: url.lastPathComponent,
      isDirectory: values.isDirectory ?? false,
      lastModified: Int(values.contentModificationDate?.timeIntervalSince1970 ?? 0) * 1000,
      size: values.isDirectory == true ? 0 : (values.fileSize ?? 0),
      mimeType: mimeType(for: url, typeIdentifier: values.typeIdentifier, isDirectory: values.isDirectory ?? false)
    )
  }

  private func mimeType(for url: URL, typeIdentifier: String?, isDirectory: Bool) -> String? {
    if isDirectory {
      return nil
    }
    if let typeIdentifier, let type = UTType(typeIdentifier) {
      return type.preferredMIMEType ?? "text/plain"
    }
    return UTType(filenameExtension: url.pathExtension)?.preferredMIMEType ?? "text/plain"
  }

  private func copyRecursively(from source: URL, to destination: URL, depth: Int, fileCount: Int) throws {
    if depth > 32 {
      throw WorkspaceBridgeError(code: "copy_too_deep", message: "Maximum directory depth exceeded")
    }
    var isDirectory: ObjCBool = false
    guard FileManager.default.fileExists(atPath: source.path, isDirectory: &isDirectory) else {
      throw WorkspaceBridgeError(code: "not_found", message: "Source not found")
    }
    if isDirectory.boolValue {
      try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
      let children = try FileManager.default.contentsOfDirectory(at: source, includingPropertiesForKeys: nil)
      var nextCount = fileCount
      for child in children {
        if !child.hasDirectoryPath {
          nextCount += 1
          if nextCount > 5000 {
            throw WorkspaceBridgeError(code: "copy_too_large", message: "Too many files to copy")
          }
        }
        try copyRecursively(
          from: child,
          to: destination.appendingPathComponent(child.lastPathComponent),
          depth: depth + 1,
          fileCount: nextCount
        )
      }
    } else {
      try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
      try FileManager.default.copyItem(at: source, to: destination)
    }
  }

  private func looksBinary(url: URL) -> Bool {
    let lower = url.path.lowercased()
    let textExtensions = [
      ".dart", ".kt", ".java", ".md", ".txt", ".yaml", ".yml", ".json",
      ".xml", ".gradle", ".properties", ".js", ".ts", ".tsx", ".jsx",
      ".html", ".css", ".scss", ".sh",
    ]
    return !textExtensions.contains(where: { lower.hasSuffix($0) })
  }

  private func shouldIgnore(path: String, isDirectory: Bool, ignorePatterns: [String]) -> Bool {
    let normalized = Self.normalize(path)
    for pattern in ignorePatterns {
      let candidate = pattern.trimmingCharacters(in: .whitespacesAndNewlines)
      if candidate.isEmpty {
        continue
      }
      guard let regex = try? globRegex(candidate) else {
        continue
      }
      let slashPath = normalized + "/"
      let range = NSRange(location: 0, length: normalized.utf16.count)
      if regex.firstMatch(in: normalized, options: [], range: range) != nil {
        return true
      }
      let slashRange = NSRange(location: 0, length: slashPath.utf16.count)
      if regex.firstMatch(in: slashPath, options: [], range: slashRange) != nil {
        return true
      }
      if candidate.hasSuffix("/") {
        let prefix = Self.normalize(String(candidate.dropLast()))
        if normalized == prefix || normalized.hasPrefix(prefix + "/") {
          return true
        }
      }
      if isDirectory && regex.firstMatch(in: slashPath, options: [], range: slashRange) != nil {
        return true
      }
    }
    return false
  }

  private func globRegex(_ pattern: String) throws -> NSRegularExpression {
    let normalized = pattern.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "*" : pattern.trimmingCharacters(in: .whitespacesAndNewlines)
    var output = "^"
    var index = normalized.startIndex
    while index < normalized.endIndex {
      let char = normalized[index]
      if char == "*" {
        let nextIndex = normalized.index(after: index)
        if nextIndex < normalized.endIndex && normalized[nextIndex] == "*" {
          output += ".*"
          index = normalized.index(after: nextIndex)
        } else {
          output += "[^/]*"
          index = nextIndex
        }
        continue
      }
      if char == "?" {
        output += "."
        index = normalized.index(after: index)
        continue
      }
      if char == "{" {
        if let end = normalized[index...].firstIndex(of: "}") {
          let body = normalized[normalized.index(after: index)..<end]
          let parts = body.split(separator: ",").map { NSRegularExpression.escapedPattern(for: String($0)) }
          output += "(\(parts.joined(separator: "|")))"
          index = normalized.index(after: end)
          continue
        }
      }
      output += NSRegularExpression.escapedPattern(for: String(char))
      index = normalized.index(after: index)
    }
    output += "$"
    return try NSRegularExpression(pattern: output)
  }

  private static func arguments(from call: FlutterMethodCall) -> [String: Any] {
    call.arguments as? [String: Any] ?? [:]
  }

  private static func requiredString(_ key: String, in arguments: [String: Any]) throws -> String {
    let value = (arguments[key] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    if value.isEmpty {
      throw WorkspaceBridgeError(code: "missing_argument", message: "Missing required parameter: \(key)")
    }
    return value
  }

  private static func requiredSegment(_ key: String, in arguments: [String: Any]) throws -> String {
    let value = try requiredString(key, in: arguments)
    if value.contains("/") || value.contains("\\") {
      throw WorkspaceBridgeError(code: "invalid_name", message: "\(key) must be a single path segment")
    }
    return value
  }

  private static func normalize(_ path: String) -> String {
    path.trimmingCharacters(in: .whitespacesAndNewlines)
      .replacingOccurrences(of: "\\", with: "/")
      .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
  }
}

private struct WorkspaceEntryPayload {
  let path: String
  let name: String
  let isDirectory: Bool
  let lastModified: Int?
  let size: Int?
  let mimeType: String?

  var json: [String: Any?] {
    [
      "path": path,
      "name": name,
      "isDirectory": isDirectory,
      "lastModified": lastModified ?? 0,
      "size": size ?? 0,
      "mimeType": mimeType,
    ]
  }
}

private struct WorkspaceBridgeError: Error {
  let code: String
  let message: String

  var flutterError: FlutterError {
    FlutterError(code: code, message: message, details: nil)
  }
}

private final class IOSGitNetworkBridge {
  private let queue = DispatchQueue(label: "mobile_agent.git_network")

  init() {
    git_libgit2_init()
  }

  deinit {
    git_libgit2_shutdown()
  }

  func attach(binaryMessenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(
      name: "mobile_agent/git_network",
      binaryMessenger: binaryMessenger
    )
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self else {
        result(FlutterError(code: "git_network_error", message: "Git bridge unavailable", details: nil))
        return
      }
      self.handle(call: call, result: result)
    }
  }

  private func handle(call: FlutterMethodCall, result: @escaping FlutterResult) {
    let arguments = call.arguments as? [String: Any] ?? [:]
    queue.async {
      do {
        let value: [String: Any?]
        switch call.method {
        case "discoverRepository":
          value = try self.discoverRepository(arguments: arguments)
        case "initRepository":
          value = try self.initRepository(arguments: arguments)
        case "cloneRepository":
          value = try self.cloneRepository(arguments: arguments)
        case "statusRepository":
          value = try self.statusRepository(arguments: arguments)
        case "addRepositoryPaths":
          value = try self.addRepositoryPaths(arguments: arguments)
        case "addAllRepositoryPaths":
          value = try self.addAllRepositoryPaths(arguments: arguments)
        case "unstageRepositoryPath":
          value = try self.unstageRepositoryPath(arguments: arguments)
        case "commitRepository":
          value = try self.commitRepository(arguments: arguments, amend: false)
        case "amendCommitRepository":
          value = try self.commitRepository(arguments: arguments, amend: true)
        case "logRepository":
          value = try self.logRepository(arguments: arguments)
        case "showRepositoryCommit":
          value = try self.showRepositoryCommit(arguments: arguments)
        case "diffRepository":
          value = try self.diffRepository(arguments: arguments)
        case "currentRepositoryBranch":
          value = try self.currentRepositoryBranch(arguments: arguments)
        case "listRepositoryBranches":
          value = try self.listRepositoryBranches(arguments: arguments)
        case "createRepositoryBranch":
          value = try self.createRepositoryBranch(arguments: arguments)
        case "deleteRepositoryBranch":
          value = try self.deleteRepositoryBranch(arguments: arguments)
        case "checkoutRepositoryTarget":
          value = try self.checkoutRepositoryTarget(arguments: arguments)
        case "checkoutRepositoryNewBranch":
          value = try self.checkoutRepositoryNewBranch(arguments: arguments)
        case "restoreRepositoryFile":
          value = try self.restoreRepositoryFile(arguments: arguments)
        case "resetRepository":
          value = try self.resetRepository(arguments: arguments)
        case "mergeRepositoryBranch":
          value = try self.mergeRepositoryBranch(arguments: arguments)
        case "fetchRepository":
          value = try self.fetchRepository(arguments: arguments)
        case "pullRepository":
          value = try self.pullRepository(arguments: arguments)
        case "pushRepository":
          value = try self.pushRepository(arguments: arguments)
        case "rebaseRepositoryTarget":
          value = try self.rebaseRepositoryTarget(arguments: arguments)
        case "cherryPickRepositoryCommit":
          value = try self.cherryPickRepositoryCommit(arguments: arguments)
        case "getRepositoryConfigValue":
          value = try self.getRepositoryConfigValue(arguments: arguments)
        case "setRepositoryConfigValue":
          value = try self.setRepositoryConfigValue(arguments: arguments)
        case "getRepositoryRemoteUrl":
          value = try self.getRepositoryRemoteUrl(arguments: arguments)
        case "listRepositoryRemotes":
          value = try self.listRepositoryRemotes(arguments: arguments)
        case "addRepositoryRemote":
          value = try self.addRepositoryRemote(arguments: arguments)
        case "setRepositoryRemoteUrl":
          value = try self.setRepositoryRemoteUrl(arguments: arguments)
        case "removeRepositoryRemote":
          value = try self.removeRepositoryRemote(arguments: arguments)
        case "renameRepositoryRemote":
          value = try self.renameRepositoryRemote(arguments: arguments)
        default:
          DispatchQueue.main.async { result(FlutterMethodNotImplemented) }
          return
        }
        DispatchQueue.main.async { result(value) }
      } catch let error as GitBridgeError {
        DispatchQueue.main.async {
          result(FlutterError(code: "git_network_error", message: error.message, details: nil))
        }
      } catch {
        DispatchQueue.main.async {
          result(FlutterError(code: "git_network_error", message: error.localizedDescription, details: nil))
        }
      }
    }
  }

  private func discoverRepository(arguments: [String: Any]) throws -> [String: Any?] {
    let path = try requiredString("path", in: arguments)
    let fileManager = FileManager.default
    var currentURL = URL(fileURLWithPath: path, isDirectory: true)
    var isDirectory: ObjCBool = false
    if !fileManager.fileExists(atPath: currentURL.path, isDirectory: &isDirectory) {
      currentURL = currentURL.deletingLastPathComponent()
    } else if !isDirectory.boolValue {
      currentURL = currentURL.deletingLastPathComponent()
    }
    while true {
      let gitURL = currentURL.appendingPathComponent(".git", isDirectory: true)
      if fileManager.fileExists(atPath: gitURL.path) {
        return [
          "success": true,
          "workDir": currentURL.path,
        ]
      }
      let parent = currentURL.deletingLastPathComponent()
      if parent.path == currentURL.path {
        break
      }
      currentURL = parent
    }
    return [
      "success": false,
      "error": "Not a git repository",
    ]
  }

  private func initRepository(arguments: [String: Any]) throws -> [String: Any?] {
    let path = try requiredString("path", in: arguments)
    var repository: OpaquePointer?
    defer {
      if let repository {
        git_repository_free(repository)
      }
    }
    try withGitCString(path) { pathCString in
      try check(git_repository_init(&repository, pathCString, 0), "Init failed")
    }
    return [
      "success": true,
      "workDir": path,
    ]
  }

  private func cloneRepository(arguments: [String: Any]) throws -> [String: Any?] {
    let url = try requiredString("url", in: arguments)
    let path = try requiredString("path", in: arguments)
    let remoteName = ((arguments["remoteName"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.isEmpty ? nil : $0 } ?? "origin"
    let branch = ((arguments["branch"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.isEmpty ? nil : $0 }
    let auth = GitAuthInfo(map: arguments["auth"] as? [String: Any])
    if directoryExistsAndNotEmpty(path) {
      throw GitBridgeError("Target directory already exists and is not empty: \(path)")
    }

    var repository: OpaquePointer?
    let context = GitOperationContext(auth: auth, remoteName: remoteName)
    let payload = Unmanaged.passRetained(context)
    defer {
      payload.release()
      if let repository {
        git_repository_free(repository)
      }
    }

    var options = git_clone_options()
    try check(git_clone_init_options(&options, UInt32(GIT_CLONE_OPTIONS_VERSION)), "Failed to initialize clone options")
    options.fetch_opts.callbacks.credentials = gitCredentialAcquireCallback
    options.fetch_opts.callbacks.certificate_check = gitCertificateCheckCallback
    options.fetch_opts.callbacks.payload = payload.toOpaque()
    options.remote_cb = gitRemoteCreateCallback
    options.remote_cb_payload = payload.toOpaque()
    options.checkout_opts.checkout_strategy = UInt32(GIT_CHECKOUT_SAFE.rawValue)

    let normalized = normalizeRemoteURL(url: url, auth: auth)
    let cloneResult = try withGitCString(normalized) { urlCString in
      try withGitCString(path) { pathCString in
        if let branch {
          return try withGitCString(branch) { branchCString in
            options.checkout_branch = branchCString
            return git_clone(&repository, urlCString, pathCString, &options)
          }
        }
        return git_clone(&repository, urlCString, pathCString, &options)
      }
    }
    try check(cloneResult, "Clone failed")

    let defaultBranch = try currentBranchName(repository: repository)
    return [
      "success": true,
      "defaultBranch": defaultBranch,
      "objectsReceived": 0,
    ]
  }

  private func statusRepository(arguments: [String: Any]) throws -> [String: Any?] {
    let workDir = try requiredString("workDir", in: arguments)
    return try withRepository(path: workDir) { repository in
      var statusOptions = git_status_options()
      try check(
        git_status_init_options(&statusOptions, UInt32(GIT_STATUS_OPTIONS_VERSION)),
        "Failed to initialize status options"
      )
      statusOptions.show = GIT_STATUS_SHOW_INDEX_AND_WORKDIR
      statusOptions.flags = UInt32(
        GIT_STATUS_OPT_INCLUDE_UNTRACKED.rawValue |
        GIT_STATUS_OPT_RECURSE_UNTRACKED_DIRS.rawValue |
        GIT_STATUS_OPT_RENAMES_HEAD_TO_INDEX.rawValue
      )
      var statusList: OpaquePointer?
      defer {
        if let statusList {
          git_status_list_free(statusList)
        }
      }
      try check(git_status_list_new(&statusList, repository, &statusOptions), "Status failed")
      let count = git_status_list_entrycount(statusList)
      var staged: [[String: Any?]] = []
      var unstaged: [[String: Any?]] = []
      var untracked: [[String: Any?]] = []
      for index in 0..<count {
        guard let entry = git_status_byindex(statusList, index)?.pointee else {
          continue
        }
        let path = statusEntryPath(entry)
        if path.isEmpty {
          continue
        }
        let flags = entry.status.rawValue
        if (flags & GIT_STATUS_WT_NEW.rawValue) != 0 {
          untracked.append(["path": path, "status": "untracked"])
        }
        if (flags & GIT_STATUS_CONFLICTED.rawValue) != 0 {
          unstaged.append(["path": path, "status": "unmerged"])
          continue
        }
        if (flags & GIT_STATUS_INDEX_NEW.rawValue) != 0 {
          staged.append(["path": path, "status": "added"])
        }
        if (flags & GIT_STATUS_INDEX_MODIFIED.rawValue) != 0 {
          staged.append(["path": path, "status": "modified"])
        }
        if (flags & GIT_STATUS_INDEX_DELETED.rawValue) != 0 {
          staged.append(["path": path, "status": "deleted"])
        }
        if (flags & GIT_STATUS_INDEX_RENAMED.rawValue) != 0 {
          staged.append(["path": path, "status": "renamed"])
        }
        if (flags & GIT_STATUS_WT_MODIFIED.rawValue) != 0 {
          unstaged.append(["path": path, "status": "modified"])
        }
        if (flags & GIT_STATUS_WT_DELETED.rawValue) != 0 {
          unstaged.append(["path": path, "status": "deleted"])
        }
        if (flags & GIT_STATUS_WT_RENAMED.rawValue) != 0 {
          unstaged.append(["path": path, "status": "renamed"])
        }
      }
      return [
        "success": true,
        "branch": try currentBranchName(repository: repository),
        "head": try headOidString(repository: repository),
        "clean": staged.isEmpty && unstaged.isEmpty && untracked.isEmpty,
        "staged": staged,
        "unstaged": unstaged,
        "untracked": untracked,
      ]
    }
  }

  private func addRepositoryPaths(arguments: [String: Any]) throws -> [String: Any?] {
    let workDir = try requiredString("workDir", in: arguments)
    let paths = (arguments["paths"] as? [String] ?? []).map {
      $0.trimmingCharacters(in: .whitespacesAndNewlines)
    }.filter { !$0.isEmpty }
    guard !paths.isEmpty else {
      throw GitBridgeError("Missing required parameter: paths")
    }
    return try withRepository(path: workDir) { repository in
      var index: OpaquePointer?
      defer {
        if let index {
          git_index_free(index)
        }
      }
      try check(git_repository_index(&index, repository), "Failed to open index")
      for path in paths {
        try withGitCString(path) { pathCString in
          try check(git_index_add_bypath(index, pathCString), "Add failed")
        }
      }
      try check(git_index_write(index), "Failed to write index")
      return ["success": true]
    }
  }

  private func addAllRepositoryPaths(arguments: [String: Any]) throws -> [String: Any?] {
    let workDir = try requiredString("workDir", in: arguments)
    return try withRepository(path: workDir) { repository in
      var index: OpaquePointer?
      defer {
        if let index {
          git_index_free(index)
        }
      }
      try check(git_repository_index(&index, repository), "Failed to open index")
      try withGitPathspec("*") { pathspec in
        try check(
          git_index_add_all(index, pathspec, UInt32(GIT_INDEX_ADD_DEFAULT.rawValue), nil, nil),
          "Add failed"
        )
      }
      try check(git_index_write(index), "Failed to write index")
      return ["success": true]
    }
  }

  private func unstageRepositoryPath(arguments: [String: Any]) throws -> [String: Any?] {
    let workDir = try requiredString("workDir", in: arguments)
    let path = try requiredString("path", in: arguments)
    return try withRepository(path: workDir) { repository in
      try withGitPathspec(path) { pathspec in
        try check(git_reset_default(repository, nil, pathspec), "Unstage failed")
      }
      return ["success": true]
    }
  }

  private func commitRepository(arguments: [String: Any], amend: Bool) throws -> [String: Any?] {
    let workDir = try requiredString("workDir", in: arguments)
    let message = try requiredString("message", in: arguments)
    let authorName = ((arguments["authorName"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.isEmpty ? nil : $0 }
    let authorEmail = ((arguments["authorEmail"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.isEmpty ? nil : $0 }

    var repository: OpaquePointer?
    defer {
      if let repository {
        git_repository_free(repository)
      }
    }
    try withGitCString(workDir) { workDirCString in
      try check(git_repository_open(&repository, workDirCString), "Failed to open repository")
    }

    var signature: UnsafeMutablePointer<git_signature>?
    defer {
      if let signature {
        git_signature_free(signature)
      }
    }
    try signatureNow(repository: repository, name: authorName, email: authorEmail, output: &signature)

    var oid = git_oid()
    if amend {
      var headRef: OpaquePointer?
      var headCommit: OpaquePointer?
      var index: OpaquePointer?
      var treeOid = git_oid()
      var tree: OpaquePointer?
      defer {
        if let headRef { git_reference_free(headRef) }
        if let headCommit { git_commit_free(headCommit) }
        if let index { git_index_free(index) }
        if let tree { git_tree_free(tree) }
      }
      try check(git_repository_head(&headRef, repository), "Reference not found: HEAD")
      var commitOid = git_reference_target(headRef).pointee
      try check(git_commit_lookup(&headCommit, repository, &commitOid), "Object not found: \(oidDescription(commitOid))")
      try check(git_repository_index(&index, repository), "Failed to open index")
      try check(git_index_write_tree(&treeOid, index), "Failed to write tree")
      try check(git_index_write(index), "Failed to write index")
      try check(git_tree_lookup(&tree, repository, &treeOid), "Failed to read tree")
      let amendResult = try withGitCString("HEAD") { updateRef in
        try withGitCString(message) { messageCString in
          git_commit_amend(&oid, headCommit, updateRef, signature, signature, nil, messageCString, tree)
        }
      }
      try check(amendResult, "Commit amend failed")
    } else {
      oid = try createCommitFromIndex(
        repository: repository,
        message: message,
        signature: signature,
        extraParents: []
      )
    }

    return try commitResult(repository: repository, oid: oid)
  }

  private func logRepository(arguments: [String: Any]) throws -> [String: Any?] {
    let workDir = try requiredString("workDir", in: arguments)
    let maxCount = max(1, arguments["maxCount"] as? Int ?? 20)
    let firstParentOnly = (arguments["firstParentOnly"] as? Bool) == true
    let since = parseDateFilter(arguments["since"] as? String)
    let until = parseDateFilter(arguments["until"] as? String)
    let commits = try withRepository(path: workDir) { repository -> [[String: Any?]] in
      guard let headOid = try resolveObjectId(repository: repository, spec: "HEAD") else {
        return []
      }
      var walker: OpaquePointer?
      defer {
        if let walker {
          git_revwalk_free(walker)
        }
      }
      try check(git_revwalk_new(&walker, repository), "Failed to initialize log walk")
      git_revwalk_sorting(walker, UInt32(GIT_SORT_TIME.rawValue))
      var oid = headOid
      try check(git_revwalk_push(walker, &oid), "Failed to walk history")
      var output: [[String: Any?]] = []
      while output.count < maxCount {
        var next = git_oid()
        let code = git_revwalk_next(&next, walker)
        if code == GIT_ITEROVER.rawValue {
          break
        }
        try check(code, "Failed to read commit history")
        let commit = try commitPayload(repository: repository, oid: next)
        let timestamp = (commit["authorTimestampMs"] as? Int) ?? 0
        if let since, timestamp < since {
          continue
        }
        if let until, timestamp > until {
          continue
        }
        output.append(commit)
        if firstParentOnly {
          let parents = commit["parents"] as? [String] ?? []
          if let first = parents.first, let parentOid = oidFromString(first) {
            git_revwalk_reset(walker)
            var mutableParentOid = parentOid
            try check(git_revwalk_push(walker, &mutableParentOid), "Failed to continue first-parent history")
          } else {
            break
          }
        }
      }
      return output
    }
    return [
      "success": true,
      "commits": commits,
    ]
  }

  private func showRepositoryCommit(arguments: [String: Any]) throws -> [String: Any?] {
    let workDir = try requiredString("workDir", in: arguments)
    let ref = try requiredString("ref", in: arguments)
    let commit = try withRepository(path: workDir) { repository -> [String: Any?] in
      guard let oid = try resolveObjectId(repository: repository, spec: ref) else {
        throw GitBridgeError("Unknown ref: \(ref)")
      }
      return try commitPayload(repository: repository, oid: oid)
    }
    return [
      "success": true,
      "commit": commit,
    ]
  }

  private func diffRepository(arguments: [String: Any]) throws -> [String: Any?] {
    let filter = Set((arguments["paths"] as? [String] ?? []).map {
      $0.trimmingCharacters(in: .whitespacesAndNewlines)
    }.filter { !$0.isEmpty })
    let status = try statusRepository(arguments: arguments)
    let groups: [(String, [[String: Any?]])] = [
      ("Staged changes", status["staged"] as? [[String: Any?]] ?? []),
      ("Unstaged changes", status["unstaged"] as? [[String: Any?]] ?? []),
      ("Untracked files", status["untracked"] as? [[String: Any?]] ?? []),
    ]
    var sections: [String] = []
    for (title, entries) in groups {
      let visible = entries.filter { entry in
        guard !filter.isEmpty else { return true }
        return filter.contains(entry["path"] as? String ?? "")
      }
      guard !visible.isEmpty else {
        continue
      }
      let body = visible.map { entry in
        let statusName = entry["status"] as? String ?? "modified"
        let path = entry["path"] as? String ?? ""
        return "--- \(statusName): \(path)"
      }.joined(separator: "\n")
      sections.append("\(title):\n\(body)")
    }
    return [
      "success": true,
      "diff": sections.isEmpty ? "No changes." : sections.joined(separator: "\n\n"),
    ]
  }

  private func currentRepositoryBranch(arguments: [String: Any]) throws -> [String: Any?] {
    let workDir = try requiredString("workDir", in: arguments)
    return try withRepository(path: workDir) { repository in
      [
        "success": true,
        "branch": try currentBranchName(repository: repository),
        "head": try headOidString(repository: repository),
      ]
    }
  }

  private func listRepositoryBranches(arguments: [String: Any]) throws -> [String: Any?] {
    let workDir = try requiredString("workDir", in: arguments)
    return try withRepository(path: workDir) { repository in
      [
        "success": true,
        "branches": try listBranches(repository: repository),
        "current": try currentBranchName(repository: repository),
      ]
    }
  }

  private func createRepositoryBranch(arguments: [String: Any]) throws -> [String: Any?] {
    let workDir = try requiredString("workDir", in: arguments)
    let name = try requiredString("name", in: arguments)
    let startPoint = ((arguments["startPoint"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.isEmpty ? nil : $0 }
    return try withRepository(path: workDir) { repository in
      try createBranch(repository: repository, name: name, startPoint: startPoint)
      return ["success": true]
    }
  }

  private func deleteRepositoryBranch(arguments: [String: Any]) throws -> [String: Any?] {
    let workDir = try requiredString("workDir", in: arguments)
    let name = try requiredString("name", in: arguments)
    let force = (arguments["force"] as? Bool) == true
    return try withRepository(path: workDir) { repository in
      try deleteBranch(repository: repository, name: name, force: force)
      return ["success": true]
    }
  }

  private func checkoutRepositoryTarget(arguments: [String: Any]) throws -> [String: Any?] {
    let workDir = try requiredString("workDir", in: arguments)
    let target = try requiredString("target", in: arguments)
    return try withRepository(path: workDir) { repository in
      try checkoutTarget(repository: repository, target: target)
      return ["success": true]
    }
  }

  private func checkoutRepositoryNewBranch(arguments: [String: Any]) throws -> [String: Any?] {
    let workDir = try requiredString("workDir", in: arguments)
    let name = try requiredString("name", in: arguments)
    return try withRepository(path: workDir) { repository in
      try createBranch(repository: repository, name: name, startPoint: nil)
      try checkoutTarget(repository: repository, target: name)
      return ["success": true]
    }
  }

  private func restoreRepositoryFile(arguments: [String: Any]) throws -> [String: Any?] {
    let workDir = try requiredString("workDir", in: arguments)
    let path = try requiredString("path", in: arguments)
    return try withRepository(path: workDir) { repository in
      var checkoutOptions = git_checkout_options()
      try check(git_checkout_init_options(&checkoutOptions, UInt32(GIT_CHECKOUT_OPTIONS_VERSION)), "Failed to initialize checkout options")
      checkoutOptions.checkout_strategy = UInt32(GIT_CHECKOUT_FORCE.rawValue)
      try withGitPathspec(path) { pathspec in
        checkoutOptions.paths = pathspec.pointee
        try check(git_checkout_head(repository, &checkoutOptions), "Restore failed")
      }
      return ["success": true]
    }
  }

  private func resetRepository(arguments: [String: Any]) throws -> [String: Any?] {
    let workDir = try requiredString("workDir", in: arguments)
    let target = ((arguments["target"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.isEmpty ? nil : $0 }
    let mode = ((arguments["mode"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.isEmpty ? nil : $0 }?.lowercased() ?? "mixed"
    let paths = (arguments["paths"] as? [String] ?? []).map {
      $0.trimmingCharacters(in: .whitespacesAndNewlines)
    }.filter { !$0.isEmpty }
    return try withRepository(path: workDir) { repository in
      if !paths.isEmpty {
        try withGitPathspecs(paths) { pathspec in
          try check(git_reset_default(repository, nil, pathspec), "Reset failed")
        }
      } else {
        let targetSpec = target ?? "HEAD"
        guard let oid = try resolveObjectId(repository: repository, spec: targetSpec) else {
          throw GitBridgeError("Unknown ref: \(targetSpec)")
        }
        var object: OpaquePointer?
        defer {
          if let object {
            git_object_free(object)
          }
        }
        var mutableOid = oid
        try check(git_object_lookup(&object, repository, &mutableOid, GIT_OBJECT_ANY), "Object not found: \(oidDescription(oid))")
        let resetMode: git_reset_t
        switch mode {
        case "soft":
          resetMode = GIT_RESET_SOFT
        case "mixed":
          resetMode = GIT_RESET_MIXED
        case "hard":
          resetMode = GIT_RESET_HARD
        default:
          throw GitBridgeError("Unknown reset mode: \(mode)")
        }
        try check(git_reset(repository, object, resetMode, nil), "Reset failed")
      }
      return [
        "success": true,
        "head": try headOidString(repository: repository),
      ]
    }
  }

  private func mergeRepositoryBranch(arguments: [String: Any]) throws -> [String: Any?] {
    let workDir = try requiredString("workDir", in: arguments)
    let action = ((arguments["action"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.isEmpty ? nil : $0 }?.lowercased() ?? "start"
    let branch = ((arguments["branch"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.isEmpty ? nil : $0 }
    let message = ((arguments["message"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.isEmpty ? nil : $0 } ?? "Merge commit"
    return try withRepository(path: workDir) { repository in
      if action == "abort" {
        try abortMerge(repository: repository)
        return [
          "success": true,
          "conflicts": [],
          "mergeCommit": try headOidString(repository: repository),
          "action": action,
          "error": nil,
        ]
      }
      if action == "continue" {
        let commit = try continueMerge(repository: repository, message: message)
        return [
          "success": true,
          "conflicts": [],
          "mergeCommit": commit,
          "action": action,
          "error": nil,
        ]
      }
      guard let branch else {
        throw GitBridgeError("Missing required parameter: branch")
      }
      let result = try performMerge(repository: repository, targetRef: branch, targetLabel: branch)
      return [
        "success": result.success,
        "conflicts": result.conflicts,
        "mergeCommit": result.mergeCommit,
        "action": action,
        "error": result.success ? nil : "Merge failed",
      ]
    }
  }

  private func fetchRepository(arguments: [String: Any]) throws -> [String: Any?] {
    let workDir = try requiredString("workDir", in: arguments)
    let remoteName = ((arguments["remoteName"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.isEmpty ? nil : $0 } ?? "origin"
    let branch = ((arguments["branch"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.isEmpty ? nil : $0 }
    let auth = GitAuthInfo(map: arguments["auth"] as? [String: Any])
    let updatedRefs = try withRepository(path: workDir) { repository in
      try fetch(repository: repository, remoteName: remoteName, branch: branch, auth: auth)
    }
    return [
      "success": true,
      "updatedRefs": updatedRefs,
      "objectsReceived": 0,
    ]
  }

  private func pullRepository(arguments: [String: Any]) throws -> [String: Any?] {
    let workDir = try requiredString("workDir", in: arguments)
    let remoteName = ((arguments["remoteName"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.isEmpty ? nil : $0 } ?? "origin"
    let branch = ((arguments["branch"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.isEmpty ? nil : $0 }
    let rebase = (arguments["rebase"] as? Bool) == true
    let auth = GitAuthInfo(map: arguments["auth"] as? [String: Any])

    let outcome = try withRepository(path: workDir) { repository -> PullOutcome in
      let updatedRefs = try fetch(repository: repository, remoteName: remoteName, branch: branch, auth: auth)
      let branchName = try branch ?? currentBranchName(repository: repository) ?? {
        throw GitBridgeError("Cannot pull in detached HEAD state")
      }()
      if rebase {
        try performRebasePull(repository: repository, remoteName: remoteName, branchName: branchName)
      } else {
        try performMergePull(repository: repository, remoteName: remoteName, branchName: branchName)
      }
      return PullOutcome(updatedRefs: updatedRefs)
    }
    return [
      "success": true,
      "fetchSuccess": true,
      "updatedRefs": outcome.updatedRefs,
      "objectsReceived": 0,
      "error": nil,
    ]
  }

  private func pushRepository(arguments: [String: Any]) throws -> [String: Any?] {
    let workDir = try requiredString("workDir", in: arguments)
    let remoteName = ((arguments["remoteName"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.isEmpty ? nil : $0 } ?? "origin"
    let refspec = ((arguments["refspec"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.isEmpty ? nil : $0 }
    let force = (arguments["force"] as? Bool) == true
    let auth = GitAuthInfo(map: arguments["auth"] as? [String: Any])

    let effectiveRefspec = try withRepository(path: workDir) { repository -> String in
      if let refspec {
        try push(repository: repository, remoteName: remoteName, refspec: refspec, auth: auth)
        return refspec
      }
      guard let branch = try currentBranchName(repository: repository) else {
        throw GitBridgeError("Detached HEAD push requires an explicit refspec")
      }
      let derived = "\(force ? "+" : "")refs/heads/\(branch):refs/heads/\(branch)"
      try push(repository: repository, remoteName: remoteName, refspec: derived, auth: auth)
      return derived
    }
    return [
      "success": true,
      "pushedRefs": [effectiveRefspec],
      "error": nil,
    ]
  }

  private func rebaseRepositoryTarget(arguments: [String: Any]) throws -> [String: Any?] {
    let workDir = try requiredString("workDir", in: arguments)
    let action = ((arguments["action"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.isEmpty ? nil : $0 }?.lowercased() ?? "start"
    let targetRef = ((arguments["targetRef"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.isEmpty ? nil : $0 }
    return try withRepository(path: workDir) { repository in
      switch action {
      case "start":
        guard let targetRef else {
          throw GitBridgeError("Missing required parameter: targetRef")
        }
        try performRebase(repository: repository, targetRef: targetRef)
      case "abort":
        try abortRebase(repository: repository)
      case "continue":
        try continueRebase(repository: repository)
      case "skip":
        try skipRebase(repository: repository)
      default:
        throw GitBridgeError("Unknown rebase action: \(action)")
      }
      return [
        "success": true,
        "conflicts": [],
        "action": action,
        "newHead": try headOidString(repository: repository),
      ]
    }
  }

  private func cherryPickRepositoryCommit(arguments: [String: Any]) throws -> [String: Any?] {
    let workDir = try requiredString("workDir", in: arguments)
    let action = ((arguments["action"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.isEmpty ? nil : $0 }?.lowercased() ?? "start"
    let ref = ((arguments["ref"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.isEmpty ? nil : $0 }
    let message = ((arguments["message"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.isEmpty ? nil : $0 } ?? "Cherry-pick commit"
    return try withRepository(path: workDir) { repository in
      switch action {
      case "start":
        guard let ref else {
          throw GitBridgeError("Missing required parameter: ref")
        }
        return try startCherryPick(repository: repository, ref: ref, message: message)
      case "continue":
        return try continueCherryPick(repository: repository, message: message)
      case "abort":
        try abortCherryPick(repository: repository)
        return [
          "success": true,
          "conflicts": [],
          "action": action,
          "newHead": try headOidString(repository: repository),
        ]
      default:
        throw GitBridgeError("Unknown cherry-pick action: \(action)")
      }
    }
  }

  private func getRepositoryConfigValue(arguments: [String: Any]) throws -> [String: Any?] {
    let workDir = try requiredString("workDir", in: arguments)
    let section = try requiredString("section", in: arguments)
    let key = try requiredString("key", in: arguments)
    return try withRepository(path: workDir) { repository in
      [
        "success": true,
        "value": try configValue(repository: repository, section: section, key: key),
      ]
    }
  }

  private func setRepositoryConfigValue(arguments: [String: Any]) throws -> [String: Any?] {
    let workDir = try requiredString("workDir", in: arguments)
    let section = try requiredString("section", in: arguments)
    let key = try requiredString("key", in: arguments)
    let value = try requiredString("value", in: arguments)
    return try withRepository(path: workDir) { repository in
      try setConfigValue(repository: repository, section: section, key: key, value: value)
      return ["success": true]
    }
  }

  private func getRepositoryRemoteUrl(arguments: [String: Any]) throws -> [String: Any?] {
    let workDir = try requiredString("workDir", in: arguments)
    let remoteName = ((arguments["remoteName"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.isEmpty ? nil : $0 } ?? "origin"
    return try withRepository(path: workDir) { repository in
      [
        "success": true,
        "url": try configValue(repository: repository, section: "remote.\(remoteName)", key: "url"),
      ]
    }
  }

  private func listRepositoryRemotes(arguments: [String: Any]) throws -> [String: Any?] {
    let workDir = try requiredString("workDir", in: arguments)
    return try withRepository(path: workDir) { repository in
      var names = git_strarray()
      defer {
        git_strarray_dispose(&names)
      }
      try check(git_remote_list(&names, repository), "Failed to list remotes")
      var remotes: [[String: Any?]] = []
      remotes.reserveCapacity(Int(names.count))
      for index in 0..<Int(names.count) {
        guard let nameCString = names.strings?[index] else {
          continue
        }
        let name = String(cString: nameCString)
        remotes.append([
          "name": name,
          "url": try configValue(repository: repository, section: "remote.\(name)", key: "url"),
        ])
      }
      remotes.sort { ($0["name"] as? String ?? "") < ($1["name"] as? String ?? "") }
      return [
        "success": true,
        "remotes": remotes,
      ]
    }
  }

  private func addRepositoryRemote(arguments: [String: Any]) throws -> [String: Any?] {
    let workDir = try requiredString("workDir", in: arguments)
    let remoteName = try requiredString("remoteName", in: arguments)
    let url = try requiredString("url", in: arguments)
    return try withRepository(path: workDir) { repository in
      var remote: OpaquePointer?
      defer {
        if let remote {
          git_remote_free(remote)
        }
      }
      try withGitCString(remoteName) { remoteNameCString in
        try withGitCString(url) { urlCString in
          try check(git_remote_create(&remote, repository, remoteNameCString, urlCString), "Failed to add remote")
        }
      }
      return ["success": true]
    }
  }

  private func setRepositoryRemoteUrl(arguments: [String: Any]) throws -> [String: Any?] {
    let workDir = try requiredString("workDir", in: arguments)
    let remoteName = try requiredString("remoteName", in: arguments)
    let url = try requiredString("url", in: arguments)
    return try withRepository(path: workDir) { repository in
      try withGitCString(remoteName) { remoteNameCString in
        try withGitCString(url) { urlCString in
          try check(git_remote_set_url(repository, remoteNameCString, urlCString), "Failed to update remote URL")
        }
      }
      return ["success": true]
    }
  }

  private func removeRepositoryRemote(arguments: [String: Any]) throws -> [String: Any?] {
    let workDir = try requiredString("workDir", in: arguments)
    let remoteName = try requiredString("remoteName", in: arguments)
    return try withRepository(path: workDir) { repository in
      try withGitCString(remoteName) { remoteNameCString in
        try check(git_remote_delete(repository, remoteNameCString), "Failed to remove remote")
      }
      return ["success": true]
    }
  }

  private func renameRepositoryRemote(arguments: [String: Any]) throws -> [String: Any?] {
    let workDir = try requiredString("workDir", in: arguments)
    let oldName = try requiredString("oldName", in: arguments)
    let newName = try requiredString("newName", in: arguments)
    return try withRepository(path: workDir) { repository in
      var problems = git_strarray()
      defer {
        git_strarray_dispose(&problems)
      }
      try withGitCString(oldName) { oldNameCString in
        try withGitCString(newName) { newNameCString in
          try check(git_remote_rename(&problems, repository, oldNameCString, newNameCString), "Failed to rename remote")
        }
      }
      return ["success": true]
    }
  }

  private func fetch(repository: OpaquePointer?, remoteName: String, branch: String?, auth: GitAuthInfo?) throws -> [String] {
    var remote: OpaquePointer?
    defer {
      if let remote {
        git_remote_free(remote)
      }
    }
    try withGitCString(remoteName) { remoteNameCString in
      try check(git_remote_lookup(&remote, repository, remoteNameCString), "Remote not found: \(remoteName)")
    }
    let context = GitOperationContext(auth: auth, remoteName: remoteName)
    let payload = Unmanaged.passRetained(context)
    defer { payload.release() }
    var options = git_fetch_options()
    try check(git_fetch_init_options(&options, UInt32(GIT_FETCH_OPTIONS_VERSION)), "Failed to initialize fetch options")
    options.callbacks.credentials = gitCredentialAcquireCallback
    options.callbacks.certificate_check = gitCertificateCheckCallback
    options.callbacks.payload = payload.toOpaque()
    options.prune = GIT_FETCH_PRUNE_UNSPECIFIED

    let updatedRefs: [String]
    if let branch {
      let refspec = "+refs/heads/\(branch):refs/remotes/\(remoteName)/\(branch)"
      try withGitStrarray([refspec]) { refspecs in
        try check(git_remote_fetch(remote, refspecs, &options, nil), "Fetch failed")
      }
      updatedRefs = ["refs/remotes/\(remoteName)/\(branch)"]
    } else {
      try check(git_remote_fetch(remote, nil, &options, nil), "Fetch failed")
      updatedRefs = []
    }
    return updatedRefs
  }

  private func push(repository: OpaquePointer?, remoteName: String, refspec: String, auth: GitAuthInfo?) throws {
    var remote: OpaquePointer?
    defer {
      if let remote {
        git_remote_free(remote)
      }
    }
    try withGitCString(remoteName) { remoteNameCString in
      try check(git_remote_lookup(&remote, repository, remoteNameCString), "Remote not found: \(remoteName)")
    }
    let context = GitOperationContext(auth: auth, remoteName: remoteName)
    let payload = Unmanaged.passRetained(context)
    defer { payload.release() }

    var callbacks = git_remote_callbacks()
    try check(git_remote_init_callbacks(&callbacks, UInt32(GIT_REMOTE_CALLBACKS_VERSION)), "Failed to initialize remote callbacks")
    callbacks.credentials = gitCredentialAcquireCallback
    callbacks.certificate_check = gitCertificateCheckCallback
    callbacks.payload = payload.toOpaque()

    var options = git_push_options()
    try check(git_push_init_options(&options, UInt32(GIT_PUSH_OPTIONS_VERSION)), "Failed to initialize push options")
    options.callbacks = callbacks

    try withGitStrarray([refspec]) { refspecs in
      try check(git_remote_push(remote, refspecs, &options), "Push failed")
    }
  }

  private func performMergePull(repository: OpaquePointer?, remoteName: String, branchName: String) throws {
    let remoteRefName = "refs/remotes/\(remoteName)/\(branchName)"
    var annotated: OpaquePointer?
    defer {
      if let annotated {
        git_annotated_commit_free(annotated)
      }
    }
    try withGitCString(remoteRefName) { remoteRefCString in
      try check(git_annotated_commit_from_revspec(&annotated, repository, remoteRefCString), "Reference not found: \(remoteRefName)")
    }
    var analysis = git_merge_analysis_t(rawValue: 0)
    var preference = git_merge_preference_t(rawValue: 0)
    var commits = [annotated]
    let analysisResult = git_merge_analysis(&analysis, &preference, repository, &commits, commits.count)
    try check(analysisResult, "Pull failed")
    if (analysis.rawValue & GIT_MERGE_ANALYSIS_UP_TO_DATE.rawValue) != 0 {
      return
    }
    if (analysis.rawValue & GIT_MERGE_ANALYSIS_FASTFORWARD.rawValue) != 0 {
      try fastForward(repository: repository, branchName: branchName, targetAnnotated: annotated, remoteRefName: remoteRefName)
      return
    }
    if (analysis.rawValue & GIT_MERGE_ANALYSIS_NORMAL.rawValue) == 0 {
      throw GitBridgeError("Pull failed")
    }

    var mergeOptions = git_merge_options()
    try check(git_merge_init_options(&mergeOptions, UInt32(GIT_MERGE_OPTIONS_VERSION)), "Failed to initialize merge options")
    var checkoutOptions = git_checkout_options()
    try check(git_checkout_init_options(&checkoutOptions, UInt32(GIT_CHECKOUT_OPTIONS_VERSION)), "Failed to initialize checkout options")
    checkoutOptions.checkout_strategy = UInt32(GIT_CHECKOUT_SAFE.rawValue)
    let mergeResult = git_merge(repository, &commits, commits.count, &mergeOptions, &checkoutOptions)
    try check(mergeResult, "Pull failed")

    var index: OpaquePointer?
    defer {
      if let index {
        git_index_free(index)
      }
      git_repository_state_cleanup(repository)
    }
    try check(git_repository_index(&index, repository), "Pull failed")
    if git_index_has_conflicts(index) != 0 {
      throw GitBridgeError("Pull failed: CONFLICTING")
    }
    var signature: UnsafeMutablePointer<git_signature>?
    defer {
      if let signature {
        git_signature_free(signature)
      }
    }
    try signatureNow(repository: repository, name: nil, email: nil, output: &signature)
    let message = "Merge remote-tracking branch '\(remoteName)/\(branchName)'"
    let mergeHead = try mergeHeadOid(repository: repository)
    _ = try createCommitFromIndex(
      repository: repository,
      message: message,
      signature: signature,
      extraParents: [mergeHead]
    )
  }

  private func performRebasePull(repository: OpaquePointer?, remoteName: String, branchName: String) throws {
    var headRef: OpaquePointer?
    var branchAnnotated: OpaquePointer?
    var upstreamAnnotated: OpaquePointer?
    var rebase: OpaquePointer?
    defer {
      if let headRef { git_reference_free(headRef) }
      if let branchAnnotated { git_annotated_commit_free(branchAnnotated) }
      if let upstreamAnnotated { git_annotated_commit_free(upstreamAnnotated) }
      if let rebase { git_rebase_free(rebase) }
      git_repository_state_cleanup(repository)
    }
    try check(git_repository_head(&headRef, repository), "Cannot pull in detached HEAD state")
    try check(git_annotated_commit_from_ref(&branchAnnotated, repository, headRef), "Pull failed")
    let upstreamRef = "refs/remotes/\(remoteName)/\(branchName)"
    try withGitCString(upstreamRef) { upstreamRefCString in
      try check(git_annotated_commit_from_revspec(&upstreamAnnotated, repository, upstreamRefCString), "Reference not found: \(upstreamRef)")
    }

    var options = git_rebase_options()
    try check(git_rebase_init_options(&options, UInt32(GIT_REBASE_OPTIONS_VERSION)), "Failed to initialize rebase options")
    try check(git_rebase_init(&rebase, repository, branchAnnotated, upstreamAnnotated, nil, &options), "Pull failed")

    var operation: UnsafeMutablePointer<git_rebase_operation>?
    while true {
      let nextCode = git_rebase_next(&operation, rebase)
      if nextCode == GIT_ITEROVER.rawValue {
        break
      }
      try check(nextCode, "Pull failed")

      var index: OpaquePointer?
      defer {
        if let index {
          git_index_free(index)
        }
      }
      try check(git_repository_index(&index, repository), "Pull failed")
      if git_index_has_conflicts(index) != 0 {
        throw GitBridgeError("Pull failed: CONFLICTING")
      }

      var signature: UnsafeMutablePointer<git_signature>?
      defer {
        if let signature {
          git_signature_free(signature)
        }
      }
      try signatureNow(repository: repository, name: nil, email: nil, output: &signature)
      var oid = git_oid()
      let commitCode = git_rebase_commit(&oid, rebase, nil, signature, nil, nil)
      if commitCode == GIT_EAPPLIED.rawValue {
        continue
      }
      try check(commitCode, "Pull failed")
    }
    try check(git_rebase_finish(rebase, nil), "Pull failed")
  }

  private func fastForward(repository: OpaquePointer?, branchName: String, targetAnnotated: OpaquePointer?, remoteRefName: String) throws {
    var oid = git_oid()
    try withGitCString(remoteRefName) { remoteRefCString in
      try check(git_reference_name_to_id(&oid, repository, remoteRefCString), "Reference not found: \(remoteRefName)")
    }

    var localRef: OpaquePointer?
    var updatedRef: OpaquePointer?
    var targetCommit: OpaquePointer?
    var targetObject: OpaquePointer?
    defer {
      if let localRef { git_reference_free(localRef) }
      if let updatedRef { git_reference_free(updatedRef) }
      if let targetCommit { git_commit_free(targetCommit) }
      if let targetObject { git_object_free(targetObject) }
    }

    let localRefName = "refs/heads/\(branchName)"
    try withGitCString(localRefName) { localRefCString in
      try check(git_reference_lookup(&localRef, repository, localRefCString), "Reference not found: \(localRefName)")
      try check(git_reference_set_target(&updatedRef, localRef, &oid, nil), "Pull failed")
      try check(git_repository_set_head(repository, localRefCString), "Pull failed")
    }
    try check(git_commit_lookup(&targetCommit, repository, &oid), "Object not found: \(oidDescription(oid))")
    try check(git_revparse_single(&targetObject, repository, oidDescription(oid)), "Object not found: \(oidDescription(oid))")
    var checkoutOptions = git_checkout_options()
    try check(git_checkout_init_options(&checkoutOptions, UInt32(GIT_CHECKOUT_OPTIONS_VERSION)), "Failed to initialize checkout options")
    checkoutOptions.checkout_strategy = UInt32(GIT_CHECKOUT_SAFE.rawValue)
    try check(git_checkout_tree(repository, targetObject, &checkoutOptions), "Pull failed")
  }

  private func performMerge(repository: OpaquePointer?, targetRef: String, targetLabel: String) throws -> MergeOutcome {
    var annotated: OpaquePointer?
    var shouldCleanupState = false
    defer {
      if let annotated {
        git_annotated_commit_free(annotated)
      }
      if shouldCleanupState {
        git_repository_state_cleanup(repository)
      }
    }
    try withGitCString(targetRef) { targetRefCString in
      try check(git_annotated_commit_from_revspec(&annotated, repository, targetRefCString), "Reference not found: \(targetRef)")
    }
    var analysis = git_merge_analysis_t(rawValue: 0)
    var preference = git_merge_preference_t(rawValue: 0)
    var commits = [annotated]
    try check(git_merge_analysis(&analysis, &preference, repository, &commits, commits.count), "Merge failed")
    if (analysis.rawValue & GIT_MERGE_ANALYSIS_UP_TO_DATE.rawValue) != 0 {
      return MergeOutcome(success: true, conflicts: [], mergeCommit: nil)
    }
    if (analysis.rawValue & GIT_MERGE_ANALYSIS_FASTFORWARD.rawValue) != 0 {
      let branchName = try currentBranchName(repository: repository) ?? {
        throw GitBridgeError("Cannot merge in detached HEAD state")
      }()
      try fastForward(repository: repository, branchName: branchName, targetAnnotated: annotated, remoteRefName: targetRef)
      return MergeOutcome(success: true, conflicts: [], mergeCommit: try headOidString(repository: repository))
    }
    var mergeOptions = git_merge_options()
    try check(git_merge_init_options(&mergeOptions, UInt32(GIT_MERGE_OPTIONS_VERSION)), "Failed to initialize merge options")
    var checkoutOptions = git_checkout_options()
    try check(git_checkout_init_options(&checkoutOptions, UInt32(GIT_CHECKOUT_OPTIONS_VERSION)), "Failed to initialize checkout options")
    checkoutOptions.checkout_strategy = UInt32(GIT_CHECKOUT_SAFE.rawValue)
    try check(git_merge(repository, &commits, commits.count, &mergeOptions, &checkoutOptions), "Merge failed")
    var index: OpaquePointer?
    defer {
      if let index {
        git_index_free(index)
      }
    }
    try check(git_repository_index(&index, repository), "Merge failed")
    if git_index_has_conflicts(index) != 0 {
      let conflicts = try conflictPaths(index: index)
      return MergeOutcome(success: false, conflicts: conflicts, mergeCommit: nil)
    }
    var signature: UnsafeMutablePointer<git_signature>?
    defer {
      if let signature {
        git_signature_free(signature)
      }
    }
    try signatureNow(repository: repository, name: nil, email: nil, output: &signature)
    let message = "Merge \(targetLabel)"
    let mergeHead = try mergeHeadOid(repository: repository)
    let oid = try createCommitFromIndex(
      repository: repository,
      message: message,
      signature: signature,
      extraParents: [mergeHead]
    )
    shouldCleanupState = true
    return MergeOutcome(success: true, conflicts: [], mergeCommit: oidDescription(oid))
  }

  private func performRebase(repository: OpaquePointer?, targetRef: String) throws {
    var headRef: OpaquePointer?
    var branchAnnotated: OpaquePointer?
    var upstreamAnnotated: OpaquePointer?
    var rebase: OpaquePointer?
    var shouldCleanupState = false
    defer {
      if let headRef { git_reference_free(headRef) }
      if let branchAnnotated { git_annotated_commit_free(branchAnnotated) }
      if let upstreamAnnotated { git_annotated_commit_free(upstreamAnnotated) }
      if let rebase { git_rebase_free(rebase) }
      if shouldCleanupState {
        git_repository_state_cleanup(repository)
      }
    }
    try check(git_repository_head(&headRef, repository), "Cannot rebase in detached HEAD state")
    try check(git_annotated_commit_from_ref(&branchAnnotated, repository, headRef), "Rebase failed")
    try withGitCString(targetRef) { targetRefCString in
      try check(git_annotated_commit_from_revspec(&upstreamAnnotated, repository, targetRefCString), "Reference not found: \(targetRef)")
    }
    var options = git_rebase_options()
    try check(git_rebase_init_options(&options, UInt32(GIT_REBASE_OPTIONS_VERSION)), "Failed to initialize rebase options")
    try check(git_rebase_init(&rebase, repository, branchAnnotated, upstreamAnnotated, nil, &options), "Rebase failed")
    var operation: UnsafeMutablePointer<git_rebase_operation>?
    while true {
      let nextCode = git_rebase_next(&operation, rebase)
      if nextCode == GIT_ITEROVER.rawValue {
        break
      }
      try check(nextCode, "Rebase failed")
      var index: OpaquePointer?
      defer {
        if let index {
          git_index_free(index)
        }
      }
      try check(git_repository_index(&index, repository), "Rebase failed")
      if git_index_has_conflicts(index) != 0 {
        throw GitBridgeError("Rebase failed: conflicts")
      }
      var signature: UnsafeMutablePointer<git_signature>?
      defer {
        if let signature {
          git_signature_free(signature)
        }
      }
      try signatureNow(repository: repository, name: nil, email: nil, output: &signature)
      var oid = git_oid()
      let commitCode = git_rebase_commit(&oid, rebase, nil, signature, nil, nil)
      if commitCode == GIT_EAPPLIED.rawValue {
        continue
      }
      try check(commitCode, "Rebase failed")
    }
    try check(git_rebase_finish(rebase, nil), "Rebase failed")
    shouldCleanupState = true
  }

  private func abortMerge(repository: OpaquePointer?) throws {
    var checkoutOptions = git_checkout_options()
    try check(git_checkout_init_options(&checkoutOptions, UInt32(GIT_CHECKOUT_OPTIONS_VERSION)), "Failed to initialize checkout options")
    checkoutOptions.checkout_strategy = UInt32(GIT_CHECKOUT_FORCE.rawValue)
    try check(git_checkout_head(repository, &checkoutOptions), "Merge abort failed")
    git_repository_state_cleanup(repository)
  }

  private func continueMerge(repository: OpaquePointer?, message: String) throws -> String {
    var index: OpaquePointer?
    var signature: UnsafeMutablePointer<git_signature>?
    defer {
      if let index {
        git_index_free(index)
      }
      if let signature {
        git_signature_free(signature)
      }
      git_repository_state_cleanup(repository)
    }
    try check(git_repository_index(&index, repository), "Merge continue failed")
    if git_index_has_conflicts(index) != 0 {
      throw GitBridgeError("Merge failed: CONFLICTING")
    }
    try signatureNow(repository: repository, name: nil, email: nil, output: &signature)
    let mergeHead = try mergeHeadOid(repository: repository)
    let oid = try createCommitFromIndex(
      repository: repository,
      message: message,
      signature: signature,
      extraParents: [mergeHead]
    )
    return oidDescription(oid)
  }

  private func abortRebase(repository: OpaquePointer?) throws {
    var rebase: OpaquePointer?
    defer {
      if let rebase {
        git_rebase_free(rebase)
      }
      git_repository_state_cleanup(repository)
    }
    var options = git_rebase_options()
    try check(git_rebase_init_options(&options, UInt32(GIT_REBASE_OPTIONS_VERSION)), "Failed to initialize rebase options")
    try check(git_rebase_open(&rebase, repository, &options), "No rebase in progress")
    try check(git_rebase_abort(rebase), "Rebase abort failed")
  }

  private func continueRebase(repository: OpaquePointer?) throws {
    var rebase: OpaquePointer?
    var shouldCleanupState = false
    defer {
      if let rebase {
        git_rebase_free(rebase)
      }
      if shouldCleanupState {
        git_repository_state_cleanup(repository)
      }
    }
    var options = git_rebase_options()
    try check(git_rebase_init_options(&options, UInt32(GIT_REBASE_OPTIONS_VERSION)), "Failed to initialize rebase options")
    try check(git_rebase_open(&rebase, repository, &options), "No rebase in progress")

    var index: OpaquePointer?
    defer {
      if let index {
        git_index_free(index)
      }
    }
    try check(git_repository_index(&index, repository), "Rebase failed")
    if git_index_has_conflicts(index) != 0 {
      throw GitBridgeError("Rebase failed: conflicts")
    }

    var signature: UnsafeMutablePointer<git_signature>?
    defer {
      if let signature {
        git_signature_free(signature)
      }
    }
    try signatureNow(repository: repository, name: nil, email: nil, output: &signature)

    var oid = git_oid()
    let currentCommit = git_rebase_commit(&oid, rebase, nil, signature, nil, nil)
    if currentCommit != GIT_EAPPLIED.rawValue {
      try check(currentCommit, "Rebase failed")
    }

    var operation: UnsafeMutablePointer<git_rebase_operation>?
    while true {
      let nextCode = git_rebase_next(&operation, rebase)
      if nextCode == GIT_ITEROVER.rawValue {
        break
      }
      try check(nextCode, "Rebase failed")
      try check(git_repository_index(&index, repository), "Rebase failed")
      if git_index_has_conflicts(index) != 0 {
        throw GitBridgeError("Rebase failed: conflicts")
      }
      var nextOid = git_oid()
      let commitCode = git_rebase_commit(&nextOid, rebase, nil, signature, nil, nil)
      if commitCode == GIT_EAPPLIED.rawValue {
        continue
      }
      try check(commitCode, "Rebase failed")
    }
    try check(git_rebase_finish(rebase, nil), "Rebase failed")
    shouldCleanupState = true
  }

  private func skipRebase(repository: OpaquePointer?) throws {
    var rebase: OpaquePointer?
    var shouldCleanupState = false
    defer {
      if let rebase {
        git_rebase_free(rebase)
      }
      if shouldCleanupState {
        git_repository_state_cleanup(repository)
      }
    }
    var options = git_rebase_options()
    try check(git_rebase_init_options(&options, UInt32(GIT_REBASE_OPTIONS_VERSION)), "Failed to initialize rebase options")
    try check(git_rebase_open(&rebase, repository, &options), "No rebase in progress")

    var checkoutOptions = git_checkout_options()
    try check(git_checkout_init_options(&checkoutOptions, UInt32(GIT_CHECKOUT_OPTIONS_VERSION)), "Failed to initialize checkout options")
    checkoutOptions.checkout_strategy = UInt32(GIT_CHECKOUT_FORCE.rawValue)
    try check(git_checkout_head(repository, &checkoutOptions), "Rebase skip failed")

    var operation: UnsafeMutablePointer<git_rebase_operation>?
    while true {
      let nextCode = git_rebase_next(&operation, rebase)
      if nextCode == GIT_ITEROVER.rawValue {
        break
      }
      try check(nextCode, "Rebase failed")
      var index: OpaquePointer?
      defer {
        if let index {
          git_index_free(index)
        }
      }
      try check(git_repository_index(&index, repository), "Rebase failed")
      if git_index_has_conflicts(index) != 0 {
        throw GitBridgeError("Rebase failed: conflicts")
      }
      var signature: UnsafeMutablePointer<git_signature>?
      defer {
        if let signature {
          git_signature_free(signature)
        }
      }
      try signatureNow(repository: repository, name: nil, email: nil, output: &signature)
      var oid = git_oid()
      let commitCode = git_rebase_commit(&oid, rebase, nil, signature, nil, nil)
      if commitCode == GIT_EAPPLIED.rawValue {
        continue
      }
      try check(commitCode, "Rebase failed")
    }
    try check(git_rebase_finish(rebase, nil), "Rebase failed")
    shouldCleanupState = true
  }

  private func startCherryPick(repository: OpaquePointer?, ref: String, message: String) throws -> [String: Any?] {
    guard let oid = try resolveObjectId(repository: repository, spec: ref) else {
      throw GitBridgeError("Unknown ref: \(ref)")
    }
    var commit: OpaquePointer?
    var index: OpaquePointer?
    var shouldCleanupState = false
    defer {
      if let commit { git_commit_free(commit) }
      if let index { git_index_free(index) }
      if shouldCleanupState {
        git_repository_state_cleanup(repository)
      }
    }
    var mutableOid = oid
    try check(git_commit_lookup(&commit, repository, &mutableOid), "Object not found: \(oidDescription(oid))")
    var options = git_cherrypick_options()
    try check(git_cherrypick_options_init(&options, UInt32(GIT_CHERRYPICK_OPTIONS_VERSION)), "Failed to initialize cherry-pick options")
    options.checkout_opts.checkout_strategy = UInt32(GIT_CHECKOUT_SAFE.rawValue)
    try check(git_cherrypick(repository, commit, &options), "Cherry-pick failed")
    try check(git_repository_index(&index, repository), "Cherry-pick failed")
    if git_index_has_conflicts(index) != 0 {
      return [
        "success": false,
        "conflicts": try conflictPaths(index: index),
        "action": "start",
        "newHead": try headOidString(repository: repository),
        "error": "Cherry-pick failed: CONFLICTING",
      ]
    }
    var signature: UnsafeMutablePointer<git_signature>?
    defer {
      if let signature { git_signature_free(signature) }
    }
    try signatureNow(repository: repository, name: nil, email: nil, output: &signature)
    let oid = try createCommitFromIndex(
      repository: repository,
      message: message,
      signature: signature,
      extraParents: []
    )
    shouldCleanupState = true
    return [
      "success": true,
      "conflicts": [],
      "action": "start",
      "newHead": oidDescription(oid),
      "cherryPickCommit": oidDescription(oid),
    ]
  }

  private func continueCherryPick(repository: OpaquePointer?, message: String) throws -> [String: Any?] {
    _ = try cherryPickHeadOid(repository: repository)
    var index: OpaquePointer?
    var signature: UnsafeMutablePointer<git_signature>?
    var shouldCleanupState = false
    defer {
      if let index { git_index_free(index) }
      if let signature { git_signature_free(signature) }
      if shouldCleanupState {
        git_repository_state_cleanup(repository)
      }
    }
    try check(git_repository_index(&index, repository), "Cherry-pick failed")
    if git_index_has_conflicts(index) != 0 {
      return [
        "success": false,
        "conflicts": try conflictPaths(index: index),
        "action": "continue",
        "newHead": try headOidString(repository: repository),
        "error": "Cherry-pick failed: CONFLICTING",
      ]
    }
    try signatureNow(repository: repository, name: nil, email: nil, output: &signature)
    let oid = try createCommitFromIndex(
      repository: repository,
      message: message,
      signature: signature,
      extraParents: []
    )
    shouldCleanupState = true
    return [
      "success": true,
      "conflicts": [],
      "action": "continue",
      "newHead": oidDescription(oid),
      "cherryPickCommit": oidDescription(oid),
    ]
  }

  private func abortCherryPick(repository: OpaquePointer?) throws {
    _ = try cherryPickHeadOid(repository: repository)
    var checkoutOptions = git_checkout_options()
    try check(git_checkout_init_options(&checkoutOptions, UInt32(GIT_CHECKOUT_OPTIONS_VERSION)), "Failed to initialize checkout options")
    checkoutOptions.checkout_strategy = UInt32(GIT_CHECKOUT_FORCE.rawValue)
    try check(git_checkout_head(repository, &checkoutOptions), "Cherry-pick abort failed")
    git_repository_state_cleanup(repository)
  }

  private func listBranches(repository: OpaquePointer?) throws -> [String] {
    var iterator: OpaquePointer?
    defer {
      if let iterator {
        git_branch_iterator_free(iterator)
      }
    }
    try check(git_branch_iterator_new(&iterator, repository, GIT_BRANCH_LOCAL), "Failed to list branches")
    var branches: [String] = []
    while true {
      var reference: OpaquePointer?
      var branchType = git_branch_t(rawValue: 0)
      let code = git_branch_next(&reference, &branchType, iterator)
      if code == GIT_ITEROVER.rawValue {
        break
      }
      try check(code, "Failed to list branches")
      defer {
        if let reference {
          git_reference_free(reference)
        }
      }
      var namePointer: UnsafePointer<CChar>?
      try check(git_branch_name(&namePointer, reference), "Failed to read branch name")
      if let namePointer {
        branches.append(String(cString: namePointer))
      }
    }
    return branches.sorted()
  }

  private func createBranch(repository: OpaquePointer?, name: String, startPoint: String?) throws {
    var commit: OpaquePointer?
    var reference: OpaquePointer?
    defer {
      if let commit {
        git_commit_free(commit)
      }
      if let reference {
        git_reference_free(reference)
      }
    }
    let spec = startPoint ?? "HEAD"
    guard let oid = try resolveObjectId(repository: repository, spec: spec) else {
      throw GitBridgeError("Unknown ref: \(spec)")
    }
    var mutableOid = oid
    try check(git_commit_lookup(&commit, repository, &mutableOid), "Object not found: \(oidDescription(oid))")
    try withGitCString(name) { nameCString in
      try check(git_branch_create(&reference, repository, nameCString, commit, 0), "Branch create failed")
    }
  }

  private func deleteBranch(repository: OpaquePointer?, name: String, force: Bool) throws {
    var reference: OpaquePointer?
    defer {
      if let reference {
        git_reference_free(reference)
      }
    }
    try withGitCString(name) { nameCString in
      try check(git_branch_lookup(&reference, repository, nameCString, GIT_BRANCH_LOCAL), "Branch not found: \(name)")
    }
    if !force {
      let current = try currentBranchName(repository: repository)
      if current == name {
        throw GitBridgeError("Cannot delete checked out branch: \(name)")
      }
    }
    try check(git_branch_delete(reference), "Branch delete failed")
  }

  private func checkoutTarget(repository: OpaquePointer?, target: String) throws {
    if let _ = try? lookupLocalBranch(repository: repository, name: target) {
      try checkoutLocalBranch(repository: repository, name: target)
      return
    }
    guard let oid = try resolveObjectId(repository: repository, spec: target) else {
      throw GitBridgeError("Unknown ref: \(target)")
    }
    try checkoutDetached(repository: repository, oid: oid)
  }

  private func lookupLocalBranch(repository: OpaquePointer?, name: String) throws -> OpaquePointer? {
    var reference: OpaquePointer?
    do {
      try withGitCString(name) { nameCString in
        try check(git_branch_lookup(&reference, repository, nameCString, GIT_BRANCH_LOCAL), "Branch not found: \(name)")
      }
      return reference
    } catch {
      if let reference {
        git_reference_free(reference)
      }
      throw error
    }
  }

  private func checkoutLocalBranch(repository: OpaquePointer?, name: String) throws {
    var reference: OpaquePointer?
    defer {
      if let reference {
        git_reference_free(reference)
      }
    }
    try withGitCString(name) { nameCString in
      try check(git_branch_lookup(&reference, repository, nameCString, GIT_BRANCH_LOCAL), "Branch not found: \(name)")
      guard let fullName = git_reference_name(reference) else {
        throw GitBridgeError("Branch not found: \(name)")
      }
      var checkoutOptions = git_checkout_options()
      try check(git_checkout_init_options(&checkoutOptions, UInt32(GIT_CHECKOUT_OPTIONS_VERSION)), "Failed to initialize checkout options")
      checkoutOptions.checkout_strategy = UInt32(GIT_CHECKOUT_SAFE.rawValue)
      try check(git_checkout_head(repository, &checkoutOptions), "Checkout failed")
      try check(git_repository_set_head(repository, fullName), "Checkout failed")
    }
  }

  private func checkoutDetached(repository: OpaquePointer?, oid: git_oid) throws {
    var commit: OpaquePointer?
    defer {
      if let commit {
        git_commit_free(commit)
      }
    }
    var mutableOid = oid
    try check(git_commit_lookup(&commit, repository, &mutableOid), "Object not found: \(oidDescription(oid))")
    var checkoutOptions = git_checkout_options()
    try check(git_checkout_init_options(&checkoutOptions, UInt32(GIT_CHECKOUT_OPTIONS_VERSION)), "Failed to initialize checkout options")
    checkoutOptions.checkout_strategy = UInt32(GIT_CHECKOUT_SAFE.rawValue)
    try check(git_checkout_tree(repository, commit, &checkoutOptions), "Checkout failed")
    try check(git_repository_set_head_detached(repository, &mutableOid), "Checkout failed")
  }

  private func resolveObjectId(repository: OpaquePointer?, spec: String) throws -> git_oid? {
    var object: OpaquePointer?
    defer {
      if let object {
        git_object_free(object)
      }
    }
    let code = try withGitCString(spec) { specCString in
      git_revparse_single(&object, repository, specCString)
    }
    if code == GIT_ENOTFOUND.rawValue {
      return nil
    }
    try check(code, "Unknown ref: \(spec)")
    guard let object else {
      return nil
    }
    return git_object_id(object).pointee
  }

  private func headOidString(repository: OpaquePointer?) throws -> String? {
    guard let oid = try resolveObjectId(repository: repository, spec: "HEAD") else {
      return nil
    }
    return oidDescription(oid)
  }

  private func commitPayload(repository: OpaquePointer?, oid: git_oid) throws -> [String: Any?] {
    var commit: OpaquePointer?
    defer {
      if let commit {
        git_commit_free(commit)
      }
    }
    var mutableOid = oid
    try check(git_commit_lookup(&commit, repository, &mutableOid), "Object not found: \(oidDescription(oid))")
    guard let commit else {
      throw GitBridgeError("Commit not found")
    }
    let author = git_commit_author(commit)
    let committer = git_commit_committer(commit)
    let tree = git_commit_tree_id(commit).pointee
    let parentCount = Int(git_commit_parentcount(commit))
    var parents: [String] = []
    if parentCount > 0 {
      parents.reserveCapacity(parentCount)
      for index in 0..<parentCount {
        if let parentId = git_commit_parent_id(commit, UInt32(index)) {
          parents.append(oidDescription(parentId.pointee))
        }
      }
    }
    return [
      "hash": oidDescription(mutableOid),
      "tree": oidDescription(tree),
      "parents": parents,
      "message": git_commit_message(commit).map { String(cString: $0) } ?? "",
      "authorName": author?.pointee.name.map { String(cString: $0) } ?? "Unknown",
      "authorEmail": author?.pointee.email.map { String(cString: $0) } ?? "unknown@example.com",
      "authorTimestampMs": Int((author?.pointee.when.time ?? 0) * 1000),
      "authorTimezone": timezoneString(offsetMinutes: Int(author?.pointee.when.offset ?? 0)),
      "committerName": committer?.pointee.name.map { String(cString: $0) } ?? "Unknown",
      "committerEmail": committer?.pointee.email.map { String(cString: $0) } ?? "unknown@example.com",
      "committerTimestampMs": Int((committer?.pointee.when.time ?? 0) * 1000),
      "committerTimezone": timezoneString(offsetMinutes: Int(committer?.pointee.when.offset ?? 0)),
    ]
  }

  private func oidFromString(_ value: String) -> git_oid? {
    var oid = git_oid()
    let code = value.withCString { git_oid_fromstr(&oid, $0) }
    return code == 0 ? oid : nil
  }

  private func conflictPaths(index: OpaquePointer?) throws -> [String] {
    var iterator: OpaquePointer?
    defer {
      if let iterator {
        git_index_conflict_iterator_free(iterator)
      }
    }
    try check(git_index_conflict_iterator_new(&iterator, index), "Merge failed")
    var paths = Set<String>()
    while true {
      var ancestor: UnsafePointer<git_index_entry>?
      var ours: UnsafePointer<git_index_entry>?
      var theirs: UnsafePointer<git_index_entry>?
      let code = git_index_conflict_next(&ancestor, &ours, &theirs, iterator)
      if code == GIT_ITEROVER.rawValue {
        break
      }
      try check(code, "Merge failed")
      let path = ancestor?.pointee.path ?? ours?.pointee.path ?? theirs?.pointee.path
      if let path {
        paths.insert(String(cString: path))
      }
    }
    return paths.sorted()
  }

  private func configValue(repository: OpaquePointer?, section: String, key: String) throws -> String? {
    var config: OpaquePointer?
    defer {
      if let config {
        git_config_free(config)
      }
    }
    try check(git_repository_config(&config, repository), "Failed to read config")
    let fullKey = "\(section).\(key)"
    var buffer = git_buf()
    defer {
      git_buf_free(&buffer)
    }
    let code = try withGitCString(fullKey) { keyCString in
      git_config_get_string_buf(&buffer, config, keyCString)
    }
    if code == GIT_ENOTFOUND.rawValue {
      return nil
    }
    try check(code, "Failed to read config")
    guard let ptr = buffer.ptr else {
      return nil
    }
    return String(cString: ptr)
  }

  private func setConfigValue(repository: OpaquePointer?, section: String, key: String, value: String) throws {
    var config: OpaquePointer?
    defer {
      if let config {
        git_config_free(config)
      }
    }
    try check(git_repository_config(&config, repository), "Failed to open config")
    let fullKey = "\(section).\(key)"
    try withGitCString(fullKey) { keyCString in
      try withGitCString(value) { valueCString in
        try check(git_config_set_string(config, keyCString, valueCString), "Failed to update config")
      }
    }
  }

  private func parseDateFilter(_ value: String?) -> Int? {
    let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    guard !trimmed.isEmpty else {
      return nil
    }
    if let date = ISO8601DateFormatter().date(from: trimmed) {
      return Int(date.timeIntervalSince1970 * 1000)
    }
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd"
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    return formatter.date(from: trimmed).map { Int($0.timeIntervalSince1970 * 1000) }
  }

  private func statusEntryPath(_ entry: git_status_entry) -> String {
    if let path = entry.head_to_index?.pointee.new_file.path {
      return String(cString: path)
    }
    if let path = entry.index_to_workdir?.pointee.new_file.path {
      return String(cString: path)
    }
    if let path = entry.head_to_index?.pointee.old_file.path {
      return String(cString: path)
    }
    if let path = entry.index_to_workdir?.pointee.old_file.path {
      return String(cString: path)
    }
    return ""
  }

  private func currentBranchName(repository: OpaquePointer?) throws -> String? {
    var head: OpaquePointer?
    defer {
      if let head {
        git_reference_free(head)
      }
    }
    let result = git_repository_head(&head, repository)
    if result == GIT_EUNBORNBRANCH.rawValue || result == GIT_ENOTFOUND.rawValue {
      return nil
    }
    try check(result, "Failed to read HEAD")
    guard let shorthand = git_reference_shorthand(head) else {
      return nil
    }
    return String(cString: shorthand)
  }

  private func commitResult(repository: OpaquePointer?, oid: git_oid) throws -> [String: Any?] {
    var commit: OpaquePointer?
    defer {
      if let commit {
        git_commit_free(commit)
      }
    }
    var oidCopy = oid
    try check(git_commit_lookup(&commit, repository, &oidCopy), "Object not found: \(oidDescription(oidCopy))")
    guard let commit else {
      throw GitBridgeError("Commit failed")
    }
    let author = git_commit_author(commit)
    let committer = git_commit_committer(commit)
    let tree = git_commit_tree_id(commit).pointee
    let parentCount = Int(git_commit_parentcount(commit))
    var parents: [String] = []
    if parentCount > 0 {
      parents.reserveCapacity(parentCount)
      for index in 0..<parentCount {
        if let parentId = git_commit_parent_id(commit, UInt32(index)) {
          parents.append(oidDescription(parentId.pointee))
        }
      }
    }
    return [
      "success": true,
      "hash": oidDescription(oidCopy),
      "tree": oidDescription(tree),
      "parents": parents,
      "message": git_commit_message(commit).map { String(cString: $0) } ?? "",
      "authorName": author?.pointee.name.map { String(cString: $0) } ?? "Unknown",
      "authorEmail": author?.pointee.email.map { String(cString: $0) } ?? "unknown@example.com",
      "authorTimestampMs": Int((author?.pointee.when.time ?? 0) * 1000),
      "authorTimezone": timezoneString(offsetMinutes: Int(author?.pointee.when.offset ?? 0)),
      "committerName": committer?.pointee.name.map { String(cString: $0) } ?? "Unknown",
      "committerEmail": committer?.pointee.email.map { String(cString: $0) } ?? "unknown@example.com",
      "committerTimestampMs": Int((committer?.pointee.when.time ?? 0) * 1000),
      "committerTimezone": timezoneString(offsetMinutes: Int(committer?.pointee.when.offset ?? 0)),
    ]
  }

  private func createCommitFromIndex(
    repository: OpaquePointer?,
    message: String,
    signature: UnsafeMutablePointer<git_signature>?,
    extraParents: [git_oid]
  ) throws -> git_oid {
    var index: OpaquePointer?
    var treeOid = git_oid()
    var tree: OpaquePointer?
    var headRef: OpaquePointer?
    var headCommit: OpaquePointer?
    var extraParentCommits: [OpaquePointer?] = []
    defer {
      if let index { git_index_free(index) }
      if let tree { git_tree_free(tree) }
      if let headRef { git_reference_free(headRef) }
      if let headCommit { git_commit_free(headCommit) }
      extraParentCommits.forEach {
        if let commit = $0 {
          git_commit_free(commit)
        }
      }
    }

    try check(git_repository_index(&index, repository), "Failed to open index")
    try check(git_index_write_tree(&treeOid, index), "Failed to write tree")
    try check(git_index_write(index), "Failed to write index")
    try check(git_tree_lookup(&tree, repository, &treeOid), "Failed to read tree")

    var parentPointers: [OpaquePointer?] = []
    let headResult = git_repository_head(&headRef, repository)
    if headResult == 0 {
      var headOid = git_reference_target(headRef).pointee
      try check(git_commit_lookup(&headCommit, repository, &headOid), "Object not found: \(oidDescription(headOid))")
      if extraParents.isEmpty,
         let headCommit,
         let headTree = git_commit_tree_id(headCommit),
         git_oid_cmp(headTree, &treeOid) == 0 {
        throw GitBridgeError("No changes staged for commit")
      }
      parentPointers.append(headCommit)
    } else if headResult != GIT_EUNBORNBRANCH.rawValue {
      try check(headResult, "Reference not found: HEAD")
    }

    if !extraParents.isEmpty {
      extraParentCommits.reserveCapacity(extraParents.count)
      for oid in extraParents {
        var parentOid = oid
        var commit: OpaquePointer?
        try check(git_commit_lookup(&commit, repository, &parentOid), "Object not found: \(oidDescription(parentOid))")
        extraParentCommits.append(commit)
        parentPointers.append(commit)
      }
    }

    var oid = git_oid()
    let result = try withGitCString("HEAD") { updateRef in
      try withGitCString(message) { messageCString in
        try parentPointers.withUnsafeMutableBufferPointer { buffer in
          git_commit_create(
            &oid,
            repository,
            updateRef,
            signature.map { UnsafePointer($0) },
            signature.map { UnsafePointer($0) },
            nil,
            messageCString,
            tree,
            buffer.count,
            buffer.baseAddress
          )
        }
      }
    }
    try check(result, "Commit failed")
    return oid
  }

  private func mergeHeadOid(repository: OpaquePointer?) throws -> git_oid {
    guard let repoPath = git_repository_path(repository) else {
      throw GitBridgeError("Pull failed")
    }
    let mergeHeadURL = URL(fileURLWithPath: String(cString: repoPath)).appendingPathComponent("MERGE_HEAD")
    let value = try String(contentsOf: mergeHeadURL, encoding: .utf8)
      .trimmingCharacters(in: .whitespacesAndNewlines)
    if value.isEmpty {
      throw GitBridgeError("Pull failed")
    }
    var oid = git_oid()
    let result = value.withCString { git_oid_fromstr(&oid, $0) }
    try check(result, "Pull failed")
    return oid
  }

  private func cherryPickHeadOid(repository: OpaquePointer?) throws -> git_oid {
    guard let repoPath = git_repository_path(repository) else {
      throw GitBridgeError("No cherry-pick in progress")
    }
    let headURL = URL(fileURLWithPath: String(cString: repoPath)).appendingPathComponent("CHERRY_PICK_HEAD")
    let value = try String(contentsOf: headURL, encoding: .utf8)
      .trimmingCharacters(in: .whitespacesAndNewlines)
    if value.isEmpty {
      throw GitBridgeError("No cherry-pick in progress")
    }
    var oid = git_oid()
    let result = value.withCString { git_oid_fromstr(&oid, $0) }
    try check(result, "No cherry-pick in progress")
    return oid
  }

  private func signatureNow(repository: OpaquePointer?, name: String?, email: String?, output: inout UnsafeMutablePointer<git_signature>?) throws {
    if let name, let email {
      let result = try withGitCString(name) { nameCString in
        try withGitCString(email) { emailCString in
          git_signature_now(&output, nameCString, emailCString)
        }
      }
      try check(result, "Failed to create signature")
      return
    }
    let defaultResult = git_signature_default(&output, repository)
    if defaultResult == 0 {
      return
    }
    let fallbackResult = try withGitCString(name ?? "Unknown") { nameCString in
      try withGitCString(email ?? "unknown@example.com") { emailCString in
        git_signature_now(&output, nameCString, emailCString)
      }
    }
    try check(fallbackResult, "Failed to create signature")
  }

  private func withRepository<T>(path: String, action: (OpaquePointer?) throws -> T) throws -> T {
    var repository: OpaquePointer?
    defer {
      if let repository {
        git_repository_free(repository)
      }
    }
    try withGitCString(path) { pathCString in
      try check(git_repository_open(&repository, pathCString), "Failed to open repository")
    }
    return try action(repository)
  }

  private func normalizeRemoteURL(url: String, auth: GitAuthInfo?) -> String {
    guard let auth, auth.type == "ssh", !auth.username.isEmpty else {
      return url
    }
    if url.hasPrefix("ssh://"), let components = URLComponents(string: url), components.user == nil {
      var updated = components
      updated.user = auth.username
      return updated.string ?? url
    }
    if url.contains("@") {
      return url
    }
    return "\(auth.username)@\(url)"
  }

  private func directoryExistsAndNotEmpty(_ path: String) -> Bool {
    var isDirectory: ObjCBool = false
    guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory), isDirectory.boolValue else {
      return false
    }
    return ((try? FileManager.default.contentsOfDirectory(atPath: path)) ?? []).isEmpty == false
  }

  private func timezoneString(offsetMinutes: Int) -> String {
    let sign = offsetMinutes < 0 ? "-" : "+"
    let absolute = abs(offsetMinutes)
    let hours = absolute / 60
    let minutes = absolute % 60
    return String(format: "%@%02d%02d", sign, hours, minutes)
  }

  private func oidDescription(_ oid: git_oid) -> String {
    var buffer = [CChar](repeating: 0, count: 41)
    var oidCopy = oid
    git_oid_tostr(&buffer, buffer.count, &oidCopy)
    return String(cString: buffer)
  }

  private func check(_ code: Int32, _ fallback: String) throws {
    if code < 0 {
      throw gitError(fallback)
    }
  }

  private func gitError(_ fallback: String) -> GitBridgeError {
    if let error = giterr_last(), let message = error.pointee.message {
      return GitBridgeError(String(cString: message))
    }
    return GitBridgeError(fallback)
  }

  private func requiredString(_ key: String, in arguments: [String: Any]) throws -> String {
    let value = (arguments[key] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    if value.isEmpty {
      throw GitBridgeError("Missing required parameter: \(key)")
    }
    return value
  }
}

private struct PullOutcome {
  let updatedRefs: [String]
}

private struct MergeOutcome {
  let success: Bool
  let conflicts: [String]
  let mergeCommit: String?
}

private struct GitBridgeError: Error {
  let message: String

  init(_ message: String) {
    self.message = message
  }
}

private struct GitAuthInfo {
  let type: String
  let username: String
  let secret: String?
  let privateKeyPem: String?

  init(map: [String: Any]?) {
    self.type = map?["type"] as? String ?? ""
    self.username = map?["username"] as? String ?? ""
    self.secret = map?["secret"] as? String
    self.privateKeyPem = map?["privateKeyPem"] as? String
  }
}

private final class GitOperationContext {
  let auth: GitAuthInfo?
  let remoteName: String

  init(auth: GitAuthInfo?, remoteName: String) {
    self.auth = auth
    self.remoteName = remoteName
  }
}

private func withGitCString<T>(_ string: String, _ body: (UnsafePointer<CChar>) throws -> T) rethrows -> T {
  try string.withCString(body)
}

private func withGitStrarray<T>(_ strings: [String], _ body: (UnsafePointer<git_strarray>) throws -> T) rethrows -> T {
  let duplicates = strings.map { strdup($0) }
  defer {
    duplicates.forEach { free($0) }
  }
  var mutable = duplicates.map { UnsafeMutablePointer<CChar>($0) }
  return try mutable.withUnsafeMutableBufferPointer { buffer in
    var array = git_strarray(strings: buffer.baseAddress, count: strings.count)
    return try body(&array)
  }
}

private func withGitPathspec<T>(_ path: String, _ body: (UnsafePointer<git_strarray>) throws -> T) rethrows -> T {
  let duplicate = strdup(path)
  defer {
    free(duplicate)
  }
  var entries: [UnsafeMutablePointer<CChar>?] = [duplicate]
  return try entries.withUnsafeMutableBufferPointer { buffer in
    var array = git_strarray(strings: buffer.baseAddress, count: 1)
    return try body(&array)
  }
}

private func withGitPathspecs<T>(_ paths: [String], _ body: (UnsafePointer<git_strarray>) throws -> T) rethrows -> T {
  let duplicates = paths.map(strdup)
  defer {
    duplicates.forEach { free($0) }
  }
  var entries = duplicates
  return try entries.withUnsafeMutableBufferPointer { buffer in
    var array = git_strarray(strings: buffer.baseAddress, count: entries.count)
    return try body(&array)
  }
}

private func gitCredentialAcquireCallback(
  _ out: UnsafeMutablePointer<UnsafeMutablePointer<git_cred>?>?,
  _ url: UnsafePointer<CChar>?,
  _ usernameFromUrl: UnsafePointer<CChar>?,
  _ allowedTypes: UInt32,
  _ payload: UnsafeMutableRawPointer?
) -> Int32 {
  guard
    let payload,
    let out
  else {
    return 1
  }
  let context = Unmanaged<GitOperationContext>.fromOpaque(payload).takeUnretainedValue()
  guard let auth = context.auth else {
    return 1
  }
  let allowUserPass = (allowedTypes & UInt32(GIT_CREDTYPE_USERPASS_PLAINTEXT.rawValue)) != 0
  let allowUsername = (allowedTypes & UInt32(GIT_CREDTYPE_USERNAME.rawValue)) != 0
  let allowSshMemory = (allowedTypes & UInt32(GIT_CREDTYPE_SSH_MEMORY.rawValue)) != 0
  let username = !auth.username.isEmpty
    ? auth.username
    : (usernameFromUrl.map { String(cString: $0) } ?? "git")

  if auth.type == "https-basic",
     allowUserPass {
    return username.withCString { usernameCString in
      (auth.secret ?? "").withCString { passwordCString in
        git_cred_userpass_plaintext_new(out, usernameCString, passwordCString)
      }
    }
  }

  if auth.type == "ssh",
     allowUsername,
     usernameFromUrl == nil {
    return username.withCString { usernameCString in
      git_cred_username_new(out, usernameCString)
    }
  }

  if auth.type == "ssh",
     allowSshMemory,
     let privateKeyPem = auth.privateKeyPem {
    return username.withCString { usernameCString in
      privateKeyPem.withCString { privateKeyCString in
        git_cred_ssh_key_memory_new(out, usernameCString, nil, privateKeyCString, nil)
      }
    }
  }

  if auth.type == "ssh",
     allowUsername {
    return username.withCString { usernameCString in
      git_cred_username_new(out, usernameCString)
    }
  }

  return 1
}

private func gitCertificateCheckCallback(
  _ certificate: UnsafeMutablePointer<git_cert>?,
  _ valid: Int32,
  _ host: UnsafePointer<CChar>?,
  _ payload: UnsafeMutableRawPointer?
) -> Int32 {
  0
}

private func gitRemoteCreateCallback(
  _ out: UnsafeMutablePointer<OpaquePointer?>?,
  _ repository: OpaquePointer?,
  _ name: UnsafePointer<CChar>?,
  _ url: UnsafePointer<CChar>?,
  _ payload: UnsafeMutableRawPointer?
) -> Int32 {
  guard
    let out,
    let repository,
    let url,
    let payload
  else {
    return -1
  }
  let context = Unmanaged<GitOperationContext>.fromOpaque(payload).takeUnretainedValue()
  return context.remoteName.withCString { remoteNameCString in
    git_remote_create(out, repository, remoteNameCString, url)
  }
}
