import Foundation

struct DayShapeArchive: Codable, Equatable, Sendable {
  static let algorithmVersion = 5

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

  private static func legacySVGURL(for day: String) -> URL {
    jsonURL(for: day).deletingPathExtension().appendingPathExtension("svg")
  }

  private static func constellationSVGURL(for day: String) -> URL {
    jsonURL(for: day).deletingPathExtension().appendingPathExtension("constellation.svg")
  }

  private static func dayTraceSVGURL(for day: String) -> URL {
    jsonURL(for: day).deletingPathExtension().appendingPathExtension("day-trace.svg")
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
    try? renderConstellationSVG(archive).data(using: .utf8)?.write(to: constellationSVGURL(for: archive.day), options: .atomic)
    try? renderDayTraceSVG(archive).data(using: .utf8)?.write(to: dayTraceSVGURL(for: archive.day), options: .atomic)
    try? FileManager.default.removeItem(at: legacySVGURL(for: archive.day))
  }

  private static func removeArchive(for day: String) {
    try? FileManager.default.removeItem(at: jsonURL(for: day))
    try? FileManager.default.removeItem(at: legacySVGURL(for: day))
    try? FileManager.default.removeItem(at: constellationSVGURL(for: day))
    try? FileManager.default.removeItem(at: dayTraceSVGURL(for: day))
  }

  private static func renderConstellationSVG(_ archive: DayShapeArchive) -> String {
    let chartLeft = 92.0
    let chartTop = 258.0
    let chartWidth = 1_016.0
    let chartHeight = 270.0
    let threadByID = Dictionary(uniqueKeysWithValues: archive.threads.map { ($0.id, $0) })
    let connections: String = archive.threads.flatMap { thread -> [String] in
      let points = archive.points.filter { $0.threadID == thread.id }.sorted { $0.startMinute < $1.startMinute }
      return zip(points, points.dropFirst()).map { first, second in
        "<line x1=\"\(svgNumber(chartLeft + first.constellationX * chartWidth))\" y1=\"\(svgNumber(chartTop + first.constellationY * chartHeight))\" x2=\"\(svgNumber(chartLeft + second.constellationX * chartWidth))\" y2=\"\(svgNumber(chartTop + second.constellationY * chartHeight))\" stroke=\"#\(thread.colorHex)\" stroke-opacity=\"0.20\" stroke-width=\"2\"/>"
      }
    }.joined()
    let dots: String = archive.points.map { point -> String in
      let color = threadByID[point.threadID]?.colorHex ?? "B5AAA2"
      let radius = min(21.0, max(7.0, 5.0 + sqrt(Double(point.durationMinutes)) * 1.55))
      return "<circle cx=\"\(svgNumber(chartLeft + point.constellationX * chartWidth))\" cy=\"\(svgNumber(chartTop + point.constellationY * chartHeight))\" r=\"\(svgNumber(radius))\" fill=\"#\(color)\" stroke=\"#FFFDF9\" stroke-width=\"4\"/>"
    }.joined()
    let labels: String = archive.threads.enumerated().map { index, thread -> String in
      let column = index % 3
      let row = index / 3
      let x = 104.0 + Double(column) * 335.0
      let y = 636.0 + Double(row) * 42.0
      return "<circle cx=\"\(svgNumber(x))\" cy=\"\(svgNumber(y - 5.0))\" r=\"6\" fill=\"#\(thread.colorHex)\"/><text x=\"\(svgNumber(x + 15.0))\" y=\"\(svgNumber(y))\" fill=\"#554A43\" font-family=\"-apple-system, BlinkMacSystemFont, sans-serif\" font-size=\"17\">\(escapeXML(thread.label))</text>"
    }.joined()
    return """
      <svg xmlns="http://www.w3.org/2000/svg" width="1200" height="760" viewBox="0 0 1200 760">
        <rect width="1200" height="760" fill="#FFFDF9"/>
        <rect x="55" y="42" width="1090" height="664" rx="10" fill="#FFFCF8" stroke="#E8DED5"/>
        <text x="92" y="112" fill="#332B26" font-family="Georgia, serif" font-size="43">Shape of your day</text>
        <text x="92" y="142" fill="#7B7068" font-family="-apple-system, BlinkMacSystemFont, sans-serif" font-size="17">\(escapeXML(formattedDay(archive.day))) · \(archive.points.count) captured intervals · \(formatMinutes(archive.totalMinutes))</text>
        <text x="92" y="188" fill="#8B6E5C" font-family="-apple-system, BlinkMacSystemFont, sans-serif" font-size="13" letter-spacing="2">CONSTELLATION</text>
        <text x="92" y="212" fill="#554A43" font-family="Georgia, serif" font-size="26">The work threads that formed your day</text>
        \(connections)
        \(dots)
        <line x1="92" y1="584" x2="1108" y2="584" stroke="#E8DED5"/>
        \(labels)
      </svg>
      """
  }

  private static func renderDayTraceSVG(_ archive: DayShapeArchive) -> String {
    let chartLeft = 150.0
    let chartTop = 250.0
    let chartWidth = 640.0
    let rowHeight = 48.0
    let chartHeight = max(1.0, Double(archive.threads.count) * rowHeight)
    let threadByID = Dictionary(uniqueKeysWithValues: archive.threads.map { ($0.id, $0) })
    let windows: String = archive.focusWindows.map { window -> String in
      let x = chartLeft + Double(window.startMinute) / 1_440.0 * chartWidth
      let width = Double(window.endMinute - window.startMinute) / 1_440.0 * chartWidth
      return "<rect x=\"\(svgNumber(x))\" y=\"\(svgNumber(chartTop - 22.0))\" width=\"\(svgNumber(width))\" height=\"\(svgNumber(chartHeight + 44.0))\" fill=\"#DDE6FF\" fill-opacity=\"0.72\"/><text x=\"\(svgNumber(x + 8.0))\" y=\"\(svgNumber(chartTop - 7.0))\" fill=\"#7B83A6\" font-family=\"-apple-system, BlinkMacSystemFont, sans-serif\" font-size=\"11\">planned window</text>"
    }.joined()
    let rows: String = archive.threads.enumerated().map { index, thread -> String in
      let y = chartTop + Double(index) * rowHeight
      return "<text x=\"134\" y=\"\(svgNumber(y + 31.0))\" text-anchor=\"end\" fill=\"#70655D\" font-family=\"-apple-system, BlinkMacSystemFont, sans-serif\" font-size=\"14\">\(escapeXML(shortLabel(thread.label)))</text><rect x=\"\(svgNumber(chartLeft))\" y=\"\(svgNumber(y + 8.0))\" width=\"\(svgNumber(chartWidth))\" height=\"29\" rx=\"4\" fill=\"#F7F2ED\"/>"
    }.joined()
    let ticks: String = [120, 300, 480, 660, 840, 1_020].map { minute -> String in
      let x = chartLeft + Double(minute) / 1_440.0 * chartWidth
      return "<text x=\"\(svgNumber(x))\" y=\"222\" text-anchor=\"middle\" fill=\"#8B8077\" font-family=\"-apple-system, BlinkMacSystemFont, sans-serif\" font-size=\"12\">\(clockLabel(for: minute))</text><line x1=\"\(svgNumber(x))\" y1=\"238\" x2=\"\(svgNumber(x))\" y2=\"\(svgNumber(chartTop + chartHeight + 22.0))\" stroke=\"#EFE8E2\"/>"
    }.joined()
    let connectors: String = archive.threads.compactMap { thread -> String? in
      let row = archive.threads.firstIndex(where: { $0.id == thread.id }) ?? 0
      let y = chartTop + Double(row) * rowHeight + rowHeight / 2.0
      let points = archive.points.filter { $0.threadID == thread.id }.sorted { $0.startMinute < $1.startMinute }
      guard points.count > 1 else { return nil }
      let segments: String = zip(points, points.dropFirst()).map { first, second -> String in
        let x1 = chartLeft + Double(first.startMinute + first.endMinute) / 2.0 / 1_440.0 * chartWidth
        let x2 = chartLeft + Double(second.startMinute + second.endMinute) / 2.0 / 1_440.0 * chartWidth
        return "<line x1=\"\(svgNumber(x1))\" y1=\"\(svgNumber(y))\" x2=\"\(svgNumber(x2))\" y2=\"\(svgNumber(y))\" stroke=\"#\(thread.colorHex)\" stroke-opacity=\"0.38\" stroke-width=\"1.5\" stroke-dasharray=\"4 5\"/>"
      }.joined()
      return segments
    }.joined()
    let dots: String = archive.points.map { point -> String in
      let row = archive.threads.firstIndex(where: { $0.id == point.threadID }) ?? 0
      let x = chartLeft + Double(point.startMinute + point.endMinute) / 2.0 / 1_440.0 * chartWidth
      let y = chartTop + Double(row) * rowHeight + rowHeight / 2.0
      let color = threadByID[point.threadID]?.colorHex ?? "B5AAA2"
      return "<circle cx=\"\(svgNumber(x))\" cy=\"\(svgNumber(y))\" r=\"7\" fill=\"#\(color)\" stroke=\"#FFFDF9\" stroke-width=\"3\"/>"
    }.joined()
    return """
      <svg xmlns="http://www.w3.org/2000/svg" width="1200" height="760" viewBox="0 0 1200 760">
        <rect width="1200" height="760" fill="#FFFDF9"/>
        <rect x="55" y="42" width="1090" height="664" rx="10" fill="#FFFCF8" stroke="#E8DED5"/>
        <text x="92" y="112" fill="#332B26" font-family="Georgia, serif" font-size="43">Shape of your day</text>
        <text x="92" y="142" fill="#7B7068" font-family="-apple-system, BlinkMacSystemFont, sans-serif" font-size="17">\(escapeXML(formattedDay(archive.day))) · \(archive.points.count) captured intervals · \(formatMinutes(archive.totalMinutes))</text>
        <text x="92" y="188" fill="#8B6E5C" font-family="-apple-system, BlinkMacSystemFont, sans-serif" font-size="13" letter-spacing="2">DAY TRACE</text>
        <text x="92" y="212" fill="#554A43" font-family="Georgia, serif" font-size="26">Where those threads appeared</text>
        \(ticks)
        \(rows)
        \(windows)
        \(connectors)
        \(dots)
        <rect x="844" y="184" width="252" height="370" rx="8" fill="#FCF7F1" stroke="#E8DED5"/>
        <text x="870" y="222" fill="#8B6E5C" font-family="-apple-system, BlinkMacSystemFont, sans-serif" font-size="12" letter-spacing="2">READ THE TRACE</text>
        <text x="870" y="270" fill="#554A43" font-family="-apple-system, BlinkMacSystemFont, sans-serif" font-size="15" font-weight="600">Focus-window overlay</text>
        <text x="870" y="295" fill="#7B7068" font-family="-apple-system, BlinkMacSystemFont, sans-serif" font-size="14">Planned blocks sit behind the</text>
        <text x="870" y="315" fill="#7B7068" font-family="-apple-system, BlinkMacSystemFont, sans-serif" font-size="14">same work cards used in Plan vs Drift.</text>
        <line x1="870" y1="342" x2="1070" y2="342" stroke="#E8DED5"/>
        <text x="870" y="374" fill="#554A43" font-family="-apple-system, BlinkMacSystemFont, sans-serif" font-size="15" font-weight="600">Time stays visible</text>
        <text x="870" y="399" fill="#7B7068" font-family="-apple-system, BlinkMacSystemFont, sans-serif" font-size="14">Colors name the same inferred</text>
        <text x="870" y="419" fill="#7B7068" font-family="-apple-system, BlinkMacSystemFont, sans-serif" font-size="14">threads as the Constellation.</text>
        <line x1="870" y1="446" x2="1070" y2="446" stroke="#E8DED5"/>
        <text x="870" y="478" fill="#554A43" font-family="-apple-system, BlinkMacSystemFont, sans-serif" font-size="15" font-weight="600">No productivity grade</text>
        <text x="870" y="503" fill="#7B7068" font-family="-apple-system, BlinkMacSystemFont, sans-serif" font-size="14">Gaps and switches are evidence</text>
        <text x="870" y="523" fill="#7B7068" font-family="-apple-system, BlinkMacSystemFont, sans-serif" font-size="14">for reflection, not failure.</text>
      </svg>
      """
  }

  private static func svgNumber(_ value: Double) -> String {
    String(format: "%.1f", value)
  }

  private static func formattedDay(_ day: String) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "yyyy-MM-dd"
    guard let date = formatter.date(from: day) else { return day }
    formatter.dateFormat = "EEE, MMM d"
    return formatter.string(from: date)
  }

  private static func formatMinutes(_ minutes: Int) -> String {
    let hours = minutes / 60
    let remainder = minutes % 60
    if hours == 0 { return "\(remainder)m" }
    if remainder == 0 { return "\(hours)h" }
    return "\(hours)h \(remainder)m"
  }

  private static func shortLabel(_ value: String) -> String {
    value.count > 16 ? "\(value.prefix(15))..." : value
  }

  private static func clockLabel(for timelineMinute: Int) -> String {
    let localMinute = (timelineMinute + timelineDayStart) % (24 * 60)
    let hour = localMinute / 60
    let displayHour = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour)
    return "\(displayHour)"
  }

  private static func escapeXML(_ value: String) -> String {
    value.replacingOccurrences(of: "&", with: "&amp;")
      .replacingOccurrences(of: "<", with: "&lt;")
      .replacingOccurrences(of: ">", with: "&gt;")
      .replacingOccurrences(of: "\"", with: "&quot;")
  }
}
