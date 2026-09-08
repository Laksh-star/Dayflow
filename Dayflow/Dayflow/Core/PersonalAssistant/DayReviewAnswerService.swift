import Foundation

enum DayReviewPrompt: CaseIterable, Identifiable, Hashable {
  case finished
  case remaining
  case next

  var id: Self { self }

  var title: String {
    switch self {
    case .finished: return "What did I finish?"
    case .remaining: return "What remains?"
    case .next: return "What should I do next?"
    }
  }

  var question: String {
    switch self {
    case .finished:
      return "What did I finish today? Separate completed tasks from recorded desktop work and manual captures."
    case .remaining:
      return "What remains unfinished today? List only open tasks and any work that is recorded but not linked to a completed task."
    case .next:
      return "What should I do next? Recommend one concrete next step from the open tasks and today's evidence. Explain the evidence briefly, or say that there is not enough evidence to choose."
    }
  }
}

struct DayReviewAnswerService {
  enum Error: LocalizedError {
    case unavailable
    case invalidResponse
    case requestFailed(Int)

    var errorDescription: String? {
      switch self {
      case .unavailable:
        return "A direct OpenAI provider and API key are required for a provider-backed review."
      case .invalidResponse:
        return "The review provider returned an unreadable response."
      case .requestFailed(let status):
        return "The review provider request failed (HTTP \(status))."
      }
    }
  }

  func answer(question: String, day: String, cards: [TimelineCard], tasks: [DayflowTask], captures: [ManualCapture]) async throws -> String {
    guard let configuration = OpenAICompatiblePreferences.load(),
      isDirectOpenAI(configuration),
      let endpoint = configuration.chatCompletionsURL,
      let key = KeychainManager.shared.retrieve(for: OpenAICompatiblePreferences.keychainProvider)?
        .trimmingCharacters(in: .whitespacesAndNewlines),
      !key.isEmpty
    else { throw Error.unavailable }

    let context = makeContext(day: day, cards: cards, tasks: tasks, captures: captures)
    let messages = [
      Message(role: "system", content: "You are Dayflow's day-review assistant. Answer only from the supplied day evidence. Be concise, distinguish recorded desktop activity from manual captures and tasks, and say when evidence is missing. Never claim a task was completed unless the task status says done or the user explicitly recorded it. For a next-step question, recommend at most one open task and explain the supporting evidence in one sentence. Do not give generic productivity advice."),
      Message(role: "user", content: "Day evidence:\n\(context)\n\nQuestion: \(question)"),
    ]
    let payload = Request(model: configuration.modelID, messages: messages, temperature: 0.2)
    var request = URLRequest(url: endpoint)
    request.httpMethod = "POST"
    request.timeoutInterval = 35
    request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.httpBody = try JSONEncoder().encode(payload)

    let session = URLSession(configuration: .ephemeral)
    let (data, response) = try await session.data(for: request)
    guard let http = response as? HTTPURLResponse else { throw Error.invalidResponse }
    guard (200...299).contains(http.statusCode) else { throw Error.requestFailed(http.statusCode) }
    guard let answer = try? JSONDecoder().decode(Response.self, from: data).choices.first?.message.content
      .trimmingCharacters(in: .whitespacesAndNewlines), !answer.isEmpty
    else { throw Error.invalidResponse }
    return answer
  }

  static func localAnswer(question: String, cards: [TimelineCard], tasks: [DayflowTask], captures: [ManualCapture]) -> String {
    let normalized = question.lowercased()
    if normalized.contains("finish") || normalized.contains("complete") {
      let completed = tasks.filter { $0.status == .done }.map(\.title)
      let desktop = cards.prefix(3).map(\.title)
      let captureCount = captures.count
      var sections: [String] = []
      sections.append(completed.isEmpty ? "No tasks are marked done." : "Marked done: \(completed.joined(separator: ", ")).")
      if desktop.isEmpty {
        sections.append("No desktop activity was recorded.")
      } else {
        sections.append("Recorded desktop work: \(desktop.joined(separator: "; ")).")
      }
      if captureCount > 0 { sections.append("Manual captures: \(captureCount).") }
      return sections.joined(separator: " ")
    }

    let openTasks = tasks.filter { $0.status != .done && $0.status != .dropped }
    if normalized.contains("next") || normalized.contains("resume") {
      guard let task = recommendedTask(from: openTasks, cards: cards, captures: captures) else {
        return "There is no open task with enough same-day evidence to recommend a next step."
      }
      let evidence = evidenceSummary(for: task, cards: cards, captures: captures)
      return "Next: \(task.title). \(evidence)"
    }

    if normalized.contains("unfinished") || normalized.contains("remain") || normalized.contains("task") {
      guard !openTasks.isEmpty else { return "There are no unfinished tasks for this day." }
      return "Still open: \(openTasks.map(\.title).joined(separator: ", "))."
    }

    if normalized.contains("capture") || normalized.contains("offline") {
      return captures.isEmpty ? "There are no manual captures for this day." : "Manual captures: \(captures.map(\.body).joined(separator: "; "))."
    }

    let titles = cards.prefix(4).map(\.title)
    return titles.isEmpty ? "There are no processed desktop cards for this day yet." : "Dayflow recorded \(cards.count) desktop activity cards. The main threads were: \(titles.joined(separator: "; "))."
  }

  static func recommendedTask(from tasks: [DayflowTask], cards: [TimelineCard], captures: [ManualCapture]) -> DayflowTask? {
    tasks.max { lhs, rhs in
      evidenceScore(for: lhs, cards: cards, captures: captures) < evidenceScore(for: rhs, cards: cards, captures: captures)
    }.flatMap { task in
      evidenceScore(for: task, cards: cards, captures: captures) > 0 ? task : nil
    }
  }

  private static func evidenceSummary(for task: DayflowTask, cards: [TimelineCard], captures: [ManualCapture]) -> String {
    let score = evidenceScore(for: task, cards: cards, captures: captures)
    guard score > 0 else { return "No matching activity was recorded today." }
    return "Dayflow found matching activity today; confirm the task before marking it done."
  }

  private static func evidenceScore(for task: DayflowTask, cards: [TimelineCard], captures: [ManualCapture]) -> Int {
    let words = Set(task.title.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }).filter { $0.count > 3 })
    guard !words.isEmpty else { return 0 }
    let cardMatches = cards.filter { card in
      let text = "\(card.title) \(card.summary)".lowercased()
      return words.contains { text.contains($0) }
    }.count
    let captureMatches = captures.filter { capture in
      let text = capture.body.lowercased()
      return words.contains { text.contains($0) }
    }.count
    return cardMatches + captureMatches
  }

  private func isDirectOpenAI(_ configuration: OpenAICompatibleConfiguration) -> Bool {
    URLComponents(string: configuration.baseURL)?.host?.lowercased() == "api.openai.com"
  }

  private func makeContext(day: String, cards: [TimelineCard], tasks: [DayflowTask], captures: [ManualCapture]) -> String {
    let cardLines = cards.map { "- desktop [\($0.startTimestamp)-\($0.endTimestamp)] \($0.category): \($0.title)" }
    let taskLines = tasks.map { "- task [\($0.status.label)]: \($0.title)" }
    let captureLines = captures.map { capture in
      let range = (capture.startTs.flatMap { start in capture.endTs.map { " [\(start)-\($0)]" } }) ?? ""
      return "- manual \(capture.kind.label)\(range): \(capture.body)"
    }
    var lines = ["Day: \(day)", "Desktop cards:"]
    lines.append(contentsOf: cardLines.isEmpty ? ["- none"] : cardLines)
    lines.append("Tasks:")
    lines.append(contentsOf: taskLines.isEmpty ? ["- none"] : taskLines)
    lines.append("Manual captures:")
    lines.append(contentsOf: captureLines.isEmpty ? ["- none"] : captureLines)
    return lines.joined(separator: "\n")
  }

  private struct Message: Codable { let role: String; let content: String }
  private struct Request: Codable { let model: String; let messages: [Message]; let temperature: Double }
  private struct Response: Decodable {
    struct Choice: Decodable { struct Message: Decodable { let content: String }; let message: Message }
    let choices: [Choice]
  }
}
