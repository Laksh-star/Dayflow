import Foundation

struct TogglProject: Codable, Equatable, Identifiable, Sendable {
  let id: Int64
  let name: String
  let clientName: String?

  enum CodingKeys: String, CodingKey {
    case id
    case name
    case clientName = "client_name"
  }
}

struct TogglExportDraftEntry: Identifiable, Equatable, Sendable {
  let id: String
  let cardRecordId: Int64?
  let sourceTitle: String
  let sourceProject: String
  let start: Date
  let end: Date
  let durationMinutes: Int
  var isIncluded: Bool
  var description: String
  var togglProjectId: Int64?
}

enum TogglExportSettings {
  private static let apiTokenProvider = "toggl"
  private static let workspaceIDKey = "togglWorkspaceID"

  static var workspaceID: String {
    get {
      UserDefaults.standard.string(forKey: workspaceIDKey) ?? ""
    }
    set {
      UserDefaults.standard.set(
        newValue.trimmingCharacters(in: .whitespacesAndNewlines),
        forKey: workspaceIDKey
      )
    }
  }

  static func loadAPIToken() -> String {
    KeychainManager.shared.retrieve(for: apiTokenProvider) ?? ""
  }

  @discardableResult
  static func saveAPIToken(_ token: String) -> Bool {
    let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.isEmpty {
      return KeychainManager.shared.delete(for: apiTokenProvider)
    }
    return KeychainManager.shared.store(trimmed, for: apiTokenProvider)
  }
}

enum TogglExportService {
  enum TogglExportError: LocalizedError {
    case missingToken
    case missingWorkspace
    case invalidWorkspace
    case httpError(Int, String)

    var errorDescription: String? {
      switch self {
      case .missingToken:
        return "Add a Toggl API token before loading projects or submitting entries."
      case .missingWorkspace:
        return "Add a Toggl workspace ID before loading projects or submitting entries."
      case .invalidWorkspace:
        return "The Toggl workspace ID must be a number."
      case .httpError(let status, let body):
        return "Toggl returned HTTP \(status): \(body)"
      }
    }
  }

  static func fetchProjects(apiToken: String, workspaceID: String) async throws -> [TogglProject] {
    let workspace = try normalizedWorkspaceID(workspaceID)
    let url = URL(string: "https://api.track.toggl.com/api/v9/workspaces/\(workspace)/projects")!
    var request = URLRequest(url: url)
    request.httpMethod = "GET"
    request.setValue(authorizationHeader(apiToken: apiToken), forHTTPHeaderField: "Authorization")

    let (data, response) = try await URLSession.shared.data(for: request)
    try validate(response: response, data: data)

    return try JSONDecoder().decode([TogglProject].self, from: data)
      .sorted {
        $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
      }
  }

  static func createTimeEntry(
    apiToken: String,
    workspaceID: String,
    entry: TogglExportDraftEntry
  ) async throws {
    let workspace = try normalizedWorkspaceID(workspaceID)
    let url = URL(string: "https://api.track.toggl.com/api/v9/workspaces/\(workspace)/time_entries")!

    var payload: [String: Any] = [
      "created_with": "Dayflow Dev",
      "description": entry.description,
      "duration": max(60, Int(entry.end.timeIntervalSince(entry.start))),
      "start": isoFormatter.string(from: entry.start),
      "stop": isoFormatter.string(from: entry.end),
      "workspace_id": workspace,
    ]
    if let togglProjectId = entry.togglProjectId {
      payload["project_id"] = togglProjectId
    }

    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.setValue(authorizationHeader(apiToken: apiToken), forHTTPHeaderField: "Authorization")
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = try JSONSerialization.data(withJSONObject: payload, options: [])

    let (data, response) = try await URLSession.shared.data(for: request)
    try validate(response: response, data: data)
  }

  static func draftEntries(
    from cards: [TimelineCard],
    projects: [TogglProject],
    rules: [ProjectTaggingRule] = ProjectTaggingService.rules()
  ) -> [TogglExportDraftEntry] {
    cards.compactMap { card in
      guard let interval = cardInterval(card) else { return nil }
      let sourceProject = ProjectTaggingService.project(for: card, rules: rules) ?? "Untagged"
      let projectID = matchingProjectID(sourceProject: sourceProject, projects: projects)
      let minutes = max(1, Int(interval.end.timeIntervalSince(interval.start) / 60))
      let description = sourceProject == "Untagged" ? card.title : "\(sourceProject): \(card.title)"

      return TogglExportDraftEntry(
        id: "\(card.day)-\(card.recordId ?? 0)-\(card.startTimestamp)-\(card.endTimestamp)-\(card.title)",
        cardRecordId: card.recordId,
        sourceTitle: card.title,
        sourceProject: sourceProject,
        start: interval.start,
        end: interval.end,
        durationMinutes: minutes,
        isIncluded: true,
        description: description,
        togglProjectId: projectID
      )
    }
  }

  private static func normalizedWorkspaceID(_ value: String) throws -> Int64 {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { throw TogglExportError.missingWorkspace }
    guard let workspace = Int64(trimmed) else { throw TogglExportError.invalidWorkspace }
    return workspace
  }

  private static func authorizationHeader(apiToken: String) -> String {
    let token = apiToken.trimmingCharacters(in: .whitespacesAndNewlines)
    let credentials = "\(token):api_token"
    let encoded = Data(credentials.utf8).base64EncodedString()
    return "Basic \(encoded)"
  }

  private static func validate(response: URLResponse, data: Data) throws {
    guard let http = response as? HTTPURLResponse else { return }
    guard (200...299).contains(http.statusCode) else {
      let body = String(data: data, encoding: .utf8) ?? ""
      throw TogglExportError.httpError(http.statusCode, body)
    }
  }

  private static func matchingProjectID(sourceProject: String, projects: [TogglProject]) -> Int64? {
    let normalizedSource = sourceProject.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    guard !normalizedSource.isEmpty, normalizedSource != "untagged" else { return nil }

    if let exact = projects.first(where: {
      $0.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == normalizedSource
    }) {
      return exact.id
    }

    return projects.first {
      $0.name.localizedCaseInsensitiveContains(sourceProject)
        || sourceProject.localizedCaseInsensitiveContains($0.name)
    }?.id
  }

  private static func cardInterval(_ card: TimelineCard) -> (start: Date, end: Date)? {
    guard
      let dayDate = DateFormatter.yyyyMMdd.date(from: card.day),
      let startTime = timeFormatter.date(from: card.startTimestamp),
      let endTime = timeFormatter.date(from: card.endTimestamp)
    else {
      return nil
    }

    let calendar = Calendar.current
    let startComponents = calendar.dateComponents([.hour, .minute], from: startTime)
    let endComponents = calendar.dateComponents([.hour, .minute], from: endTime)
    guard
      var start = calendar.date(
        bySettingHour: startComponents.hour ?? 0,
        minute: startComponents.minute ?? 0,
        second: 0,
        of: dayDate
      ),
      var end = calendar.date(
        bySettingHour: endComponents.hour ?? 0,
        minute: endComponents.minute ?? 0,
        second: 0,
        of: dayDate
      )
    else {
      return nil
    }

    if calendar.component(.hour, from: start) < 4 {
      start = calendar.date(byAdding: .day, value: 1, to: start) ?? start
    }
    if calendar.component(.hour, from: end) < 4 {
      end = calendar.date(byAdding: .day, value: 1, to: end) ?? end
    }
    if end < start {
      end = calendar.date(byAdding: .day, value: 1, to: end) ?? end
    }
    return (start, end)
  }

  private static let timeFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateFormat = "h:mm a"
    formatter.locale = Locale(identifier: "en_US_POSIX")
    return formatter
  }()

  private static let isoFormatter: ISO8601DateFormatter = {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter
  }()
}
