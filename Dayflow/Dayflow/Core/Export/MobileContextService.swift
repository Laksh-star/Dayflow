import Foundation

struct MobileContextNote: Equatable, Identifiable, Sendable {
  let id: String
  let url: URL
  let title: String
  let body: String
  let modifiedAt: Date
  let matchedDay: String
}

enum MobileContextSettings {
  private static let folderPathKey = "mobileContextInboxFolderPath"
  private static let includeInExportsKey = "mobileContextIncludeInExports"
  private static let includeInDailyKey = "mobileContextIncludeInDaily"

  static var defaultInboxURL: URL {
    FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent("Library/Mobile Documents/com~apple~CloudDocs/Dayflow/Mobile Inbox", isDirectory: true)
  }

  static var inboxFolderPath: String {
    get {
      let saved = UserDefaults.standard.string(forKey: folderPathKey)?
        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
      return saved.isEmpty ? defaultInboxURL.path : saved
    }
    set {
      UserDefaults.standard.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines), forKey: folderPathKey)
    }
  }

  static var includeInExports: Bool {
    get { UserDefaults.standard.object(forKey: includeInExportsKey) as? Bool ?? true }
    set { UserDefaults.standard.set(newValue, forKey: includeInExportsKey) }
  }

  static var includeInDaily: Bool {
    get { UserDefaults.standard.object(forKey: includeInDailyKey) as? Bool ?? true }
    set { UserDefaults.standard.set(newValue, forKey: includeInDailyKey) }
  }
}

enum MobileContextService {
  static func ensureInboxFolderExists() -> Bool {
    let url = URL(fileURLWithPath: MobileContextSettings.inboxFolderPath, isDirectory: true)
    do {
      try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
      return true
    } catch {
      print("[MobileContext] failed to create inbox folder \(url.path): \(error)")
      return false
    }
  }

  static func notes(from start: Date, through end: Date) -> [MobileContextNote] {
    let calendar = Calendar.current
    let startDay = calendar.startOfDay(for: start)
    let endDay = calendar.startOfDay(for: end)

    var matchedNotes: [MobileContextNote] = []
    var cursor = startDay
    while cursor <= endDay {
      let dayString = DateFormatter.yyyyMMdd.string(from: cursor)
      matchedNotes.append(contentsOf: notes(forDay: dayString, dayStart: cursor))
      guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
      cursor = next
    }

    return matchedNotes.sorted {
      if $0.matchedDay == $1.matchedDay {
        return $0.modifiedAt < $1.modifiedAt
      }
      return $0.matchedDay < $1.matchedDay
    }
  }

  static func notes(forDay dayString: String) -> [MobileContextNote] {
    guard let day = DateFormatter.yyyyMMdd.date(from: dayString) else { return [] }
    return notes(forDay: dayString, dayStart: Calendar.current.startOfDay(for: day))
  }

  static func makeNotesText(day: String, notes: [MobileContextNote]) -> String {
    guard !notes.isEmpty else {
      return "No mobile context notes were imported for \(day)."
    }

    var lines: [String] = ["Mobile context notes for \(day):", ""]
    for (index, note) in notes.enumerated() {
      lines.append("\(index + 1). \(note.title)")
      let body = note.body.trimmingCharacters(in: .whitespacesAndNewlines)
      if !body.isEmpty {
        lines.append(indent(body, prefix: "   "))
      }
    }
    return lines.joined(separator: "\n")
  }

  private static func notes(forDay dayString: String, dayStart: Date) -> [MobileContextNote] {
    let folderURL = URL(fileURLWithPath: MobileContextSettings.inboxFolderPath, isDirectory: true)
    let fileManager = FileManager.default
    guard
      let urls = try? fileManager.contentsOfDirectory(
        at: folderURL,
        includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
        options: [.skipsHiddenFiles]
      )
    else {
      return []
    }

    let calendar = Calendar.current
    let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart

    return urls.compactMap { url in
      guard isSupportedNote(url) else { return nil }
      let modifiedAt = modificationDate(for: url) ?? .distantPast
      let filenameMatches = url.lastPathComponent.contains(dayString)
      let modifiedMatches = modifiedAt >= dayStart && modifiedAt < dayEnd
      guard filenameMatches || modifiedMatches else { return nil }
      guard let content = try? String(contentsOf: url, encoding: .utf8) else { return nil }
      let body = content.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !body.isEmpty else { return nil }

      let title = titleFromContent(body) ?? url.deletingPathExtension().lastPathComponent
      return MobileContextNote(
        id: url.path,
        url: url,
        title: title,
        body: body,
        modifiedAt: modifiedAt,
        matchedDay: dayString
      )
    }
  }

  private static func isSupportedNote(_ url: URL) -> Bool {
    let ext = url.pathExtension.lowercased()
    return ext == "md" || ext == "markdown" || ext == "txt"
  }

  private static func modificationDate(for url: URL) -> Date? {
    (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
  }

  private static func titleFromContent(_ content: String) -> String? {
    content
      .components(separatedBy: .newlines)
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .first { !$0.isEmpty }?
      .trimmingCharacters(in: CharacterSet(charactersIn: "# "))
      .nilIfBlank
  }

  private static func indent(_ value: String, prefix: String) -> String {
    value
      .components(separatedBy: .newlines)
      .map { prefix + $0 }
      .joined(separator: "\n")
  }
}

private extension String {
  var nilIfBlank: String? {
    let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
  }
}
