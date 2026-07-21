import AppKit
import Foundation
import UniformTypeIdentifiers

enum MarkdownExportService {
  struct DailyExportInput {
    let day: DailyStandupDayInfo
    let standupDraft: DailyStandupDraft
    let cards: [TimelineCard]
    let observations: [Observation]
    let mobileNotes: [MobileContextNote]
  }

  struct WeeklyExportInput {
    let range: WeeklyDateRange
    let dashboard: WeeklyDashboardSnapshot
    let cards: [TimelineCard]
    let observations: [Observation]
    let recordedMinutes: Int?
    let mobileNotes: [MobileContextNote]
  }

  static func dailyMarkdown(_ input: DailyExportInput) -> String {
    let cards = input.cards.sorted(by: timelineCardSort)
    let observations = input.observations.sorted { $0.startTs < $1.startTs }
    let totals = categoryTotals(from: cards)

    var lines: [String] = []
    appendFrontmatter(
      to: &lines,
      title: "Dayflow Daily \(input.day.dayString)",
      kind: "daily",
      date: input.day.dayString,
      start: input.day.startOfDay,
      end: input.day.endOfDay,
      cardCount: cards.count,
      observationCount: observations.count
    )

    lines.append("# Dayflow Daily - \(input.day.dayString)")
    lines.append("")
    lines.append("Exported: \(displayDateTime(Date()))")
    lines.append("Window: \(displayDateTime(input.day.startOfDay)) - \(displayDateTime(input.day.endOfDay))")
    lines.append("")

    appendStandup(input.standupDraft, to: &lines)
    appendMobileContext(input.mobileNotes, to: &lines)
    appendCategoryTotals(totals, to: &lines)
    appendTimelineCards(cards, to: &lines)
    appendObservations(observations, to: &lines)

    return normalizedMarkdown(lines)
  }

  static func weeklyMarkdown(_ input: WeeklyExportInput) -> String {
    let cards = input.cards.sorted(by: timelineCardSort)
    let observations = input.observations.sorted { $0.startTs < $1.startTs }
    let totals = categoryTotals(from: cards)

    var lines: [String] = []
    appendFrontmatter(
      to: &lines,
      title: "Dayflow Weekly \(input.range.title)",
      kind: "weekly",
      date: DateFormatter.yyyyMMdd.string(from: input.range.weekStart),
      start: input.range.weekStart,
      end: input.range.weekEnd,
      cardCount: cards.count,
      observationCount: observations.count
    )

    lines.append("# Dayflow Weekly - \(input.range.title)")
    lines.append("")
    lines.append("Exported: \(displayDateTime(Date()))")
    lines.append("Window: \(displayDateTime(input.range.weekStart)) - \(displayDateTime(input.range.weekEnd))")
    if let recordedMinutes = input.recordedMinutes {
      lines.append("Tracked time: \(durationText(recordedMinutes))")
    }
    lines.append("")

    appendWeeklySummary(input.dashboard, to: &lines)
    appendMobileContext(input.mobileNotes, to: &lines)
    appendCategoryTotals(totals, to: &lines)
    appendTimelineCards(cards, to: &lines)
    appendObservations(observations, to: &lines)

    return normalizedMarkdown(lines)
  }

  @MainActor
  static func saveMarkdown(markdown: String, defaultFileName: String, panelTitle: String) -> Bool {
    let savePanel = NSSavePanel()
    savePanel.title = panelTitle
    savePanel.prompt = "Export"
    savePanel.nameFieldStringValue = defaultFileName
    savePanel.allowedContentTypes = [UTType(filenameExtension: "md") ?? .plainText]
    savePanel.canCreateDirectories = true

    guard savePanel.runModal() == .OK, let url = savePanel.url else { return false }

    do {
      try markdown.write(to: url, atomically: true, encoding: .utf8)
      return true
    } catch {
      NSSound.beep()
      print("[MarkdownExport] failed to write \(url.path): \(error)")
      return false
    }
  }

  static func dailyFileName(day: String) -> String {
    "dayflow-daily-\(slug(day)).md"
  }

  static func weeklyFileName(range: WeeklyDateRange) -> String {
    "dayflow-weekly-\(slug(range.title)).md"
  }

  private static func appendFrontmatter(
    to lines: inout [String],
    title: String,
    kind: String,
    date: String,
    start: Date,
    end: Date,
    cardCount: Int,
    observationCount: Int
  ) {
    lines.append("---")
    lines.append("title: \"\(yamlEscaped(title))\"")
    lines.append("source: dayflow")
    lines.append("export_kind: \(kind)")
    lines.append("date: \(date)")
    lines.append("window_start: \(isoDateTime(start))")
    lines.append("window_end: \(isoDateTime(end))")
    lines.append("timeline_cards: \(cardCount)")
    lines.append("observations: \(observationCount)")
    lines.append("---")
    lines.append("")
  }

  private static func appendStandup(_ draft: DailyStandupDraft, to lines: inout [String]) {
    lines.append("## Standup")
    lines.append("")
    appendBulletSection(title: cleanTitle(draft.highlightsTitle, fallback: "Highlights"), items: draft.highlights.map(\.text), to: &lines)
    appendBulletSection(title: cleanTitle(draft.tasksTitle, fallback: "Tasks"), items: draft.tasks.map(\.text), to: &lines)
    appendBulletSection(
      title: cleanTitle(draft.blockersTitle, fallback: "Blockers"),
      items: draft.blockersBody.components(separatedBy: .newlines),
      to: &lines
    )
  }

  private static func appendMobileContext(_ notes: [MobileContextNote], to lines: inout [String]) {
    guard !notes.isEmpty else { return }

    lines.append("## Mobile Context")
    lines.append("")
    for note in notes.sorted(by: { $0.modifiedAt < $1.modifiedAt }) {
      lines.append("### \(cleanInline(note.title, fallback: note.url.deletingPathExtension().lastPathComponent))")
      lines.append("")
      lines.append("- Day: \(note.matchedDay)")
      lines.append("- Source: `\(note.url.lastPathComponent)`")
      lines.append("")
      appendParagraph(note.body, fallback: nil, to: &lines)
    }
  }

  private static func appendWeeklySummary(_ dashboard: WeeklyDashboardSnapshot, to lines: inout [String]) {
    lines.append("## Weekly Summary")
    lines.append("")

    if !dashboard.workflow.totals.isEmpty {
      lines.append("### Workflow totals")
      dashboard.workflow.totals.forEach { total in
        lines.append("- \(total.name): \(total.duration)")
      }
      lines.append("")
    }

    if !dashboard.donut.items.isEmpty {
      lines.append("### Distribution")
      dashboard.donut.items.forEach { item in
        lines.append("- \(item.name): \(durationText(item.minutes))")
      }
      lines.append("")
    }
  }

  private static func appendCategoryTotals(_ totals: [(category: String, minutes: Int)], to lines: inout [String]) {
    lines.append("## Category Totals")
    lines.append("")

    if totals.isEmpty {
      lines.append("- No categorized timeline cards found.")
      lines.append("")
      return
    }

    totals.forEach { total in
      lines.append("- \(total.category): \(durationText(total.minutes))")
    }
    lines.append("")
  }

  private static func appendTimelineCards(_ cards: [TimelineCard], to lines: inout [String]) {
    lines.append("## Timeline")
    lines.append("")

    if cards.isEmpty {
      lines.append("No timeline cards found.")
      lines.append("")
      return
    }

    for card in cards {
      let timeRange = [card.startTimestamp, card.endTimestamp]
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
        .joined(separator: " - ")
      let headingTime = timeRange.isEmpty ? card.day : timeRange

      lines.append("### \(headingTime) - \(cleanInline(card.title, fallback: "Untitled activity"))")
      lines.append("")
      lines.append("- Category: \(cleanInline(card.category, fallback: "Uncategorized"))")
      if !card.subcategory.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        lines.append("- Subcategory: \(card.subcategory)")
      }
      if let appSites = appSitesText(card.appSites) {
        lines.append("- Apps/sites: \(appSites)")
      }
      if let videoPath = cleanOptional(card.videoSummaryURL) {
        lines.append("- Video summary: `\(videoPath)`")
      }
      if let otherVideos = card.otherVideoSummaryURLs?.compactMap(cleanOptional), !otherVideos.isEmpty {
        lines.append("- Additional videos: \(otherVideos.map { "`\($0)`" }.joined(separator: ", "))")
      }
      lines.append("")

      appendParagraph(card.summary, fallback: nil, to: &lines)
      appendParagraph(card.detailedSummary, fallback: nil, to: &lines)

      if let distractions = card.distractions, !distractions.isEmpty {
        lines.append("Distractions:")
        distractions.forEach { distraction in
          let label = [distraction.startTime, distraction.endTime]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " - ")
          let prefix = label.isEmpty ? "" : "\(label): "
          lines.append("- \(prefix)\(cleanInline(distraction.title, fallback: "Untitled distraction"))")
          appendIndented(distraction.summary, to: &lines)
        }
        lines.append("")
      }
    }
  }

  private static func appendObservations(_ observations: [Observation], to lines: inout [String]) {
    lines.append("## Observations")
    lines.append("")

    if observations.isEmpty {
      lines.append("No observations found.")
      lines.append("")
      return
    }

    observations.forEach { observation in
      lines.append("### \(displayUnixRange(start: observation.startTs, end: observation.endTs))")
      lines.append("")
      lines.append(observation.observation.trimmingCharacters(in: .whitespacesAndNewlines))
      if let model = cleanOptional(observation.llmModel) {
        lines.append("")
        lines.append("Model: `\(model)`")
      }
      lines.append("")
    }
  }

  private static func appendBulletSection(title: String, items: [String], to lines: inout [String]) {
    lines.append("### \(title)")
    let cleaned = items.compactMap(cleanOptional)
    if cleaned.isEmpty {
      lines.append("- None")
    } else {
      cleaned.forEach { lines.append("- \($0)") }
    }
    lines.append("")
  }

  private static func appendParagraph(_ text: String, fallback: String?, to lines: inout [String]) {
    let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
    if cleaned.isEmpty {
      if let fallback {
        lines.append(fallback)
        lines.append("")
      }
      return
    }
    lines.append(cleaned)
    lines.append("")
  }

  private static func appendIndented(_ text: String, to lines: inout [String]) {
    let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !cleaned.isEmpty else { return }
    lines.append("  - \(cleaned.replacingOccurrences(of: "\n", with: "\n    "))")
  }

  private static func categoryTotals(from cards: [TimelineCard]) -> [(category: String, minutes: Int)] {
    var totals: [String: Int] = [:]
    cards.forEach { card in
      let key = cleanInline(card.category, fallback: "Uncategorized")
      totals[key, default: 0] += max(0, estimatedMinutes(for: card))
    }
    return totals
      .map { (category: $0.key, minutes: $0.value) }
      .sorted {
        if $0.minutes == $1.minutes { return $0.category < $1.category }
        return $0.minutes > $1.minutes
      }
  }

  private static func estimatedMinutes(for card: TimelineCard) -> Int {
    guard
      let start = timelineTimeDate(card.startTimestamp, day: card.day),
      let end = timelineTimeDate(card.endTimestamp, day: card.day)
    else {
      return 0
    }

    let adjustedEnd = end >= start ? end : end.addingTimeInterval(24 * 60 * 60)
    return Int(max(1, (adjustedEnd.timeIntervalSince(start) / 60).rounded()))
  }

  private static func timelineCardSort(_ lhs: TimelineCard, _ rhs: TimelineCard) -> Bool {
    if lhs.day != rhs.day { return lhs.day < rhs.day }
    return lhs.startTimestamp < rhs.startTimestamp
  }

  private static func timelineTimeDate(_ time: String, day: String) -> Date? {
    let cleaned = time.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !cleaned.isEmpty else { return nil }

    for formatter in timelineTimeFormatters {
      if let timeDate = formatter.date(from: cleaned),
        let dayDate = DateFormatter.yyyyMMdd.date(from: day)
      {
        let calendar = Calendar.current
        let timeComponents = calendar.dateComponents([.hour, .minute, .second], from: timeDate)
        return calendar.date(
          bySettingHour: timeComponents.hour ?? 0,
          minute: timeComponents.minute ?? 0,
          second: timeComponents.second ?? 0,
          of: dayDate
        )
      }
    }

    return nil
  }

  private static let timelineTimeFormatters: [DateFormatter] = {
    ["HH:mm:ss", "HH:mm", "h:mm a", "h:mm:ss a"].map { format in
      let formatter = DateFormatter()
      formatter.locale = Locale(identifier: "en_US_POSIX")
      formatter.dateFormat = format
      return formatter
    }
  }()

  private static func appSitesText(_ appSites: AppSites?) -> String? {
    guard let appSites else { return nil }
    let values = [appSites.primary, appSites.secondary].compactMap(cleanOptional)
    return values.isEmpty ? nil : values.joined(separator: ", ")
  }

  private static func cleanTitle(_ text: String, fallback: String) -> String {
    cleanInline(text, fallback: fallback)
  }

  private static func cleanInline(_ text: String, fallback: String) -> String {
    let cleaned = text.trimmingCharacters(in: .whitespacesAndNewlines)
    return cleaned.isEmpty ? fallback : cleaned.replacingOccurrences(of: "\n", with: " ")
  }

  private static func cleanOptional(_ text: String?) -> String? {
    let cleaned = text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    return cleaned.isEmpty ? nil : cleaned
  }

  private static func normalizedMarkdown(_ lines: [String]) -> String {
    lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines) + "\n"
  }

  private static func slug(_ text: String) -> String {
    text
      .lowercased()
      .components(separatedBy: CharacterSet.alphanumerics.inverted)
      .filter { !$0.isEmpty }
      .joined(separator: "-")
  }

  private static func yamlEscaped(_ text: String) -> String {
    text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
  }

  private static func durationText(_ minutes: Int) -> String {
    let safeMinutes = max(0, minutes)
    let hours = safeMinutes / 60
    let remainingMinutes = safeMinutes % 60

    if hours == 0 {
      return "\(remainingMinutes)m"
    }
    if remainingMinutes == 0 {
      return "\(hours)h"
    }
    return "\(hours)h \(remainingMinutes)m"
  }

  private static func isoDateTime(_ date: Date) -> String {
    isoFormatter.string(from: date)
  }

  private static func displayDateTime(_ date: Date) -> String {
    displayFormatter.string(from: date)
  }

  private static func displayUnixRange(start: Int, end: Int) -> String {
    let startDate = Date(timeIntervalSince1970: TimeInterval(start))
    let endDate = Date(timeIntervalSince1970: TimeInterval(end))
    return "\(displayFormatter.string(from: startDate)) - \(displayFormatter.string(from: endDate))"
  }

  private static let isoFormatter: ISO8601DateFormatter = {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withDashSeparatorInDate, .withColonSeparatorInTime]
    return formatter
  }()

  private static let displayFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateFormat = "MMM d, yyyy h:mm a"
    return formatter
  }()
}
