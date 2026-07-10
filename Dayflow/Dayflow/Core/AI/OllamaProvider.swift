//
//  OllamaProvider.swift
//  Dayflow
//

import AppKit
import Foundation

final class OllamaProvider {
  struct RuntimeConfiguration {
    let providerName: String
    let modelId: String
    let apiKey: String?
    let additionalHeaders: [String: String]
    let usesMaxCompletionTokens: Bool

    static func openAICompatible(
      modelId: String, apiKey: String?, baseURL: String
    ) -> RuntimeConfiguration {
      let trimmedKey = apiKey?.trimmingCharacters(in: .whitespacesAndNewlines)
      return RuntimeConfiguration(
        providerName: OpenAICompatibleProviderSettings.providerID,
        modelId: modelId,
        apiKey: trimmedKey?.isEmpty == false ? trimmedKey : nil,
        additionalHeaders: OpenAICompatibleProviderSettings.authorizationHeaders(apiKey: apiKey),
        usesMaxCompletionTokens: OpenAICompatibleProviderSettings.usesMaxCompletionTokens(
          modelId: modelId,
          baseURL: baseURL
        )
      )
    }
  }

  let endpoint: String
  private let runtimeConfiguration: RuntimeConfiguration?
  let screenshotInterval: TimeInterval = 10  // seconds between screenshots
  // Read persisted local settings
  var savedModelId: String {
    if let runtimeConfiguration {
      return runtimeConfiguration.modelId
    }
    if let m = UserDefaults.standard.string(forKey: "llmLocalModelId"), !m.isEmpty {
      return m
    }
    // Fallback to a sensible default
    let engine: LocalEngine = isLMStudio ? .lmstudio : .ollama
    return LocalModelPreferences.defaultModelId(for: engine)
  }
  var isLMStudio: Bool {
    (UserDefaults.standard.string(forKey: "llmLocalEngine") ?? "ollama") == "lmstudio"
  }
  var isCustomEngine: Bool {
    (UserDefaults.standard.string(forKey: "llmLocalEngine") ?? "ollama") == "custom"
  }
  var customAPIKey: String? {
    if let runtimeConfiguration {
      return runtimeConfiguration.apiKey
    }
    let trimmed =
      UserDefaults.standard.string(forKey: "llmLocalAPIKey")?.trimmingCharacters(
        in: .whitespacesAndNewlines) ?? ""
    return trimmed.isEmpty ? nil : trimmed
  }

  // Get the actual local engine type for analytics tracking
  var localEngine: String {
    if let runtimeConfiguration {
      return runtimeConfiguration.providerName
    }
    return UserDefaults.standard.string(forKey: "llmLocalEngine") ?? "ollama"
  }

  var authorizationHeaderValue: String? {
    if isLMStudio {
      return "Bearer lm-studio"
    }
    if isCustomEngine, let token = customAPIKey {
      return "Bearer \(token)"
    }
    return nil
  }

  var additionalHeaders: [String: String] {
    if let runtimeConfiguration {
      return runtimeConfiguration.additionalHeaders
    }
    guard let authorizationHeaderValue else { return [:] }
    return ["Authorization": authorizationHeaderValue]
  }

  var usesMaxCompletionTokens: Bool {
    runtimeConfiguration?.usesMaxCompletionTokens ?? false
  }

  init(endpoint: String = "http://localhost:1234", runtimeConfiguration: RuntimeConfiguration? = nil) {
    self.endpoint = endpoint
    self.runtimeConfiguration = runtimeConfiguration
  }

  // Strip user references from observations to prevent LLM from using third-person language
  // For some reason, even after adding negative prompts during observation generation,
  // it still generates text with "a user" and "the user", which poisons the context
  // for the summary prompt and makes it more likely to write in 3rd person.
  // TODO: Remove this when observation generation is fixed upstream
  func stripUserReferences(_ text: String) -> String {
    return
      text
      .replacingOccurrences(of: "The user", with: "", options: .caseInsensitive)
      .replacingOccurrences(of: "A user", with: "", options: .caseInsensitive)
  }

  func logCallDuration(operation: String, duration: TimeInterval, status: Int? = nil) {
    let statusText = status.map { " status=\($0)" } ?? ""
    print("⏱️ [\(localEngine)] \(operation) \(String(format: "%.2f", duration))s\(statusText)")
  }

  func generateActivityCards(
    observations: [Observation], context: ActivityGenerationContext, batchId: Int64?
  ) async throws -> (cards: [ActivityCardData], log: LLMCall) {
    enum CardGenerationError: LocalizedError {
      case empty(rawOutput: String)
      case validationFailed(details: String, rawOutput: String)

      var errorDescription: String? {
        switch self {
        case .empty(let rawOutput):
          return "No cards returned.\n\nRaw output:\n\(rawOutput)"
        case .validationFailed(let details, let rawOutput):
          return "\(details)\n\nRaw output:\n\(rawOutput)"
        }
      }
    }

    let callStart = Date()
    let sortedObservations = observations.sorted { $0.startTs < $1.startTs }

    guard !sortedObservations.isEmpty else {
      throw NSError(
        domain: "OllamaProvider",
        code: 16,
        userInfo: [
          NSLocalizedDescriptionKey: "Cannot generate activity cards: no observations provided"
        ]
      )
    }

    let basePrompt = buildMultiCardPrompt(observations: sortedObservations, context: context)
    var prompt = basePrompt
    var lastError: Error?
    var lastRawOutput = ""

    for attempt in 1...3 {
      do {
        let response = try await callTextAPI(
          prompt,
          operation: "generate_activity_cards",
          expectJSON: true,
          batchId: batchId,
          maxRetries: 1,
          maxTokens: 6000
        )
        lastRawOutput = response

        let parsedCards = try parseActivityCardsResponse(response)
        guard !parsedCards.isEmpty else {
          throw CardGenerationError.empty(rawOutput: response)
        }

        let normalizedCards = parsedCards.map { card in
          ActivityCardData(
            startTime: card.startTime,
            endTime: card.endTime,
            category: normalizeCategory(card.category, categories: context.categories),
            subcategory: card.subcategory,
            title: card.title,
            summary: card.summary,
            detailedSummary: card.detailedSummary.isEmpty ? card.summary : card.detailedSummary,
            distractions: card.distractions,
            appSites: card.appSites
          )
        }

        let validationErrors = validateGeneratedCards(
          normalizedCards,
          observations: sortedObservations,
          existingCards: context.existingCards
        )
        guard validationErrors.isEmpty else {
          let details = validationErrors.joined(separator: "\n\n")
          throw CardGenerationError.validationFailed(details: details, rawOutput: response)
        }

        let totalLatency = Date().timeIntervalSince(callStart)
        let combinedLog = LLMCall(
          timestamp: callStart,
          latency: totalLatency,
          input: prompt,
          output: response
        )

        return (normalizedCards, combinedLog)
      } catch {
        lastError = error
        if attempt == 3 { break }

        print(
          "[OLLAMA] ⚠️ generate_activity_cards attempt \(attempt) failed: \(error.localizedDescription)"
        )

        prompt =
          basePrompt + """


          PREVIOUS ATTEMPT FAILED — \(error.localizedDescription)

          Return the full corrected JSON array. Keep the same overall time coverage, avoid gaps and overlaps, merge short middle cards into adjacent cards, and output JSON only.
          """
      }
    }

    throw lastError
      ?? CardGenerationError.validationFailed(
        details: "Failed to generate valid activity cards",
        rawOutput: lastRawOutput
      )
  }

  private func normalizeCategory(_ raw: String, categories: [LLMCategoryDescriptor]) -> String {
    let cleaned = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !cleaned.isEmpty else { return categories.first?.name ?? "" }
    let normalized = cleaned.lowercased()
    if let match = categories.first(where: {
      $0.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == normalized
    }) {
      return match.name
    }
    if let idle = categories.first(where: { $0.isIdle }) {
      let idleLabels = [
        "idle", "idle time", idle.name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
      ]
      if idleLabels.contains(normalized) {
        return idle.name
      }
    }
    return categories.first?.name ?? cleaned
  }

  func parseJSONResponse<T: Codable>(_ type: T.Type, from data: Data) throws -> T {
    // First try direct parsing
    do {
      return try JSONDecoder().decode(type, from: data)
    } catch {
      // Try to extract JSON from the response
      guard let responseString = String(data: data, encoding: .utf8) else {
        throw error
      }

      // Look for JSON object
      if let startIndex = responseString.firstIndex(of: "{"),
        let endIndex = responseString.lastIndex(of: "}")
      {
        let jsonSubstring = responseString[startIndex...endIndex]
        if let jsonData = jsonSubstring.data(using: .utf8) {
          return try JSONDecoder().decode(type, from: jsonData)
        }
      }

      throw error
    }
  }

  func formatTimestampForPrompt(_ timestamp: Int) -> String {
    let date = Date(timeIntervalSince1970: TimeInterval(timestamp))
    let formatter = DateFormatter()
    formatter.dateFormat = "h:mm a"
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone.current
    return formatter.string(from: date)
  }

  private func calculateDurationInMinutes(from startTime: String, to endTime: String) -> Int {
    let formatter = DateFormatter()
    formatter.dateFormat = "h:mm a"
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone.current

    guard let start = formatter.date(from: startTime),
      let end = formatter.date(from: endTime)
    else {
      return 0
    }

    var duration = end.timeIntervalSince(start)

    // Handle day boundary - if end is before start, assume it's the next day
    if duration < 0 {
      duration += 24 * 60 * 60  // Add 24 hours in seconds
    }

    return Int(duration / 60)
  }

  private func buildMultiCardPrompt(
    observations: [Observation], context: ActivityGenerationContext
  ) -> String {
    let transcriptText = observations.map { obs in
      let startTime = formatTimestampForPrompt(obs.startTs)
      let endTime = formatTimestampForPrompt(obs.endTs)
      return "[\(startTime) - \(endTime)]: \(stripUserReferences(obs.observation))"
    }.joined(separator: "\n")

    let encoder = JSONEncoder()
    encoder.outputFormatting = .prettyPrinted
    let existingCardsData = try? encoder.encode(context.existingCards)
    let existingCardsJSON = existingCardsData.flatMap { String(data: $0, encoding: .utf8) } ?? "[]"

    let categoryLines = context.categories.map { descriptor in
      let description = descriptor.description?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
      let suffix = description.isEmpty ? "" : " — \(description)"
      return "- \"\(descriptor.name)\"\(suffix)"
    }.joined(separator: "\n")
    let categoriesSection = categoryLines.isEmpty ? "- \"Work\"" : categoryLines
    let languageBlock =
      LLMOutputLanguagePreferences.languageInstruction(forJSON: true)
      .map { "\n\n\($0)" } ?? ""

    return """
      You are synthesizing a user's computer activity log into timeline cards. Each card represents one main thing they did.

      CORE PRINCIPLE:
      Each card = one coherent activity. Time is a constraint, not the goal.

      CARD BOUNDARIES:
      - Minimum card length: 10 minutes.
      - Maximum card length: 60 minutes.
      - The final card may be shorter if the input window ends.
      - Brief interruptions under 5 minutes that do not change focus belong in the card's distractions.

      WHEN TO SPLIT:
      - The user's goal changes, not merely the app or website.
      - A sustained unrelated activity lasts about 10+ minutes.
      - A natural title would need "and" to connect unrelated things.

      WHEN TO MERGE:
      - Consecutive observations serve the same project or goal.
      - Tool switches support the same task.
      - Brief unrelated checks are distractions, not new cards.

      BIAS:
      Prefer fewer rich cards over many tiny cards. Merge if the user would describe the period as one sitting or session.

      CONTINUITY:
      Do not invent gaps or overlaps. Adjacent cards should meet cleanly unless the source data has a real gap.

      TITLES:
      - 5-10 words, natural and specific.
      - Prefer proper nouns, apps, repos, people, documents, or concrete topics.
      - Avoid vague titles like "Worked on tasks" or "Various activities".
      - Do not use the words: various, multiple, browsing, activity, activities.

      SUMMARIES:
      - Two sentences max.
      - First-person perspective without using "I".
      - Name the concrete tools/topics once each.
      - No bullet points or laundry lists.

      DETAILED SUMMARY:
      - 2-4 concise sentences with enough detail to remember what happened.
      - Preserve concrete names from the observations.

      DISTRACTIONS:
      A distraction is a brief unrelated interruption under 5 minutes.
      Sustained social, video, gaming, email, or shopping periods should be separate cards.

      CATEGORIES:
      Choose exactly one category per card:
      \(categoriesSection)

      APP SITES:
      Identify the main app or website for each card.
      - Use canonical domains where possible: chatgpt.com, claude.ai, github.com, docs.google.com, x.com.
      - For native apps without a domain, use a stable lowercase name such as terminal, xcode, cursor.
      - Do not invent brands.

      INPUT/OUTPUT CONTRACT:
      Your output cards must cover the same total time range as the previous cards plus the new observations.
      Think of previous cards as a draft you may revise, merge, split, or extend.

      Previous cards:
      \(existingCardsJSON)

      New observations:
      \(transcriptText)

      \(languageBlock)

      Return ONLY a raw JSON array. No code fences, no markdown, no commentary.

      [
        {
          "startTime": "1:12 AM",
          "endTime": "1:30 AM",
          "category": "",
          "subcategory": "",
          "title": "",
          "summary": "",
          "detailedSummary": "",
          "distractions": [
            {
              "startTime": "1:15 AM",
              "endTime": "1:18 AM",
              "title": "",
              "summary": ""
            }
          ],
          "appSites": {
            "primary": "",
            "secondary": ""
          }
        }
      ]
      """
  }

  private struct CardsEnvelope: Codable {
    let cards: [ActivityCardData]
  }

  private func parseActivityCardsResponse(_ response: String) throws -> [ActivityCardData] {
    guard let data = response.data(using: .utf8) else {
      throw NSError(
        domain: "OllamaProvider",
        code: 17,
        userInfo: [NSLocalizedDescriptionKey: "Failed to parse activity cards response"])
    }

    let decoder = JSONDecoder()
    if let cards = try? decoder.decode([ActivityCardData].self, from: data) {
      return cards
    }
    if let envelope = try? decoder.decode(CardsEnvelope.self, from: data) {
      return envelope.cards
    }

    let trimmed = response.trimmingCharacters(in: .whitespacesAndNewlines)
    if let start = trimmed.firstIndex(of: "["),
      let end = trimmed.lastIndex(of: "]"),
      start < end
    {
      let slice = trimmed[start...end]
      if let slicedData = String(slice).data(using: .utf8),
        let cards = try? decoder.decode([ActivityCardData].self, from: slicedData)
      {
        return cards
      }
    }

    if let start = trimmed.firstIndex(of: "{"),
      let end = trimmed.lastIndex(of: "}"),
      start < end
    {
      let slice = trimmed[start...end]
      if let slicedData = String(slice).data(using: .utf8),
        let envelope = try? decoder.decode(CardsEnvelope.self, from: slicedData)
      {
        return envelope.cards
      }
    }

    throw NSError(
      domain: "OllamaProvider",
      code: 17,
      userInfo: [NSLocalizedDescriptionKey: "Failed to decode activity cards JSON"])
  }

  private func validateGeneratedCards(
    _ cards: [ActivityCardData],
    observations: [Observation],
    existingCards: [ActivityCardData]
  ) -> [String] {
    var errors: [String] = []

    if cards.isEmpty {
      return ["No cards were returned."]
    }

    for (index, card) in cards.enumerated() {
      let duration = durationMinutes(startTime: card.startTime, endTime: card.endTime)
      if duration <= 0 {
        errors.append("Card \(index + 1) has invalid time range: \(card.startTime) - \(card.endTime).")
      }
      if duration < 10 && index < cards.count - 1 {
        errors.append(
          "Card \(index + 1) '\(card.title)' is only \(String(format: "%.1f", duration)) minutes; merge short middle cards."
        )
      }
      if duration > 65 {
        errors.append(
          "Card \(index + 1) '\(card.title)' is \(String(format: "%.1f", duration)) minutes; split cards longer than 60 minutes."
        )
      }
    }

    let cardRanges = cards.map {
      TimeRange(start: timeToMinutes($0.startTime), end: adjustedEndMinutes($0.endTime, after: $0.startTime))
    }.sorted { $0.start < $1.start }

    for pair in zip(cardRanges, cardRanges.dropFirst()) {
      if pair.1.start < pair.0.end - 1 {
        errors.append("Cards overlap around \(minutesToTimeString(pair.1.start)).")
      }
    }

    let requiredRanges = requiredCoverageRanges(observations: observations, existingCards: existingCards)
    let coverageErrors = missingCoverageDescriptions(requiredRanges: requiredRanges, outputRanges: cardRanges)
    errors.append(contentsOf: coverageErrors)

    return errors
  }

  private struct TimeRange {
    let start: Double
    let end: Double
  }

  private func requiredCoverageRanges(
    observations: [Observation],
    existingCards: [ActivityCardData]
  ) -> [TimeRange] {
    var ranges: [TimeRange] = []

    for card in existingCards {
      let start = timeToMinutes(card.startTime)
      ranges.append(TimeRange(start: start, end: adjustedEndMinutes(card.endTime, after: card.startTime)))
    }

    for observation in observations {
      let start = timeToMinutes(formatTimestampForPrompt(observation.startTs))
      let end = timeToMinutes(formatTimestampForPrompt(observation.endTs))
      ranges.append(TimeRange(start: start, end: end < start ? end + 24 * 60 : end))
    }

    return mergeTimeRanges(ranges)
  }

  private func missingCoverageDescriptions(
    requiredRanges: [TimeRange],
    outputRanges: [TimeRange]
  ) -> [String] {
    let output = mergeTimeRanges(outputRanges)
    let flexibility = 3.0
    var errors: [String] = []

    for required in requiredRanges {
      var cursor = required.start
      while cursor < required.end {
        if let covering = output.first(where: {
          $0.start - flexibility <= cursor && cursor <= $0.end + flexibility
        }) {
          cursor = max(cursor + 0.01, covering.end)
          continue
        }

        let nextStart = output
          .filter { $0.start > cursor }
          .map(\.start)
          .min() ?? required.end
        let missingEnd = min(nextStart, required.end)
        if missingEnd - cursor > flexibility {
          errors.append(
            "Missing coverage for \(minutesToTimeString(cursor)) - \(minutesToTimeString(missingEnd))."
          )
        }
        cursor = max(cursor + 0.01, missingEnd)
      }
    }

    return errors
  }

  private func mergeTimeRanges(_ ranges: [TimeRange]) -> [TimeRange] {
    guard !ranges.isEmpty else { return [] }
    let sorted = ranges.sorted { $0.start < $1.start }
    var merged: [TimeRange] = []

    for range in sorted {
      guard range.end > range.start else { continue }
      if let last = merged.last, range.start <= last.end + 1 {
        _ = merged.popLast()
        merged.append(TimeRange(start: last.start, end: max(last.end, range.end)))
      } else {
        merged.append(range)
      }
    }

    return merged
  }

  private func durationMinutes(startTime: String, endTime: String) -> Double {
    let start = timeToMinutes(startTime)
    let end = adjustedEndMinutes(endTime, after: startTime)
    return end - start
  }

  private func adjustedEndMinutes(_ endTime: String, after startTime: String) -> Double {
    let start = timeToMinutes(startTime)
    var end = timeToMinutes(endTime)
    if end < start { end += 24 * 60 }
    return end
  }

  private func timeToMinutes(_ timeStr: String) -> Double {
    let trimmed = timeStr.trimmingCharacters(in: .whitespacesAndNewlines)
    let formatter = DateFormatter()
    formatter.dateFormat = "h:mm a"
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone.current

    guard let date = formatter.date(from: trimmed) else { return 0 }
    let components = Calendar.current.dateComponents([.hour, .minute], from: date)
    return Double((components.hour ?? 0) * 60 + (components.minute ?? 0))
  }

  private func minutesToTimeString(_ minutes: Double) -> String {
    let normalized = Int(minutes.rounded()) % (24 * 60)
    let hours = normalized / 60
    let mins = normalized % 60
    let suffix = hours >= 12 ? "PM" : "AM"
    let displayHour = hours % 12 == 0 ? 12 : hours % 12
    return "\(displayHour):\(String(format: "%02d", mins)) \(suffix)"
  }
}
