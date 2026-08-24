import Foundation

struct DayShapeArchive: Codable, Equatable, Sendable {
  static let algorithmVersion = 3

  let algorithmVersion: Int
  let day: String
  let generatedAt: Int
  let sourceFingerprint: String
  let totalMinutes: Int
  let points: [DayShapePoint]
  let threads: [DayShapeThread]
  let focusWindows: [DayShapeFocusWindow]
}

struct DayShapePoint: Codable, Identifiable, Equatable, Sendable {
  let id: String
  let cardID: Int64?
  let startMinute: Int
  let endMinute: Int
  let durationMinutes: Int
  let title: String
  let threadID: String
  let constellationX: Double
  let constellationY: Double
}

struct DayShapeThread: Codable, Identifiable, Equatable, Sendable {
  let id: String
  let label: String
  let colorHex: String
  let totalMinutes: Int
  let cardCount: Int
}

struct DayShapeFocusWindow: Codable, Identifiable, Equatable, Sendable {
  let id: String
  let startMinute: Int
  let endMinute: Int
}

enum DayShapeService {
  private struct SourceItem {
    let card: TimelineCard
    let startMinute: Int
    let endMinute: Int
    let durationMinutes: Int
    let topicLabel: String
  }

  private static let palette = ["7388F5", "C38665", "61C3C5", "A68DC7", "8B8B9D", "D49A72"]
  private static let maxThreads = 6
  private static let timelineDayStart = 4 * 60

  static func archive(for day: String, storageManager: StorageManaging) -> DayShapeArchive? {
    let cards = storageManager.fetchTimelineCards(forDay: day)
    let plan = storageManager.fetchDayGoalPlan(forDay: day)
    let sourceFingerprint = fingerprint(for: cards, plan: plan)
    let archiveURL = jsonURL(for: day)

    if let existing = loadArchive(at: archiveURL),
      existing.algorithmVersion == DayShapeArchive.algorithmVersion,
      existing.sourceFingerprint == sourceFingerprint
    {
      return existing
    }

    guard let archive = buildArchive(day: day, cards: cards, plan: plan, sourceFingerprint: sourceFingerprint) else {
      removeArchive(for: day)
      return nil
    }

    save(archive)
    return archive
  }

  static func archiveRecentCompletedDays(storageManager: StorageManaging, count: Int = 7, now: Date = Date()) {
    guard count > 0 else { return }
    let calendar = Calendar.current
    let today = timelineDisplayDate(from: now)

    for offset in 1...count {
      guard let date = calendar.date(byAdding: .day, value: -offset, to: today) else { continue }
      let day = DateFormatter.yyyyMMdd.string(from: date)
      _ = archive(for: day, storageManager: storageManager)
    }
  }

  static func archiveDirectoryURL() -> URL {
    let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    return appSupport.appendingPathComponent("DayflowDev/day-shapes", isDirectory: true)
  }

  private static func buildArchive(
    day: String,
    cards: [TimelineCard],
    plan: DayGoalPlan?,
    sourceFingerprint: String
  ) -> DayShapeArchive? {
    let sourceItems = cards.compactMap(makeSourceItem).sorted { lhs, rhs in
      if lhs.startMinute == rhs.startMinute { return lhs.endMinute < rhs.endMinute }
      return lhs.startMinute < rhs.startMinute
    }
    guard sourceItems.isEmpty == false else { return nil }

    let grouped = Dictionary(grouping: sourceItems, by: \.topicLabel)
    let rankedTopics = grouped
      .map { label, items in
        (label: label, totalMinutes: items.reduce(0) { $0 + $1.durationMinutes }, count: items.count)
      }
      .sorted {
        if $0.totalMinutes == $1.totalMinutes { return $0.label < $1.label }
        return $0.totalMinutes > $1.totalMinutes
      }

    let retainedTopics = Set(rankedTopics.prefix(maxThreads).map(\.label))
    let normalizedTopics = sourceItems.map { item in
      retainedTopics.contains(item.topicLabel) ? item.topicLabel : "Other work"
    }
    let orderedTopics = Array(Set(normalizedTopics)).sorted { lhs, rhs in
      let lhsMinutes = sourceItems.enumerated().reduce(0) { total, item in
        total + (normalizedTopics[item.offset] == lhs ? item.element.durationMinutes : 0)
      }
      let rhsMinutes = sourceItems.enumerated().reduce(0) { total, item in
        total + (normalizedTopics[item.offset] == rhs ? item.element.durationMinutes : 0)
      }
      if lhsMinutes == rhsMinutes { return lhs < rhs }
      return lhsMinutes > rhsMinutes
    }
    let topicIndex = Dictionary(uniqueKeysWithValues: orderedTopics.enumerated().map { ($1, $0) })

    let threads = orderedTopics.enumerated().map { index, label in
      let members = sourceItems.enumerated().filter { normalizedTopics[$0.offset] == label }.map(\.element)
      return DayShapeThread(
        id: threadID(for: label),
        label: label,
        colorHex: palette[index % palette.count],
        totalMinutes: members.reduce(0) { $0 + $1.durationMinutes },
        cardCount: members.count
      )
    }
    let threadByLabel = Dictionary(uniqueKeysWithValues: threads.map { ($0.label, $0) })

    let points = sourceItems.enumerated().compactMap { index, item -> DayShapePoint? in
      let label = normalizedTopics[index]
      guard let thread = threadByLabel[label], let lane = topicIndex[label] else { return nil }
      let midpoint = Double(item.startMinute + item.endMinute) / 2
      let x = 0.08 + min(max(midpoint / 1_440, 0), 1) * 0.84
      let baseY = Double(lane + 1) / Double(max(orderedTopics.count + 1, 2))
      let wobble = sin(Double(index + 1) * 1.73 + Double(stableHash(label) % 17)) * 0.08
      let durationLift = min(Double(item.durationMinutes) / 240, 0.05)
      let y = min(max(baseY + wobble - durationLift, 0.12), 0.88)
      let id = "\(item.card.recordId ?? Int64(index))-\(item.startMinute)-\(item.endMinute)"
      return DayShapePoint(
        id: id,
        cardID: item.card.recordId,
        startMinute: item.startMinute,
        endMinute: item.endMinute,
        durationMinutes: item.durationMinutes,
        title: item.card.title,
        threadID: thread.id,
        constellationX: x,
        constellationY: y
      )
    }

    let focusWindows = (plan?.focusWindows ?? [])
      .filter(\.isValid)
      .map { DayShapeFocusWindow(id: $0.id, startMinute: $0.startMinutes, endMinute: $0.endMinutes) }

    return DayShapeArchive(
      algorithmVersion: DayShapeArchive.algorithmVersion,
      day: day,
      generatedAt: Int(Date().timeIntervalSince1970),
      sourceFingerprint: sourceFingerprint,
      totalMinutes: sourceItems.reduce(0) { $0 + $1.durationMinutes },
      points: points,
      threads: threads,
      focusWindows: focusWindows
    )
  }

  private static func makeSourceItem(_ card: TimelineCard) -> SourceItem? {
    guard card.category.trimmingCharacters(in: .whitespacesAndNewlines).caseInsensitiveCompare("System") != .orderedSame,
      let startMinute = timelineMinute(from: card.startTimestamp),
      let rawEndMinute = timelineMinute(from: card.endTimestamp)
    else { return nil }

    let endMinute = rawEndMinute >= startMinute ? rawEndMinute : rawEndMinute + (24 * 60)
    guard endMinute > startMinute else { return nil }
    return SourceItem(
      card: card,
      startMinute: min(max(startMinute, 0), 24 * 60),
      endMinute: min(max(endMinute, 0), 24 * 60),
      durationMinutes: max(1, endMinute - startMinute),
      topicLabel: inferredTopic(for: card)
    )
  }

  private static func inferredTopic(for card: TimelineCard) -> String {
    let appSites = [card.appSites?.primary, card.appSites?.secondary]
      .compactMap { $0 }
      .joined(separator: " ")
    let text = [card.title, card.summary, card.detailedSummary, appSites]
      .joined(separator: " ")
      .lowercased()

    let rules: [(String, [String])] = [
      ("Finance & tax", ["tax", "pension", "annuity", "icici", "payout", "e-filing"]),
      ("Flow & video", ["google flow", "flow", "youtube", "video", "storyboard", "voiceover"]),
      ("X Trend & agents", ["x trend", "x.com", "twitter", "agent", "codex", "dayflow", "toggl"]),
      ("Research", ["research", "deepseek", "gemini", "paper", "analysis", "reading"]),
      ("Communication", ["gmail", "email", "slack", "teams", "whatsapp", "meeting"]),
    ]

    if let match = rules.first(where: { _, keywords in keywords.contains(where: text.contains) }) {
      return match.0
    }
    if card.category.trimmingCharacters(in: .whitespacesAndNewlines).caseInsensitiveCompare("Personal") == .orderedSame {
      return "Personal"
    }
    if let app = card.appSites?.primary?.trimmingCharacters(in: .whitespacesAndNewlines), app.isEmpty == false {
      return displayAppName(app)
    }
    return "Other work"
  }

  private static func displayAppName(_ app: String) -> String {
    app.replacingOccurrences(of: "www.", with: "")
      .split(separator: ".")
      .first
      .map { $0.capitalized }
      ?? "Other work"
  }

  private static func timelineMinute(from time: String) -> Int? {
    let trimmed = time.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    let parts = trimmed.split(separator: " ")
    guard parts.count >= 2 else { return nil }
    let clock = parts[0].split(separator: ":")
    guard clock.count == 2, let rawHour = Int(clock[0]), let minute = Int(clock[1]) else { return nil }
    let isPM = parts[1] == "PM"
    var hour = rawHour % 12
    if isPM { hour += 12 }
    let minutes = (hour * 60) + minute
    return minutes >= timelineDayStart ? minutes - timelineDayStart : minutes + (24 * 60 - timelineDayStart)
  }

  private static func fingerprint(for cards: [TimelineCard], plan: DayGoalPlan?) -> String {
    let cardSource = cards
      .sorted { ($0.recordId ?? 0) < ($1.recordId ?? 0) }
      .map { "\($0.recordId ?? 0)|\($0.startTimestamp)|\($0.endTimestamp)|\($0.category)|\($0.title)|\($0.summary)" }
      .joined(separator: "\n")
    let windowSource = (plan?.focusWindows ?? [])
      .sorted { $0.id < $1.id }
      .map { "\($0.id)|\($0.startMinutes)|\($0.endMinutes)|\($0.focusCategoryIDs.joined(separator: ","))" }
      .joined(separator: "\n")
    return String(stableHash("\(cardSource)\n--windows--\n\(windowSource)"), radix: 16)
  }

  private static func stableHash(_ value: String) -> UInt64 {
    value.utf8.reduce(UInt64(14_695_981_039_346_656_037)) { hash, byte in
      (hash ^ UInt64(byte)) &* 1_099_511_628_211
    }
  }

  private static func threadID(for label: String) -> String {
    "thread-\(String(stableHash(label), radix: 16))"
  }

  private static func jsonURL(for day: String) -> URL {
    let components = day.split(separator: "-")
    let year = components.first.map(String.init) ?? "unknown"
    let month = components.dropFirst().first.map(String.init) ?? "unknown"
    return archiveDirectoryURL()
      .appendingPathComponent(year, isDirectory: true)
      .appendingPathComponent(month, isDirectory: true)
      .appendingPathComponent("\(day).json")
  }

  private static func svgURL(for day: String) -> URL {
    jsonURL(for: day).deletingPathExtension().appendingPathExtension("svg")
  }

  private static func loadArchive(at url: URL) -> DayShapeArchive? {
    guard let data = try? Data(contentsOf: url) else { return nil }
    return try? JSONDecoder().decode(DayShapeArchive.self, from: data)
  }

  private static func save(_ archive: DayShapeArchive) {
    let directory = jsonURL(for: archive.day).deletingLastPathComponent()
    try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    guard let json = try? encoder.encode(archive) else { return }
    try? json.write(to: jsonURL(for: archive.day), options: .atomic)
    try? renderSVG(archive).data(using: .utf8)?.write(to: svgURL(for: archive.day), options: .atomic)
  }

  private static func removeArchive(for day: String) {
    try? FileManager.default.removeItem(at: jsonURL(for: day))
    try? FileManager.default.removeItem(at: svgURL(for: day))
  }

  private static func renderSVG(_ archive: DayShapeArchive) -> String {
    let width = 900.0
    let height = 560.0
    let threadByID = Dictionary(uniqueKeysWithValues: archive.threads.map { ($0.id, $0) })
    let connections = archive.threads.flatMap { thread -> [String] in
      let points = archive.points.filter { $0.threadID == thread.id }.sorted { $0.startMinute < $1.startMinute }
      return zip(points, points.dropFirst()).map { first, second in
        "<line x1=\"\(svgNumber(first.constellationX * width))\" y1=\"\(svgNumber(first.constellationY * height))\" x2=\"\(svgNumber(second.constellationX * width))\" y2=\"\(svgNumber(second.constellationY * height))\" stroke=\"#E8DED5\" stroke-width=\"1.5\"/>"
      }
    }.joined()
    let dots = archive.points.map { point -> String in
      let color = threadByID[point.threadID]?.colorHex ?? "B5AAA2"
      let radius = min(17, max(5, 4 + sqrt(Double(point.durationMinutes)) * 1.35))
      return "<circle cx=\"\(svgNumber(point.constellationX * width))\" cy=\"\(svgNumber(point.constellationY * height))\" r=\"\(svgNumber(radius))\" fill=\"#\(color)\" stroke=\"#FFFDF9\" stroke-width=\"3\"/>"
    }.joined()
    let labels: String = archive.threads.enumerated().map { index, thread -> String in
      let y: Double = 485.0 + Double(index % 2) * 25.0
      let x: Double = 45.0 + Double(index / 2) * 275.0
      return "<circle cx=\"\(svgNumber(x))\" cy=\"\(svgNumber(y - 4.0))\" r=\"5\" fill=\"#\(thread.colorHex)\"/><text x=\"\(svgNumber(x + 11.0))\" y=\"\(svgNumber(y))\" fill=\"#554A43\" font-family=\"-apple-system, BlinkMacSystemFont, sans-serif\" font-size=\"14\">\(escapeXML(thread.label))</text>"
    }.joined()
    return """
      <svg xmlns="http://www.w3.org/2000/svg" width="900" height="560" viewBox="0 0 900 560">
        <rect width="900" height="560" fill="#FFFDF9"/>
        <text x="45" y="52" fill="#332B26" font-family="Georgia, serif" font-size="29">Shape of your day</text>
        <text x="45" y="78" fill="#7B7068" font-family="-apple-system, BlinkMacSystemFont, sans-serif" font-size="15">\(escapeXML(archive.day)) · \(archive.points.count) captured intervals · \(archive.totalMinutes) minutes</text>
        \(connections)
        \(dots)
        \(labels)
      </svg>
      """
  }

  private static func svgNumber(_ value: Double) -> String {
    String(format: "%.1f", value)
  }

  private static func escapeXML(_ value: String) -> String {
    value.replacingOccurrences(of: "&", with: "&amp;")
      .replacingOccurrences(of: "<", with: "&lt;")
      .replacingOccurrences(of: ">", with: "&gt;")
      .replacingOccurrences(of: "\"", with: "&quot;")
  }
}
