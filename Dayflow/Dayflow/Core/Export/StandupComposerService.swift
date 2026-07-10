import Foundation

enum StandupComposerService {
  static func compose(
    yesterdayCards: [TimelineCard],
    todayCards: [TimelineCard],
    projectRules: [ProjectTaggingRule] = ProjectTaggingService.rules()
  ) -> String {
    var lines: [String] = []
    lines.append("Yesterday")
    appendStandupBullets(from: yesterdayCards, rules: projectRules, to: &lines)
    lines.append("")
    lines.append("Today")
    appendStandupBullets(from: todayCards, rules: projectRules, to: &lines)
    lines.append("")
    lines.append("Blockers")
    appendBlockers(from: yesterdayCards + todayCards, to: &lines)
    return lines.joined(separator: "\n")
  }

  private static func appendStandupBullets(
    from cards: [TimelineCard],
    rules: [ProjectTaggingRule],
    to lines: inout [String]
  ) {
    let filtered = cards
      .filter { $0.category.lowercased() != "system" && $0.title != "Processing failed" }
      .sorted(by: sortCards)

    guard !filtered.isEmpty else {
      lines.append("- No captured activity.")
      return
    }

    let projectGroups = Dictionary(grouping: filtered) {
      ProjectTaggingService.project(for: $0, rules: rules) ?? "Untagged"
    }

    for project in projectGroups.keys.sorted() {
      guard let groupCards = projectGroups[project] else { continue }
      let titles = groupCards.prefix(3).map { clean($0.title) }.filter { !$0.isEmpty }
      let minutes = ProjectTaggingService.rollups(for: groupCards, rules: rules)
        .first(where: { $0.project == project || project == "Untagged" })?.minutes
        ?? groupCards.compactMap(ProjectTaggingService.durationMinutes).reduce(0, +)
      let timePrefix = minutes > 0 ? "\(durationText(minutes)) - " : ""
      lines.append("- \(timePrefix)\(project): \(titles.joined(separator: "; "))")
    }
  }

  private static func appendBlockers(from cards: [TimelineCard], to lines: inout [String]) {
    let blockers = cards.filter { card in
      let text = [card.title, card.summary, card.detailedSummary]
        .joined(separator: " ")
        .lowercased()
      return text.contains("blocked")
        || text.contains("blocker")
        || text.contains("failed")
        || text.contains("waiting")
    }

    guard !blockers.isEmpty else {
      lines.append("- None captured.")
      return
    }

    blockers.prefix(5).forEach { card in
      lines.append("- \(clean(card.title))")
    }
  }

  private static func sortCards(_ lhs: TimelineCard, _ rhs: TimelineCard) -> Bool {
    if lhs.day != rhs.day { return lhs.day < rhs.day }
    return lhs.startTimestamp < rhs.startTimestamp
  }

  private static func clean(_ value: String) -> String {
    value.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private static func durationText(_ minutes: Int) -> String {
    if minutes < 60 { return "\(minutes)m" }
    let hours = minutes / 60
    let remainder = minutes % 60
    return remainder == 0 ? "\(hours)h" : "\(hours)h \(remainder)m"
  }
}
