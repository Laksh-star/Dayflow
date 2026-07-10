import Foundation

struct ProjectTaggingRule: Identifiable, Equatable, Sendable {
  let id: String
  let project: String
  let patterns: [String]
}

struct ProjectTimeRollup: Identifiable, Equatable, Sendable {
  let project: String
  let minutes: Int
  let cardCount: Int

  var id: String { project }
}

struct ProjectRuleSuggestion: Identifiable, Equatable, Sendable {
  let pattern: String
  let source: String
  let cardTitle: String
  let minutes: Int

  var id: String { pattern }
}

enum ProjectTaggingService {
  private static let rulesKey = "projectTaggingRulesText"

  static var rulesText: String {
    get {
      UserDefaults.standard.string(forKey: rulesKey)
        ?? """
        Dayflow=dayflow,teleportlabs
        Coding=xcode,cursor,github,git,swift
        Meetings=zoom,teams,meet,calendar
        """
    }
    set {
      UserDefaults.standard.set(newValue, forKey: rulesKey)
    }
  }

  static func rules(from text: String = rulesText) -> [ProjectTaggingRule] {
    text
      .components(separatedBy: .newlines)
      .compactMap { line -> ProjectTaggingRule? in
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { return nil }

        let parts = trimmed.split(separator: "=", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return nil }

        let project = parts[0].trimmingCharacters(in: .whitespacesAndNewlines)
        let patterns = parts[1]
          .split(separator: ",")
          .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
          .filter { !$0.isEmpty }

        guard !project.isEmpty, !patterns.isEmpty else { return nil }
        return ProjectTaggingRule(
          id: project.lowercased(),
          project: project,
          patterns: patterns
        )
      }
  }

  static func project(for card: TimelineCard, rules: [ProjectTaggingRule] = rules()) -> String? {
    let searchable = searchableText(for: card)
    guard !searchable.isEmpty else { return nil }

    return rules.first { rule in
      rule.patterns.contains { searchable.contains($0) }
    }?.project
  }

  static func tags(for card: TimelineCard, rules: [ProjectTaggingRule] = rules()) -> [String] {
    var tags: [String] = []
    if let project = project(for: card, rules: rules) {
      tags.append(project)
    }

    let category = card.category.trimmingCharacters(in: .whitespacesAndNewlines)
    if !category.isEmpty {
      tags.append(category)
    }
    return tags
  }

  static func rollups(for cards: [TimelineCard], rules: [ProjectTaggingRule] = rules())
    -> [ProjectTimeRollup]
  {
    var totals: [String: (minutes: Int, cardCount: Int)] = [:]

    for card in cards {
      let project = project(for: card, rules: rules) ?? "Untagged"
      let minutes = max(1, durationMinutes(for: card) ?? 0)
      var current = totals[project, default: (0, 0)]
      current.minutes += minutes
      current.cardCount += 1
      totals[project] = current
    }

    return totals.map { key, value in
      ProjectTimeRollup(project: key, minutes: value.minutes, cardCount: value.cardCount)
    }
    .sorted {
      if $0.minutes != $1.minutes { return $0.minutes > $1.minutes }
      return $0.project.localizedCaseInsensitiveCompare($1.project) == .orderedAscending
    }
  }

  static func untaggedSuggestions(
    for cards: [TimelineCard],
    rules: [ProjectTaggingRule] = rules(),
    limit: Int = 8
  ) -> [ProjectRuleSuggestion] {
    let taggedPatterns = Set(rules.flatMap(\.patterns))
    var scores: [String: (source: String, title: String, minutes: Int)] = [:]

    for card in cards where project(for: card, rules: rules) == nil {
      let minutes = max(1, durationMinutes(for: card) ?? 0)
      for (pattern, source) in suggestionPatterns(for: card) {
        guard !taggedPatterns.contains(pattern) else { continue }
        var current = scores[pattern] ?? (source, card.title, 0)
        current.minutes += minutes
        scores[pattern] = current
      }
    }

    return scores.map { pattern, value in
      ProjectRuleSuggestion(
        pattern: pattern,
        source: value.source,
        cardTitle: value.title,
        minutes: value.minutes
      )
    }
    .sorted {
      if $0.minutes != $1.minutes { return $0.minutes > $1.minutes }
      return $0.pattern.localizedCaseInsensitiveCompare($1.pattern) == .orderedAscending
    }
    .prefix(limit)
    .map { $0 }
  }

  static func durationMinutes(for card: TimelineCard) -> Int? {
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

    return max(0, Int(end.timeIntervalSince(start) / 60))
  }

  private static func searchableText(for card: TimelineCard) -> String {
    [
      card.title,
      card.summary,
      card.detailedSummary,
      card.category,
      card.subcategory,
      card.appSites?.primary,
      card.appSites?.secondary,
    ]
    .compactMap { $0 }
    .joined(separator: " ")
    .lowercased()
  }

  private static func suggestionPatterns(for card: TimelineCard) -> [(String, String)] {
    var candidates: [(String, String)] = []
    if let primary = normalizedPattern(card.appSites?.primary) {
      candidates.append((primary, "Primary app/site"))
    }
    if let secondary = normalizedPattern(card.appSites?.secondary), secondary != candidates.first?.0 {
      candidates.append((secondary, "Secondary app/site"))
    }

    for token in [card.title, card.category, card.subcategory] {
      if let normalized = normalizedPattern(token), normalized.count >= 4 {
        candidates.append((normalized, "Card text"))
      }
    }

    var seen = Set<String>()
    return candidates.filter { candidate in
      seen.insert(candidate.0).inserted
    }
  }

  private static func normalizedPattern(_ value: String?) -> String? {
    guard var normalized = value?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
      !normalized.isEmpty
    else { return nil }
    normalized = normalized
      .replacingOccurrences(of: "https://", with: "")
      .replacingOccurrences(of: "http://", with: "")
    if let slashIndex = normalized.firstIndex(of: "/") {
      normalized = String(normalized[..<slashIndex])
    }
    let trimmed = normalized.trimmingCharacters(
      in: CharacterSet.alphanumerics.inverted
    )
    return trimmed.isEmpty ? nil : trimmed
  }

  private static let timeFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateFormat = "h:mm a"
    formatter.locale = Locale(identifier: "en_US_POSIX")
    return formatter
  }()
}
