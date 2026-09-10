import Foundation

struct TogglProjectMapping: Identifiable, Equatable {
  enum Destination: Equatable {
    case togglProject(String)
    case skip
  }

  let id = UUID()
  let dayflowProject: String
  let keywords: [String]
  let destination: Destination
}

struct TogglDraftRow: Identifiable, Equatable {
  let id = UUID()
  let start: Date
  let end: Date
  let roundedMinutes: Int
  let exactMinutes: Int
  var description: String
  let dayflowProject: String
  var togglProject: String
  let sourceCardCount: Int
  let isManual: Bool
  let skippedReason: String?
  var isIncluded: Bool

  var isSkipped: Bool { skippedReason != nil || !isIncluded }
  var reviewKey: String {
    [
      "\(Int(start.timeIntervalSince1970))",
      "\(Int(end.timeIntervalSince1970))",
      dayflowProject,
      "\(sourceCardCount)",
      "\(isManual)",
    ].joined(separator: "|")
  }

  var sourceCountLabel: String {
    let noun = isManual ? "manual capture" : "card"
    return "\(sourceCardCount) \(sourceCardCount == 1 ? noun : "\(noun)s")"
  }
}

enum TogglExportMode: String, CaseIterable, Identifiable {
  case detailed
  case consolidated
  case summary

  var id: String { rawValue }

  var label: String {
    switch self {
    case .detailed: return "Detailed"
    case .consolidated: return "Consolidated"
    case .summary: return "Summary"
    }
  }
}

enum TogglRounding: String, CaseIterable, Identifiable {
  case exact
  case fiveMinutes
  case fifteenMinutes

  var id: String { rawValue }

  var label: String {
    switch self {
    case .exact: return "Exact"
    case .fiveMinutes: return "5 min"
    case .fifteenMinutes: return "15 min"
    }
  }

  var increment: Int {
    switch self {
    case .exact: return 1
    case .fiveMinutes: return 5
    case .fifteenMinutes: return 15
    }
  }
}

enum TogglMappingPreferences {
  private static let mappingKey = "togglV2ProjectMappings"
  private static let roundingKey = "togglV2Rounding"
  private static let exportModeKey = "togglV3ExportMode"
  private static let emailKey = "togglV3ImportEmail"
  private static let knownProjectsKey = "togglV4KnownProjects"
  private static let includePersonalKey = "togglV2IncludePersonal"
  private static let includeDistractionsKey = "togglV2IncludeDistractions"

  static let defaultMappingText = """
    Dayflow -> Directing Business Consulting | dayflow,teleportlabs
    Coding -> Directing Business Consulting | xcode,cursor,github,git,swift
    Meetings -> Directing Business Consulting | zoom,teams,meet,calendar
    Personal -> Personal | cooking,personal
    Distractions -> SKIP | distraction,x.com,twitter,youtube
    """

  static var mappingText: String {
    get {
      UserDefaults.standard.string(forKey: mappingKey) ?? defaultMappingText
    }
    set {
      UserDefaults.standard.set(newValue, forKey: mappingKey)
    }
  }

  static var rounding: TogglRounding {
    get {
      guard let raw = UserDefaults.standard.string(forKey: roundingKey),
        let value = TogglRounding(rawValue: raw)
      else { return .fiveMinutes }
      return value
    }
    set {
      UserDefaults.standard.set(newValue.rawValue, forKey: roundingKey)
    }
  }

  static var exportMode: TogglExportMode {
    get {
      guard let raw = UserDefaults.standard.string(forKey: exportModeKey),
        let value = TogglExportMode(rawValue: raw)
      else { return .consolidated }
      return value
    }
    set {
      UserDefaults.standard.set(newValue.rawValue, forKey: exportModeKey)
    }
  }

  static var importEmail: String {
    get {
      UserDefaults.standard.string(forKey: emailKey) ?? ""
    }
    set {
      UserDefaults.standard.set(
        newValue.trimmingCharacters(in: .whitespacesAndNewlines),
        forKey: emailKey
      )
    }
  }

  static var knownProjectsText: String {
    get {
      UserDefaults.standard.string(forKey: knownProjectsKey) ?? """
        Directing Business Consulting
        Personal
        """
    }
    set {
      UserDefaults.standard.set(
        newValue.trimmingCharacters(in: .whitespacesAndNewlines),
        forKey: knownProjectsKey
      )
    }
  }

  static var includePersonal: Bool {
    get {
      if UserDefaults.standard.object(forKey: includePersonalKey) == nil { return false }
      return UserDefaults.standard.bool(forKey: includePersonalKey)
    }
    set {
      UserDefaults.standard.set(newValue, forKey: includePersonalKey)
    }
  }

  static var includeDistractions: Bool {
    get {
      if UserDefaults.standard.object(forKey: includeDistractionsKey) == nil { return false }
      return UserDefaults.standard.bool(forKey: includeDistractionsKey)
    }
    set {
      UserDefaults.standard.set(newValue, forKey: includeDistractionsKey)
    }
  }
}

enum TogglMappingParser {
  static func parse(_ text: String) -> [TogglProjectMapping] {
    text.components(separatedBy: .newlines).compactMap { line in
      let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { return nil }

      let mappingAndKeywords = trimmed.split(separator: "|", maxSplits: 1).map(String.init)
      let mappingPart = mappingAndKeywords[0]
      let keywordsPart = mappingAndKeywords.count > 1 ? mappingAndKeywords[1] : ""
      let pieces = mappingPart.components(separatedBy: "->")
      guard pieces.count == 2 else { return nil }

      let dayflowProject = pieces[0].trimmingCharacters(in: .whitespacesAndNewlines)
      let destinationText = pieces[1].trimmingCharacters(in: .whitespacesAndNewlines)
      guard !dayflowProject.isEmpty, !destinationText.isEmpty else { return nil }

      let keywords = keywordsPart
        .components(separatedBy: ",")
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
        .filter { !$0.isEmpty }

      let destination: TogglProjectMapping.Destination =
        destinationText.caseInsensitiveCompare("skip") == .orderedSame
        ? .skip
        : .togglProject(destinationText)

      return TogglProjectMapping(
        dayflowProject: dayflowProject,
        keywords: keywords,
        destination: destination
      )
    }
  }
}

enum TogglProjectCatalog {
  static func parse(_ text: String) -> [String] {
    text
      .components(separatedBy: .newlines)
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
  }

  static func unknownProjects(rows: [TogglDraftRow], knownProjects: [String]) -> [String] {
    let normalizedKnown = Set(
      knownProjects
        .map { normalize($0) }
        .filter { !$0.isEmpty }
    )

    return Array(
      Set(
        rows
          .filter { !$0.isSkipped }
          .map(\.togglProject)
          .filter { !normalize($0).isEmpty && !normalizedKnown.contains(normalize($0)) }
      )
    )
    .sorted()
  }

  static func isKnownProject(_ project: String, knownProjects: [String]) -> Bool {
    let normalizedProject = normalize(project)
    guard !normalizedProject.isEmpty else { return false }
    return knownProjects.contains { normalize($0) == normalizedProject }
  }

  private static func normalize(_ value: String) -> String {
    value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
  }
}

enum TogglDraftExportService {
  private static let mergeGapSeconds: TimeInterval = 10 * 60
  private static let minimumExportMinutes = 3

  static func buildRows(
    from cards: [TimelineCard],
    manualCaptures: [ManualCapture] = [],
    mappings: [TogglProjectMapping],
    rounding: TogglRounding,
    mode: TogglExportMode,
    includePersonal: Bool,
    includeDistractions: Bool
  ) -> [TogglDraftRow] {
    let items = (
      cards.compactMap {
        makeItem(
          from: $0,
          mappings: mappings,
          includePersonal: includePersonal,
          includeDistractions: includeDistractions
        )
      }
      + manualCaptures.compactMap {
        makeItem(from: $0, mappings: mappings, includePersonal: includePersonal)
      }
    )
    .sorted { $0.start < $1.start }

    let groups: [DraftGroup]
    switch mode {
    case .detailed:
      groups = items.map(DraftGroup.init(item:))
    case .consolidated:
      groups = consolidatedGroups(from: items)
    case .summary:
      groups = summaryGroups(from: items)
    }

    return groups.map { group in
      makeRow(from: group, rounding: rounding, mode: mode)
    }
  }

  static func makeCSV(rows: [TogglDraftRow], email: String) -> String {
    var lines = [
      "Email,Client,Project,Task,Description,Billable,Start date,Start time,Duration,Tags"
    ]
    let dateFormatter = DateFormatter()
    dateFormatter.dateFormat = "yyyy-MM-dd"
    let timeFormatter = DateFormatter()
    timeFormatter.dateFormat = "HH:mm:ss"

    for row in rows where !row.isSkipped {
      let values = [
        email,
        "",
        row.togglProject,
        "",
        row.description,
        "No",
        dateFormatter.string(from: row.start),
        timeFormatter.string(from: row.start),
        durationString(minutes: row.roundedMinutes),
        togglTags(for: row),
      ]
      lines.append(values.map(csvEscape).joined(separator: ","))
    }
    return lines.joined(separator: "\n")
  }

  private static func consolidatedGroups(from items: [DraftItem]) -> [DraftGroup] {
    var groups: [DraftGroup] = []
    for item in items {
      if var last = groups.popLast() {
        if last.canMerge(with: item) {
          last.append(item)
          groups.append(last)
        } else {
          groups.append(last)
          groups.append(DraftGroup(item: item))
        }
      } else {
        groups.append(DraftGroup(item: item))
      }
    }
    return groups
  }

  private static func summaryGroups(from items: [DraftItem]) -> [DraftGroup] {
    var groupsByKey: [String: DraftGroup] = [:]
    let dayFormatter = DateFormatter()
    dayFormatter.dateFormat = "yyyy-MM-dd"

    for item in items {
      let key = [
        dayFormatter.string(from: item.start),
        item.dayflowProject,
        item.togglProject,
        "\(item.isSkipped)",
        "\(item.isManual)",
      ].joined(separator: "|")

      if var group = groupsByKey[key] {
        group.appendForSummary(item)
        groupsByKey[key] = group
      } else {
        groupsByKey[key] = DraftGroup(item: item)
      }
    }
    return groupsByKey.values.sorted { lhs, rhs in
      if lhs.start == rhs.start { return lhs.dayflowProject < rhs.dayflowProject }
      return lhs.start < rhs.start
    }
  }

  private static func makeRow(
    from group: DraftGroup,
    rounding: TogglRounding,
    mode: TogglExportMode
  ) -> TogglDraftRow {
    let exactMinutes = max(1, Int((group.totalDuration / 60).rounded()))
    let roundedMinutes = round(minutes: exactMinutes, rounding: rounding)
    let description = makeDescription(for: group, mode: mode)
    let skippedReason: String?
    if group.isSkipped {
      skippedReason = "Mapped to SKIP"
    } else if roundedMinutes < minimumExportMinutes {
      skippedReason = "Under \(minimumExportMinutes) min"
    } else {
      skippedReason = nil
    }

    return TogglDraftRow(
      start: group.start,
      end: group.end,
      roundedMinutes: roundedMinutes,
      exactMinutes: exactMinutes,
      description: description,
      dayflowProject: group.dayflowProject,
      togglProject: group.togglProject,
      sourceCardCount: group.items.count,
      isManual: group.isManual,
      skippedReason: skippedReason,
      isIncluded: skippedReason == nil
    )
  }

  private static func makeItem(
    from card: TimelineCard,
    mappings: [TogglProjectMapping],
    includePersonal: Bool,
    includeDistractions: Bool
  ) -> DraftItem? {
    guard card.title != "Processing failed" else { return nil }
    guard card.category.caseInsensitiveCompare("Idle") != .orderedSame else { return nil }
    guard let interval = cardInterval(card) else { return nil }

    let text = searchableText(card)
    let mapping = bestMapping(for: text, category: card.category, mappings: mappings)
    let dayflowProject = mapping?.dayflowProject ?? inferredProject(from: card)
    let destination = mapping?.destination ?? .togglProject(dayflowProject)

    if !includePersonal && dayflowProject.caseInsensitiveCompare("Personal") == .orderedSame {
      return DraftItem(
        start: interval.start, end: interval.end, title: card.title,
        dayflowProject: dayflowProject, togglProject: "Personal", isSkipped: true, isManual: false)
    }

    if !includeDistractions
      && (card.category.caseInsensitiveCompare("Distraction") == .orderedSame
        || dayflowProject.caseInsensitiveCompare("Distractions") == .orderedSame)
    {
      return DraftItem(
        start: interval.start, end: interval.end, title: card.title,
        dayflowProject: dayflowProject, togglProject: "Distractions", isSkipped: true, isManual: false)
    }

    switch destination {
    case .skip:
      return DraftItem(
        start: interval.start, end: interval.end, title: card.title,
        dayflowProject: dayflowProject, togglProject: "SKIP", isSkipped: true, isManual: false)
    case .togglProject(let togglProject):
      return DraftItem(
        start: interval.start, end: interval.end, title: card.title,
        dayflowProject: dayflowProject, togglProject: togglProject, isSkipped: false, isManual: false)
    }
  }

  private static func makeItem(
    from capture: ManualCapture,
    mappings: [TogglProjectMapping],
    includePersonal: Bool
  ) -> DraftItem? {
    guard let startTs = capture.startTs, let endTs = capture.endTs, endTs > startTs else { return nil }

    let dayflowProject = manualProject(for: capture)
    let mapping = bestMapping(
      for: "\(dayflowProject) \(capture.kind.label) \(capture.body)",
      category: dayflowProject,
      mappings: mappings
    )
    let destination = mapping?.destination ?? .togglProject(dayflowProject)
    let start = Date(timeIntervalSince1970: TimeInterval(startTs))
    let end = Date(timeIntervalSince1970: TimeInterval(endTs))

    if !includePersonal && dayflowProject.caseInsensitiveCompare("Personal") == .orderedSame {
      return DraftItem(
        start: start, end: end, title: capture.body,
        dayflowProject: dayflowProject, togglProject: "Personal", isSkipped: true, isManual: true)
    }

    switch destination {
    case .skip:
      return DraftItem(
        start: start, end: end, title: capture.body,
        dayflowProject: dayflowProject, togglProject: "SKIP", isSkipped: true, isManual: true)
    case .togglProject(let togglProject):
      return DraftItem(
        start: start, end: end, title: capture.body,
        dayflowProject: dayflowProject, togglProject: togglProject, isSkipped: false, isManual: true)
    }
  }

  private static func manualProject(for capture: ManualCapture) -> String {
    if let projectName = capture.projectName?.trimmingCharacters(in: .whitespacesAndNewlines), !projectName.isEmpty {
      return projectName
    }
    switch capture.kind {
    case .meeting: return "Meetings"
    case .personal: return "Personal"
    case .offlineWork: return "Offline work"
    case .note: return "Notes"
    }
  }

  private static func bestMapping(
    for text: String,
    category: String,
    mappings: [TogglProjectMapping]
  ) -> TogglProjectMapping? {
    let lowerText = text.lowercased()
    let lowerCategory = category.lowercased()

    return mappings.max { lhs, rhs in
      score(mapping: lhs, text: lowerText, category: lowerCategory)
        < score(mapping: rhs, text: lowerText, category: lowerCategory)
    }.flatMap { mapping in
      score(mapping: mapping, text: lowerText, category: lowerCategory) > 0 ? mapping : nil
    }
  }

  private static func score(mapping: TogglProjectMapping, text: String, category: String) -> Int {
    var value = 0
    if category == mapping.dayflowProject.lowercased() { value += 6 }
    if text.contains(mapping.dayflowProject.lowercased()) { value += 4 }
    for keyword in mapping.keywords where text.contains(keyword) {
      value += 3
    }
    return value
  }

  private static func inferredProject(from card: TimelineCard) -> String {
    if !card.category.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      return card.category
    }
    return "Untagged"
  }

  private static func searchableText(_ card: TimelineCard) -> String {
    [
      card.category,
      card.subcategory,
      card.title,
      card.summary,
      card.detailedSummary,
      card.appSites?.primary,
      card.appSites?.secondary,
    ]
    .compactMap { $0 }
    .joined(separator: " ")
  }

  private static func cardInterval(_ card: TimelineCard) -> (start: Date, end: Date)? {
    let dayFormatter = DateFormatter()
    dayFormatter.dateFormat = "yyyy-MM-dd"
    let timeFormatter = DateFormatter()
    timeFormatter.dateFormat = "h:mm a"
    timeFormatter.locale = Locale(identifier: "en_US_POSIX")

    guard
      let dayDate = dayFormatter.date(from: card.day),
      let startTime = timeFormatter.date(from: card.startTimestamp),
      let endTime = timeFormatter.date(from: card.endTimestamp)
    else { return nil }

    let calendar = Calendar.current
    let baseDate = calendar.startOfDay(for: dayDate)
    let startComponents = calendar.dateComponents([.hour, .minute], from: startTime)
    let endComponents = calendar.dateComponents([.hour, .minute], from: endTime)

    guard
      var start = calendar.date(
        bySettingHour: startComponents.hour ?? 0,
        minute: startComponents.minute ?? 0,
        second: 0,
        of: baseDate),
      var end = calendar.date(
        bySettingHour: endComponents.hour ?? 0,
        minute: endComponents.minute ?? 0,
        second: 0,
        of: baseDate)
    else { return nil }

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

  private static func round(minutes: Int, rounding: TogglRounding) -> Int {
    let increment = rounding.increment
    guard increment > 1 else { return minutes }
    return max(increment, Int((Double(minutes) / Double(increment)).rounded()) * increment)
  }

  private static func makeDescription(for group: DraftGroup, mode: TogglExportMode) -> String {
    let titles = group.items.map(\.title)
    let first = titles.first ?? "Work block"
    if group.isManual {
      return mode == .summary ? "\(group.dayflowProject): Manual activity summary" : "Manual: \(first)"
    }
    if mode == .summary {
      return "\(group.dayflowProject): Daily work summary"
    }
    guard titles.count > 1 else {
      return "\(group.dayflowProject): \(cleanTitle(first, project: group.dayflowProject))"
    }

    let uniqueKeywords = Set(
      titles.flatMap { title in
        title.lowercased()
          .components(separatedBy: CharacterSet.alphanumerics.inverted)
          .filter { $0.count >= 5 }
      }
    )

    if uniqueKeywords.contains("export") || uniqueKeywords.contains("toggl") {
      return "\(group.dayflowProject): Toggl export and time-entry cleanup"
    }
    if uniqueKeywords.contains("debug") || uniqueKeywords.contains("processing")
      || uniqueKeywords.contains("diagnostics")
    {
      return "\(group.dayflowProject): Processing diagnostics and repair"
    }
    return "\(group.dayflowProject): \(cleanTitle(first, project: group.dayflowProject))"
  }

  private static func cleanTitle(_ title: String, project: String) -> String {
    let prefix = "\(project):"
    if title.lowercased().hasPrefix(prefix.lowercased()) {
      return title.dropFirst(prefix.count).trimmingCharacters(in: .whitespacesAndNewlines)
    }
    return title
  }

  private static func csvEscape(_ value: String) -> String {
    let escaped = value.replacingOccurrences(of: "\"", with: "\"\"")
    if escaped.contains(",") || escaped.contains("\"") || escaped.contains("\n") {
      return "\"\(escaped)\""
    }
    return escaped
  }

  private static func durationString(minutes: Int) -> String {
    let hours = minutes / 60
    let mins = minutes % 60
    return String(format: "%02d:%02d:00", hours, mins)
  }

  private static func togglTags(for row: TogglDraftRow) -> String {
    [
      "dayward",
      row.isManual ? "manual" : "",
      normalizedProjectTag(row.dayflowProject),
    ]
    .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    .joined(separator: ",")
  }

  private static func normalizedProjectTag(_ project: String) -> String {
    project
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .lowercased()
      .replacingOccurrences(of: ",", with: " ")
      .replacingOccurrences(
        of: "[^a-z0-9]+",
        with: "-",
        options: .regularExpression
      )
      .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
  }

  private struct DraftItem {
    var start: Date
    var end: Date
    let title: String
    let dayflowProject: String
    let togglProject: String
    let isSkipped: Bool
    let isManual: Bool
  }

  private struct DraftGroup {
    var items: [DraftItem]
    var start: Date
    var end: Date
    let dayflowProject: String
    let togglProject: String
    var isSkipped: Bool
    let isManual: Bool
    var totalDuration: TimeInterval

    init(item: DraftItem) {
      items = [item]
      start = item.start
      end = item.end
      dayflowProject = item.dayflowProject
      togglProject = item.togglProject
      isSkipped = item.isSkipped
      isManual = item.isManual
      totalDuration = max(60, item.end.timeIntervalSince(item.start))
    }

    func canMerge(with item: DraftItem) -> Bool {
      dayflowProject == item.dayflowProject
        && togglProject == item.togglProject
        && isSkipped == item.isSkipped
        && isManual == item.isManual
        && item.start.timeIntervalSince(end) <= mergeGapSeconds
    }

    mutating func append(_ item: DraftItem) {
      items.append(item)
      end = max(end, item.end)
      totalDuration = max(60, end.timeIntervalSince(start))
    }

    mutating func appendForSummary(_ item: DraftItem) {
      items.append(item)
      start = min(start, item.start)
      end = max(end, item.end)
      totalDuration += max(60, item.end.timeIntervalSince(item.start))
    }
  }
}
