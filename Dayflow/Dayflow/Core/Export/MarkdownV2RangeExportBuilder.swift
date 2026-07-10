import Foundation

enum MarkdownV2RangeExportBuilder {
  static func makeMarkdown(start: Date, end: Date, cardsByDay: [(day: Date, cards: [TimelineCard])])
    -> String
  {
    let allCards = cardsByDay.flatMap(\.cards)
    let rules = ProjectTaggingService.rules()
    let rollups = ProjectTaggingService.rollups(for: allCards, rules: rules)
    let startDay = DateFormatter.yyyyMMdd.string(from: start)
    let endDay = DateFormatter.yyyyMMdd.string(from: end)

    var lines: [String] = []
    lines.append("---")
    lines.append("title: \"Dayflow timeline \(startDay) to \(endDay)\"")
    lines.append("source: dayflow")
    lines.append("export_kind: timeline_range")
    lines.append("export_version: 2")
    lines.append("start_date: \(startDay)")
    lines.append("end_date: \(endDay)")
    lines.append("card_count: \(allCards.count)")
    lines.append("suggested_folder: dayflow/\(startDay)-to-\(endDay)")
    lines.append("---")
    lines.append("")
    lines.append("# Dayflow timeline")
    lines.append("")
    lines.append("Range: \(startDay) to \(endDay)")
    lines.append("")

    appendProjectRollups(rollups, to: &lines)
    appendWeeklyRollupIfNeeded(cardsByDay: cardsByDay, rules: rules, to: &lines)

    lines.append("## Daily timeline")
    lines.append("")
    for entry in cardsByDay {
      appendDay(entry.day, cards: entry.cards, rules: rules, to: &lines)
    }

    return lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines) + "\n"
  }

  private static func appendProjectRollups(_ rollups: [ProjectTimeRollup], to lines: inout [String]) {
    lines.append("## Project rollup")
    lines.append("")
    guard !rollups.isEmpty else {
      lines.append("- No tagged project time found.")
      lines.append("")
      return
    }

    for rollup in rollups {
      lines.append("- #\(tagSlug(rollup.project)) \(rollup.project): \(durationText(rollup.minutes)) across \(rollup.cardCount) card\(rollup.cardCount == 1 ? "" : "s")")
    }
    lines.append("")
  }

  private static func appendWeeklyRollupIfNeeded(
    cardsByDay: [(day: Date, cards: [TimelineCard])],
    rules: [ProjectTaggingRule],
    to lines: inout [String]
  ) {
    guard cardsByDay.count >= 5 else { return }

    let allCards = cardsByDay.flatMap(\.cards)
    let categoryGroups = Dictionary(grouping: allCards) { $0.category }
    lines.append("## Weekly rollup")
    lines.append("")
    lines.append("### Categories")
    for category in categoryGroups.keys.sorted() {
      let cards = categoryGroups[category] ?? []
      let minutes = cards.compactMap(ProjectTaggingService.durationMinutes).reduce(0, +)
      lines.append("- \(category): \(durationText(minutes))")
    }
    lines.append("")

    let projectRollups = ProjectTaggingService.rollups(for: allCards, rules: rules)
    if !projectRollups.isEmpty {
      lines.append("### Projects")
      for rollup in projectRollups.prefix(10) {
        lines.append("- \(rollup.project): \(durationText(rollup.minutes))")
      }
      lines.append("")
    }
  }

  private static func appendDay(
    _ day: Date,
    cards: [TimelineCard],
    rules: [ProjectTaggingRule],
    to lines: inout [String]
  ) {
    let dayString = DateFormatter.yyyyMMdd.string(from: day)
    lines.append("### \(dayString)")
    lines.append("")

    guard !cards.isEmpty else {
      lines.append("_No timeline activities were recorded for this day._")
      lines.append("")
      return
    }

    for card in cards.sorted(by: cardSort) {
      let title = clean(card.title, fallback: "Untitled activity")
      let timeRange = [card.startTimestamp, card.endTimestamp]
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
        .joined(separator: " - ")
      lines.append("#### \(timeRange.isEmpty ? title : "\(timeRange) - \(title)")")
      lines.append("")

      let tags = ProjectTaggingService.tags(for: card, rules: rules)
      if !tags.isEmpty {
        lines.append("Tags: \(tags.map { "#\(tagSlug($0))" }.joined(separator: " "))")
      }
      lines.append("- Category: \(clean(card.category, fallback: "Uncategorized"))")
      if let project = ProjectTaggingService.project(for: card, rules: rules) {
        lines.append("- Project: \(project)")
      }
      if let appSites = appSitesText(card.appSites) {
        lines.append("- Apps/sites: \(appSites)")
      }
      if let video = optional(card.videoSummaryURL) {
        lines.append("- Timelapse: `\(video)`")
      }
      lines.append("")

      if let summary = optional(card.summary) {
        lines.append(summary)
        lines.append("")
      }
      if let details = optional(card.detailedSummary), details != optional(card.summary) {
        lines.append(details)
        lines.append("")
      }
    }
  }

  private static func appSitesText(_ appSites: AppSites?) -> String? {
    guard let appSites else { return nil }
    return [appSites.primary, appSites.secondary]
      .compactMap(optional)
      .joined(separator: ", ")
      .nilIfEmpty
  }

  private static func cardSort(_ lhs: TimelineCard, _ rhs: TimelineCard) -> Bool {
    if lhs.day != rhs.day { return lhs.day < rhs.day }
    return lhs.startTimestamp < rhs.startTimestamp
  }

  private static func optional(_ value: String?) -> String? {
    let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    return trimmed.isEmpty ? nil : trimmed
  }

  private static func clean(_ value: String, fallback: String) -> String {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? fallback : trimmed
  }

  private static func tagSlug(_ value: String) -> String {
    value
      .lowercased()
      .replacingOccurrences(of: " ", with: "-")
      .filter { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }
  }

  private static func durationText(_ minutes: Int) -> String {
    if minutes < 60 { return "\(minutes)m" }
    let hours = minutes / 60
    let remainder = minutes % 60
    return remainder == 0 ? "\(hours)h" : "\(hours)h \(remainder)m"
  }
}

private extension String {
  var nilIfEmpty: String? {
    isEmpty ? nil : self
  }
}
