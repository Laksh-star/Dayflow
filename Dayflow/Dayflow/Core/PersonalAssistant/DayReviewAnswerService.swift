import Foundation

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
      Message(role: "system", content: "You are Dayflow's day-review assistant. Answer only from the supplied day evidence. Be concise, distinguish recorded desktop activity from manual captures and tasks, and say when evidence is missing. Never claim a task was completed unless the task status says done or the user explicitly recorded it."),
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
