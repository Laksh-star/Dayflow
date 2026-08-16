//
//  DaySummaryStats.swift
//  Dayflow
//
//  Pure stat computation for the "Your day so far" panel. Everything here is
//  parameter-driven and safe to call from a background task — DaySummaryView
//  invokes these off the main thread to avoid hangs during body evaluation.
//

import Foundation

enum DaySummaryStats {
  /// Pre-computed card data with parsed timestamps to avoid expensive parsing during body evaluation
  struct CardWithDuration {
    let card: TimelineCard
    let duration: TimeInterval
    let startMinutes: Int  // For focus blocks calculation
    let endMinutes: Int  // For focus blocks calculation
  }

  private static let focusGapMinutes: Int = 5
  private static let timelineDayStartMinutes: Int = 4 * 60
  private static let minutesPerDay: Int = 24 * 60

  private static func normalizedCategoryName(_ name: String) -> String {
    name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
  }

  private static func timelineMinutes(for timeString: String) -> Int? {
    guard let minutes = parseTimeHMMA(timeString: timeString) else { return nil }
    if minutes >= timelineDayStartMinutes {
      return minutes - timelineDayStartMinutes
    }
    return minutes + (minutesPerDay - timelineDayStartMinutes)
  }

  /// Pre-computes per-card durations clipped to the current timeline day window (4 AM -> 4 AM).
  /// Overlap normalization is applied later based on active category configuration.
  static func precomputeCardDurations(_ cards: [TimelineCard]) -> [CardWithDuration] {
    cards.compactMap { card in
      guard let startMinutes = timelineMinutes(for: card.startTimestamp),
        let endMinutes = timelineMinutes(for: card.endTimestamp)
      else {
        return nil
      }
      var adjustedEnd = endMinutes
      if adjustedEnd < startMinutes {
        adjustedEnd += minutesPerDay
      }

      // Clip to this timeline day's 24h window so cross-boundary cards only
      // contribute the portion that belongs to the selected day.
      let clippedStart = min(max(startMinutes, 0), minutesPerDay)
      let clippedEnd = min(max(adjustedEnd, 0), minutesPerDay)
      guard clippedEnd > clippedStart else { return nil }

      let duration = TimeInterval(clippedEnd - clippedStart) * 60
      return CardWithDuration(
        card: card,
        duration: duration,
        startMinutes: clippedStart,
        endMinutes: clippedEnd
      )
    }
  }

  private struct FocusWindowWork {
    let window: DayFocusWindow
    let label: String
    let ranges: [Range<Int>]
    let selectedCategoryIDs: Set<String>
    let selectedCategoryNames: Set<String>
    var plannedMinutes: Int
    var onPlanMinutes: Int
    var driftMinutes: Int
    var recoveryCount: Int
    var segments: [FocusWindowSegment]
  }

  private struct FocusWindowSegment {
    let id: String
    let windowID: String
    let windowLabel: String
    let windowStartMinutes: Int
    let windowEndMinutes: Int
    let startMinutes: Int
    let endMinutes: Int
    let categoryName: String
    let isOnPlan: Bool
    let isDrift: Bool
  }

  /// Removes overlapping coverage by trimming later cards so each minute of the day is counted once.
  private static func removeOverlaps(from durations: [CardWithDuration]) -> [CardWithDuration] {
    guard durations.count > 1 else { return durations }

    let sorted = durations.sorted { lhs, rhs in
      if lhs.startMinutes == rhs.startMinutes {
        if lhs.endMinutes == rhs.endMinutes {
          let lhsId = lhs.card.recordId ?? 0
          let rhsId = rhs.card.recordId ?? 0
          return lhsId < rhsId
        }
        // Prefer the longer interval when starts match.
        return lhs.endMinutes > rhs.endMinutes
      }
      return lhs.startMinutes < rhs.startMinutes
    }

    var normalized: [CardWithDuration] = []
    normalized.reserveCapacity(sorted.count)
    var coveredUntil = 0

    for item in sorted {
      if coveredUntil >= minutesPerDay { break }

      let normalizedStart = max(item.startMinutes, coveredUntil)
      let normalizedEnd = min(item.endMinutes, minutesPerDay)
      guard normalizedEnd > normalizedStart else { continue }

      normalized.append(
        CardWithDuration(
          card: item.card,
          duration: TimeInterval(normalizedEnd - normalizedStart) * 60,
          startMinutes: normalizedStart,
          endMinutes: normalizedEnd
        )
      )
      coveredUntil = max(coveredUntil, normalizedEnd)
    }

    return normalized
  }

  private static func normalizedNonSystemDurations(
    from precomputed: [CardWithDuration], categories: [TimelineCategory]
  ) -> [CardWithDuration] {
    let nonSystemDurations = precomputed.filter { item in
      !isSystemCategoryStatic(item.card.category, categories: categories)
    }
    return removeOverlaps(from: nonSystemDurations)
  }

  private static func normalizedFocusDriftDurations(
    from precomputed: [CardWithDuration],
    categories: [TimelineCategory]
  ) -> [CardWithDuration] {
    let relevantDurations = precomputed.filter { item in
      !isExcludedFromFocusDrift(item.card.category, categories: categories)
    }
    return removeOverlaps(from: relevantDurations)
  }

  /// Computes category durations from pre-computed data
  static func computeCategoryDurations(
    from precomputed: [CardWithDuration], categories: [TimelineCategory]
  ) -> [CategoryTimeData] {
    let categoryLookup = firstCategoryLookup(
      from: categories, normalizedKey: normalizedCategoryName)
    var durationsByCategory: [String: TimeInterval] = [:]
    var fallbackNamesByCategory: [String: String] = [:]

    for item in normalizedNonSystemDurations(from: precomputed, categories: categories) {
      let categoryKey = normalizedCategoryName(item.card.category)
      durationsByCategory[categoryKey, default: 0] += item.duration

      if fallbackNamesByCategory[categoryKey] == nil {
        fallbackNamesByCategory[categoryKey] = item.card.category
      }
    }

    return durationsByCategory.keys.sorted { lhs, rhs in
      let lhsDuration = durationsByCategory[lhs, default: 0]
      let rhsDuration = durationsByCategory[rhs, default: 0]
      let lhsDisplayMinutes = Int(lhsDuration / 60)
      let rhsDisplayMinutes = Int(rhsDuration / 60)

      if lhsDisplayMinutes != rhsDisplayMinutes {
        return lhsDisplayMinutes > rhsDisplayMinutes
      }

      let lhsOrder = categoryLookup[lhs]?.order ?? Int.max
      let rhsOrder = categoryLookup[rhs]?.order ?? Int.max

      if lhsOrder != rhsOrder {
        return lhsOrder < rhsOrder
      }

      let lhsName = categoryLookup[lhs]?.name ?? fallbackNamesByCategory[lhs] ?? lhs
      let rhsName = categoryLookup[rhs]?.name ?? fallbackNamesByCategory[rhs] ?? rhs
      return lhsName.localizedCaseInsensitiveCompare(rhsName) == .orderedAscending
    }
    .compactMap { categoryKey -> CategoryTimeData? in
      guard let duration = durationsByCategory[categoryKey] else { return nil }
      guard duration > 0 else { return nil }

      if let category = categoryLookup[categoryKey] {
        return CategoryTimeData(category: category, duration: duration)
      }

      let name = fallbackNamesByCategory[categoryKey] ?? categoryKey
      return CategoryTimeData(name: name, colorHex: "#E5E7EB", duration: duration)
    }
  }

  /// Computes total captured time from pre-computed data
  static func computeTotalCapturedTime(
    from precomputed: [CardWithDuration], categories: [TimelineCategory]
  ) -> TimeInterval {
    normalizedNonSystemDurations(from: precomputed, categories: categories).reduce(0) {
      total, item in
      total + item.duration
    }
  }

  /// Computes total focus time from pre-computed data
  static func computeTotalFocusTime(
    from precomputed: [CardWithDuration], snapshots: [DayGoalCategorySnapshot],
    categories: [TimelineCategory]
  ) -> TimeInterval {
    normalizedNonSystemDurations(from: precomputed, categories: categories)
      .filter {
        isGoalCategoryStatic($0.card.category, snapshots: snapshots, categories: categories)
      }
      .reduce(0) { $0 + $1.duration }
  }

  /// Computes focus blocks from pre-computed data
  static func computeFocusBlocks(
    from precomputed: [CardWithDuration], snapshots: [DayGoalCategorySnapshot], baseDate: Date,
    categories: [TimelineCategory]
  ) -> [FocusBlock] {
    let focusCards = normalizedNonSystemDurations(from: precomputed, categories: categories)
      .filter {
        isGoalCategoryStatic($0.card.category, snapshots: snapshots, categories: categories)
      }

    var blocks: [(start: Int, end: Int)] = []
    for item in focusCards {
      blocks.append((start: item.startMinutes, end: item.endMinutes))
    }

    let sorted = blocks.sorted { $0.start < $1.start }
    var merged: [(start: Int, end: Int)] = []
    for block in sorted {
      if let last = merged.last {
        let gap = block.start - last.end
        if gap < focusGapMinutes {
          merged[merged.count - 1].end = max(last.end, block.end)
          continue
        }
      }
      merged.append(block)
    }

    return merged.map { block in
      let startDate = baseDate.addingTimeInterval(TimeInterval(block.start * 60))
      let endDate = baseDate.addingTimeInterval(TimeInterval(block.end * 60))
      return FocusBlock(startTime: startDate, endTime: endDate)
    }
  }

  /// Computes total distracted time from pre-computed data
  static func computeTotalDistractedTime(
    from precomputed: [CardWithDuration], snapshots: [DayGoalCategorySnapshot],
    categories: [TimelineCategory]
  ) -> TimeInterval {
    normalizedNonSystemDurations(from: precomputed, categories: categories).reduce(0) {
      total, item in
      guard
        isGoalCategoryStatic(item.card.category, snapshots: snapshots, categories: categories)
      else { return total }
      return total + item.duration
    }
  }

  static func attentionReferenceTimelineMinute(forDay day: String, now: Date = Date()) -> Int? {
    let todayInfo = timelineDisplayDate(from: now).getDayInfoFor4AMBoundary()
    guard todayInfo.dayString == day else { return nil }
    let components = Calendar.current.dateComponents([.hour, .minute], from: now)
    let clockMinutes = (components.hour ?? 0) * 60 + (components.minute ?? 0)
    return timelineMinute(fromClockMinutes: clockMinutes)
  }

  static func makeFocusDriftSnapshot(
    from precomputed: [CardWithDuration],
    plan: DayGoalPlan,
    categories: [TimelineCategory],
    referenceTimelineMinute: Int? = nil
  ) -> DayFocusDriftSnapshot {
    let windows = plan.focusWindows.filter(\.isValid)
    guard windows.isEmpty == false else {
      return .empty
    }

    let focusDurations = normalizedFocusDriftDurations(from: precomputed, categories: categories)
    let categoryByID = Dictionary(uniqueKeysWithValues: categories.map { ($0.id.uuidString, $0) })
    let fallbackFocusIDs = plan.focusCategories.map(\.categoryID)
    let fallbackFocusNames = Set(plan.focusCategories.map { normalizedCategoryName($0.name) })

    var works = windows.map { window -> FocusWindowWork in
      let resolvedIDs = Set(window.resolvedCategoryIDs(fallbackCategoryIDs: fallbackFocusIDs))
      let resolvedNames = Set(
        resolvedIDs.compactMap { categoryByID[$0]?.name }.map(normalizedCategoryName)
      ).union(fallbackFocusNames)
      let ranges = timelineRanges(for: window)
      let plannedMinutes = ranges.reduce(0) { $0 + $1.count }
      let label = window.label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        ? "\(formatClockTime(window.startMinutes)) - \(formatClockTime(window.endMinutes))"
        : window.label.trimmingCharacters(in: .whitespacesAndNewlines)
      return FocusWindowWork(
        window: window,
        label: label,
        ranges: ranges,
        selectedCategoryIDs: resolvedIDs,
        selectedCategoryNames: resolvedNames,
        plannedMinutes: plannedMinutes,
        onPlanMinutes: 0,
        driftMinutes: 0,
        recoveryCount: 0,
        segments: []
      )
    }

    for item in focusDurations {
      let normalizedCardCategory = normalizedCategoryName(item.card.category)
      let cardCategoryID =
        categories.first(where: { normalizedCategoryName($0.name) == normalizedCardCategory })?.id
        .uuidString

      for index in works.indices {
        let work = works[index]
        for range in work.ranges {
          let overlapStart = max(item.startMinutes, range.lowerBound)
          let overlapEnd = min(item.endMinutes, range.upperBound)
          guard overlapEnd > overlapStart else { continue }

          let isOnPlan =
            (cardCategoryID.map { work.selectedCategoryIDs.contains($0) } ?? false)
            || work.selectedCategoryNames.contains(normalizedCardCategory)
          let duration = overlapEnd - overlapStart
          if isOnPlan {
            works[index].onPlanMinutes += duration
          } else {
            works[index].driftMinutes += duration
          }

          works[index].segments.append(
            FocusWindowSegment(
              id: "\(work.window.id)-\(overlapStart)-\(overlapEnd)-\(item.card.recordId ?? 0)",
              windowID: work.window.id,
              windowLabel: work.label,
              windowStartMinutes: work.window.startMinutes,
              windowEndMinutes: work.window.endMinutes,
              startMinutes: overlapStart,
              endMinutes: overlapEnd,
              categoryName: item.card.category,
              isOnPlan: isOnPlan,
              isDrift: !isOnPlan
            )
          )
        }
      }
    }

    var recoveryEvents: [DayRecoveryEvent] = []
    var recoveryDurations: [Int] = []
    var driftCategoryMinutes: [String: Int] = [:]

    for index in works.indices {
      works[index].segments = mergeFocusSegments(works[index].segments)

      let segments = works[index].segments.sorted { lhs, rhs in
        if lhs.startMinutes == rhs.startMinutes {
          return lhs.endMinutes < rhs.endMinutes
        }
        return lhs.startMinutes < rhs.startMinutes
      }

      for (segmentIndex, segment) in segments.enumerated() where segment.isDrift {
        driftCategoryMinutes[normalizedCategoryName(segment.categoryName), default: 0] += max(
          0,
          segment.endMinutes - segment.startMinutes
        )
        let followingOnPlan: FocusWindowSegment?
        if segmentIndex + 1 < segments.count {
          followingOnPlan = segments[(segmentIndex + 1)...].first { later in
            later.isOnPlan
              && later.startMinutes >= segment.endMinutes
              && (later.startMinutes - segment.endMinutes) <= 30
          }
        } else {
          followingOnPlan = nil
        }

        let recovered = followingOnPlan != nil
        if let followingOnPlan {
          works[index].recoveryCount += 1
          recoveryDurations.append(max(0, followingOnPlan.startMinutes - segment.endMinutes))
        }

        recoveryEvents.append(
          DayRecoveryEvent(
            id: "\(segment.windowID)-\(segment.startMinutes)-\(segment.endMinutes)",
            day: plan.day,
            windowID: segment.windowID,
            windowLabel: segment.windowLabel,
            windowStartMinutes: segment.windowStartMinutes,
            windowEndMinutes: segment.windowEndMinutes,
            driftStartMinutes: segment.startMinutes,
            driftEndMinutes: segment.endMinutes,
            recoveryStartMinutes: followingOnPlan?.startMinutes,
            recoveryEndMinutes: followingOnPlan?.endMinutes,
            triggerCategory: segment.categoryName,
            recoveryCategory: followingOnPlan?.categoryName,
            driftMinutes: max(0, segment.endMinutes - segment.startMinutes),
            recovered: recovered
          )
        )
      }
    }

    let plannedMinutes = works.reduce(0) { $0 + $1.plannedMinutes }
    let onPlanMinutes = works.reduce(0) { $0 + $1.onPlanMinutes }
    let driftMinutes = works.reduce(0) { $0 + $1.driftMinutes }
    let recoveryCount = works.reduce(0) { $0 + $1.recoveryCount }
    let unresolvedRecoveryCount = recoveryEvents.filter { !$0.recovered }.count
    let driftRatio = plannedMinutes > 0 ? Double(driftMinutes) / Double(plannedMinutes) : 0
    let averageRecoveryMinutes =
      recoveryDurations.isEmpty ? nil : Int(Double(recoveryDurations.reduce(0, +)) / Double(recoveryDurations.count))
    let fastestRecoveryMinutes = recoveryDurations.min()
    let mostCommonDriftCategories = driftCategoryMinutes
      .sorted { lhs, rhs in
        if lhs.value == rhs.value {
          return lhs.key.localizedCaseInsensitiveCompare(rhs.key) == .orderedAscending
        }
        return lhs.value > rhs.value
      }
      .prefix(3)
      .map { displayName(forNormalizedCategory: $0.key, categories: categories) }

    let attention = deriveAttentionState(
      works: works,
      recoveryEvents: recoveryEvents,
      referenceTimelineMinute: referenceTimelineMinute
        ?? focusDurations.map(\.endMinutes).max()
    )

    return DayFocusDriftSnapshot(
      plannedMinutes: plannedMinutes,
      onPlanMinutes: onPlanMinutes,
      driftMinutes: driftMinutes,
      recoveryCount: recoveryCount,
      driftRatio: driftRatio,
      averageRecoveryMinutes: averageRecoveryMinutes,
      fastestRecoveryMinutes: fastestRecoveryMinutes,
      unresolvedRecoveryCount: unresolvedRecoveryCount,
      mostCommonDriftCategories: mostCommonDriftCategories,
      windows: works.map {
        PlanVsDriftWindowSnapshot(
          id: $0.window.id,
          label: $0.label,
          startMinutes: $0.window.startMinutes,
          endMinutes: $0.window.endMinutes,
          plannedMinutes: $0.plannedMinutes,
          onPlanMinutes: $0.onPlanMinutes,
          driftMinutes: $0.driftMinutes,
          recoveryCount: $0.recoveryCount
        )
      },
      recoveryEvents: recoveryEvents.sorted { lhs, rhs in
        lhs.driftStartMinutes < rhs.driftStartMinutes
      },
      attentionState: attention.state,
      attentionMessage: attention.message
    )
  }

  /// Category matcher that treats the built-in "system" category (and any category
  /// flagged isSystem) as excluded from stats.
  private static func isSystemCategoryStatic(_ name: String, categories: [TimelineCategory])
    -> Bool
  {
    let normalized = normalizedCategoryName(name)
    if normalized == "system" { return true }
    guard let category = categories.first(where: { normalizedCategoryName($0.name) == normalized })
    else {
      return false
    }
    return category.isSystem
  }

  private static func isExcludedFromFocusDrift(_ name: String, categories: [TimelineCategory])
    -> Bool
  {
    let normalized = normalizedCategoryName(name)
    if normalized == "system" { return true }
    guard let category = categories.first(where: { normalizedCategoryName($0.name) == normalized })
    else {
      return false
    }
    return category.isSystem && !category.isIdle
  }

  /// Goal-category matcher that prefers current category IDs and falls back to saved names.
  private static func isGoalCategoryStatic(
    _ name: String, snapshots: [DayGoalCategorySnapshot], categories: [TimelineCategory]
  ) -> Bool {
    if isSystemCategoryStatic(name, categories: categories) { return false }
    let normalized = normalizedCategoryName(name)
    let selectedIDs = Set(snapshots.map(\.categoryID))

    if let category = categories.first(where: { normalizedCategoryName($0.name) == normalized }),
      selectedIDs.contains(category.id.uuidString)
    {
      return true
    }

    return snapshots.contains { normalizedCategoryName($0.name) == normalized }
  }

  static func makeGoalReviewSnapshot(
    dayInfo: (dayString: String, startOfDay: Date, endOfDay: Date),
    storageManager: StorageManaging,
    categories: [TimelineCategory]
  ) -> DayGoalReviewSnapshot {
    let plan = carriedForwardGoalPlan(
      day: dayInfo.dayString,
      storageManager: storageManager,
      categories: categories
    )
    let cards = storageManager.fetchTimelineCards(forDay: dayInfo.dayString)
    let precomputed = precomputeCardDurations(cards)
    let categoryDurations = computeCategoryDurations(from: precomputed, categories: categories)
    let focusDuration = computeTotalFocusTime(
      from: precomputed,
      snapshots: plan.focusCategories,
      categories: categories
    )
    let distractedDuration = computeTotalDistractedTime(
      from: precomputed,
      snapshots: plan.distractionCategories,
      categories: categories
    )

    return DayGoalReviewSnapshot(
      day: dayInfo.dayString,
      plan: plan,
      focusDuration: focusDuration,
      distractedDuration: distractedDuration,
      focusCategories: goalCategoryResults(
        snapshots: plan.focusCategories,
        categoryDurations: categoryDurations,
        categories: categories
      )
    )
  }

  static func makeGoalSetupReferenceStats(
    currentTimelineDate: Date,
    storageManager: StorageManaging,
    categories: [TimelineCategory]
  ) -> DayGoalSetupReferenceStats {
    let calendar = Calendar.current
    let dayStrings = (1...7).compactMap { offset -> String? in
      guard let date = calendar.date(byAdding: .day, value: -offset, to: currentTimelineDate)
      else {
        return nil
      }
      return timelineDisplayDate(from: date).getDayInfoFor4AMBoundary().dayString
    }
    guard let yesterdayDayString = dayStrings.first else { return .empty }

    let yesterdayMaps = categoryDurationMaps(
      forDay: yesterdayDayString,
      storageManager: storageManager,
      categories: categories
    )

    var lastWeekByIDTotals: [String: TimeInterval] = [:]
    var lastWeekByNameTotals: [String: TimeInterval] = [:]
    for dayString in dayStrings {
      let maps = categoryDurationMaps(
        forDay: dayString,
        storageManager: storageManager,
        categories: categories
      )
      for (categoryID, duration) in maps.byID {
        lastWeekByIDTotals[categoryID, default: 0] += duration
      }
      for (categoryName, duration) in maps.byName {
        lastWeekByNameTotals[categoryName, default: 0] += duration
      }
    }

    let dayCount = max(Double(dayStrings.count), 1)
    return DayGoalSetupReferenceStats(
      yesterdayByCategoryID: yesterdayMaps.byID,
      yesterdayByCategoryName: yesterdayMaps.byName,
      lastWeekAverageByCategoryID: lastWeekByIDTotals.mapValues { $0 / dayCount },
      lastWeekAverageByCategoryName: lastWeekByNameTotals.mapValues { $0 / dayCount }
    )
  }

  private static func categoryDurationMaps(
    forDay dayString: String,
    storageManager: StorageManaging,
    categories: [TimelineCategory]
  ) -> (byID: [String: TimeInterval], byName: [String: TimeInterval]) {
    let cards = storageManager.fetchTimelineCards(forDay: dayString)
    let precomputed = precomputeCardDurations(cards)
    let categoryDurations = computeCategoryDurations(from: precomputed, categories: categories)
    return durationMaps(from: categoryDurations)
  }

  private static func durationMaps(
    from categoryDurations: [CategoryTimeData]
  ) -> (byID: [String: TimeInterval], byName: [String: TimeInterval]) {
    var byID: [String: TimeInterval] = [:]
    var byName: [String: TimeInterval] = [:]
    for item in categoryDurations {
      byID[item.id, default: 0] += item.duration
      byName[normalizedCategoryName(item.name), default: 0] += item.duration
    }
    return (byID, byName)
  }

  static func carriedForwardGoalPlan(
    day: String,
    storageManager: StorageManaging,
    categories: [TimelineCategory]
  ) -> DayGoalPlan {
    let saved = storageManager.fetchMostRecentDayGoalPlan(beforeOrOn: day)
    let plan = saved ?? DayGoalPlan.defaultPlan(day: day, categories: categories)
    return plan.carriedForward(to: day, categories: categories)
  }

  private static func timelineMinute(fromClockMinutes minutes: Int) -> Int {
    if minutes >= timelineDayStartMinutes {
      return minutes - timelineDayStartMinutes
    }
    return minutes + (minutesPerDay - timelineDayStartMinutes)
  }

  private static func clockMinute(fromTimelineMinute minute: Int) -> Int {
    (minute + timelineDayStartMinutes) % minutesPerDay
  }

  private static func timelineRanges(for window: DayFocusWindow) -> [Range<Int>] {
    guard window.isValid else { return [] }
    var ranges: [Range<Int>] = []
    var start: Int?

    for minute in 0..<minutesPerDay {
      let contains = windowContainsTimelineMinute(window, minute: minute)
      if contains {
        if start == nil {
          start = minute
        }
      } else if let rangeStart = start {
        ranges.append(rangeStart..<minute)
        start = nil
      }
    }

    if let start {
      ranges.append(start..<minutesPerDay)
    }
    return ranges
  }

  private static func windowContainsTimelineMinute(_ window: DayFocusWindow, minute: Int) -> Bool {
    let clockMinute = clockMinute(fromTimelineMinute: minute)
    if window.endMinutes > window.startMinutes {
      return clockMinute >= window.startMinutes && clockMinute < window.endMinutes
    }
    return clockMinute >= window.startMinutes || clockMinute < window.endMinutes
  }

  private static func mergeFocusSegments(_ segments: [FocusWindowSegment]) -> [FocusWindowSegment] {
    guard segments.count > 1 else { return segments }
    let sorted = segments.sorted { lhs, rhs in
      if lhs.startMinutes == rhs.startMinutes {
        return lhs.endMinutes < rhs.endMinutes
      }
      return lhs.startMinutes < rhs.startMinutes
    }
    var merged: [FocusWindowSegment] = []

    for segment in sorted {
      guard var last = merged.last else {
        merged.append(segment)
        continue
      }
      if last.windowID == segment.windowID,
        last.categoryName == segment.categoryName,
        last.isOnPlan == segment.isOnPlan,
        last.endMinutes == segment.startMinutes
      {
        last = FocusWindowSegment(
          id: last.id,
          windowID: last.windowID,
          windowLabel: last.windowLabel,
          windowStartMinutes: last.windowStartMinutes,
          windowEndMinutes: last.windowEndMinutes,
          startMinutes: last.startMinutes,
          endMinutes: segment.endMinutes,
          categoryName: last.categoryName,
          isOnPlan: last.isOnPlan,
          isDrift: last.isDrift
        )
        merged[merged.count - 1] = last
      } else {
        merged.append(segment)
      }
    }

    return merged
  }

  private static func deriveAttentionState(
    works: [FocusWindowWork],
    recoveryEvents: [DayRecoveryEvent],
    referenceTimelineMinute: Int?
  ) -> (state: AttentionGradientState?, message: String) {
    guard let referenceTimelineMinute else {
      return (nil, "No recent focus context yet.")
    }

    let recentStart = max(0, referenceTimelineMinute - 30)
    let allSegments = works.flatMap(\.segments)
    let recentSegments = allSegments.compactMap { segment -> FocusWindowSegment? in
      let overlapStart = max(segment.startMinutes, recentStart)
      let overlapEnd = min(segment.endMinutes, referenceTimelineMinute)
      guard overlapEnd > overlapStart else { return nil }
      return FocusWindowSegment(
        id: segment.id,
        windowID: segment.windowID,
        windowLabel: segment.windowLabel,
        windowStartMinutes: segment.windowStartMinutes,
        windowEndMinutes: segment.windowEndMinutes,
        startMinutes: overlapStart,
        endMinutes: overlapEnd,
        categoryName: segment.categoryName,
        isOnPlan: segment.isOnPlan,
        isDrift: segment.isDrift
      )
    }

    guard recentSegments.isEmpty == false else {
      return (nil, "No recent focus context yet.")
    }

    let onPlanMinutes = recentSegments.filter { $0.isOnPlan }.reduce(0) {
      $0 + ($1.endMinutes - $1.startMinutes)
    }
    let driftMinutes = recentSegments.filter { $0.isDrift }.reduce(0) {
      $0 + ($1.endMinutes - $1.startMinutes)
    }
    let switches = zip(recentSegments, recentSegments.dropFirst()).reduce(0) { total, pair in
      total + (pair.0.categoryName != pair.1.categoryName ? 1 : 0)
    }
    if let recentRecovery = recoveryEvents
      .filter({ $0.recovered })
      .sorted(by: { ($0.recoveryStartMinutes ?? Int.max) > ($1.recoveryStartMinutes ?? Int.max) })
      .first,
      let recoveryStart = recentRecovery.recoveryStartMinutes,
      referenceTimelineMinute >= recoveryStart,
      (referenceTimelineMinute - recoveryStart) <= 10
    {
      let ago = max(0, referenceTimelineMinute - recoveryStart)
      return (
        .reEntry,
        "You're in Re-entry: focus resumed after drift \(ago) min ago."
      )
    }
    if onPlanMinutes >= 25 && driftMinutes <= 2 {
      return (.lockedIn, "You're in Locked In: planned work held steady for the last \(onPlanMinutes) min.")
    }
    if driftMinutes >= max(12, onPlanMinutes) {
      return (.wandering, "You're in Wandering: recent activity drifted away from the current focus block.")
    }
    if switches >= 3 {
      return (.friction, "You're in Friction: recent work kept switching before settling.")
    }
    if onPlanMinutes > 0 {
      return (.steady, "You're in Steady: recent work is mostly aligned with the current plan.")
    }
    return (.wandering, "You're in Wandering: there is not enough on-plan focus in the last 30 minutes.")
  }

  private static func formatClockTime(_ minutes: Int) -> String {
    let clamped = ((minutes % minutesPerDay) + minutesPerDay) % minutesPerDay
    let hour24 = clamped / 60
    let minute = clamped % 60
    let period = hour24 >= 12 ? "PM" : "AM"
    let hour12 = hour24 == 0 ? 12 : (hour24 > 12 ? hour24 - 12 : hour24)
    return String(format: "%d:%02d %@", hour12, minute, period)
  }

  private static func displayName(
    forNormalizedCategory normalized: String,
    categories: [TimelineCategory]
  ) -> String {
    categories.first(where: { normalizedCategoryName($0.name) == normalized })?.name
      ?? normalized.capitalized
  }

  private static func goalCategoryResults(
    snapshots: [DayGoalCategorySnapshot],
    categoryDurations: [CategoryTimeData],
    categories: [TimelineCategory]
  ) -> [DayGoalCategoryResult] {
    let currentByID = Dictionary(uniqueKeysWithValues: categories.map { ($0.id.uuidString, $0) })
    let durationByID = categoryDurations.reduce(into: [String: TimeInterval]()) { result, item in
      result[item.id] = item.duration
    }
    let durationByName = categoryDurations.reduce(into: [String: TimeInterval]()) { result, item in
      result[normalizedCategoryName(item.name)] = item.duration
    }

    return
      snapshots
      .sorted { $0.sortOrder < $1.sortOrder }
      .map { snapshot in
        let current = currentByID[snapshot.categoryID]
        let name = current?.name ?? snapshot.name
        let colorHex = current?.colorHex ?? snapshot.colorHex
        let duration =
          durationByID[snapshot.categoryID]
          ?? durationByName[normalizedCategoryName(snapshot.name), default: 0]

        return DayGoalCategoryResult(
          id: snapshot.categoryID,
          name: name,
          colorHex: colorHex,
          duration: duration
        )
      }
  }

  private enum ReviewRatingKey: String {
    case distracted
    case neutral
    case focused
  }

  static func makeReviewSummary(
    segments: [TimelineReviewRatingSegment],
    dayStartTs: Int,
    dayEndTs: Int
  ) -> TimelineReviewSummarySnapshot {
    var durationByRating: [ReviewRatingKey: TimeInterval] = [
      .distracted: 0,
      .neutral: 0,
      .focused: 0,
    ]
    var latestEnd: Int? = nil

    for segment in segments {
      let start = max(segment.startTs, dayStartTs)
      let end = min(segment.endTs, dayEndTs)
      guard end > start else { continue }

      let normalized = segment.rating
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .lowercased()

      guard let rating = ReviewRatingKey(rawValue: normalized) else { continue }

      durationByRating[rating, default: 0] += TimeInterval(end - start)
      latestEnd = max(latestEnd ?? end, end)
    }

    let total = durationByRating.values.reduce(0, +)
    guard total > 0 else {
      return .placeholder
    }

    let distractedRatio = durationByRating[.distracted, default: 0] / total
    let neutralRatio = durationByRating[.neutral, default: 0] / total
    let productiveRatio = durationByRating[.focused, default: 0] / total

    return TimelineReviewSummarySnapshot(
      hasData: true,
      lastReviewedAt: latestEnd.map { Date(timeIntervalSince1970: TimeInterval($0)) },
      distractedRatio: distractedRatio,
      neutralRatio: neutralRatio,
      productiveRatio: productiveRatio,
      distractedDuration: durationByRating[.distracted, default: 0],
      neutralDuration: durationByRating[.neutral, default: 0],
      productiveDuration: durationByRating[.focused, default: 0]
    )
  }
}
