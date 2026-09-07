import Foundation

struct MobileCaptureInboxService {
  static let folderPathDefaultsKey = "personalAssistantMobileInboxFolderPath"

  func importCaptures(storageManager: StorageManaging) -> MobileCaptureInboxResult {
    guard let path = UserDefaults.standard.string(forKey: Self.folderPathDefaultsKey), !path.isEmpty else {
      return MobileCaptureInboxResult(imported: 0, skipped: 0, errors: ["Choose a mobile inbox folder first."])
    }
    let folder = URL(fileURLWithPath: path, isDirectory: true)
    guard let files = try? FileManager.default.contentsOfDirectory(
      at: folder, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles])
    else { return MobileCaptureInboxResult(imported: 0, skipped: 0, errors: ["The selected mobile inbox folder is unavailable."]) }

    var imported = 0
    var skipped = 0
    var errors: [String] = []
    for file in files where file.pathExtension.lowercased() == "json" {
      let sourcePath = file.standardizedFileURL.path
      if storageManager.hasImportedMobileCapture(sourcePath: sourcePath) {
        skipped += 1
        continue
      }
      do {
        let payload = try JSONDecoder().decode(Payload.self, from: Data(contentsOf: file))
        let capture = try payload.makeCapture(now: Int(Date().timeIntervalSince1970))
        storageManager.saveManualCapture(capture)
        storageManager.recordMobileCaptureImport(sourcePath: sourcePath, importedAt: Int(Date().timeIntervalSince1970))
        imported += 1
      } catch {
        errors.append("\(file.lastPathComponent): \(error.localizedDescription)")
      }
    }
    return MobileCaptureInboxResult(imported: imported, skipped: skipped, errors: errors)
  }

  private struct Payload: Decodable {
    let body: String
    let kind: String?
    let start: String?
    let end: String?
    let day: String?
    let taskID: String?
    let categoryID: String?
    let projectName: String?

    func makeCapture(now: Int) throws -> ManualCapture {
      let trimmedBody = body.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !trimmedBody.isEmpty else { throw InboxError.emptyBody }
      let formatter = ISO8601DateFormatter()
      let startDate = start.flatMap(formatter.date(from:))
      let endDate = end.flatMap(formatter.date(from:))
      guard endDate == nil || startDate == nil || endDate! > startDate! else { throw InboxError.invalidRange }
      let resolvedDay = day ?? DateFormatter.yyyyMMdd.string(from: startDate ?? Date())
      let resolvedKind = kind.flatMap(ManualCaptureKind.init(rawValue:)) ?? .note
      return ManualCapture(
        id: UUID(), day: resolvedDay, body: trimmedBody, kind: resolvedKind,
        startTs: startDate.map { Int($0.timeIntervalSince1970) }, endTs: endDate.map { Int($0.timeIntervalSince1970) },
        categoryID: categoryID, projectName: projectName, taskID: taskID.flatMap(UUID.init(uuidString:)),
        source: .mobileShortcut, sourcePayload: nil, createdAt: now, updatedAt: now
      )
    }
  }

  private enum InboxError: LocalizedError {
    case emptyBody
    case invalidRange
    var errorDescription: String? { self == .emptyBody ? "body is required" : "end must be after start" }
  }
}
