import Foundation

enum AttentionGradientState: String, CaseIterable, Sendable {
  case friction
  case wandering
  case reEntry = "re_entry"
  case steady
  case lockedIn = "locked_in"

  var title: String {
    switch self {
    case .friction: return "Friction"
    case .wandering: return "Wandering"
    case .reEntry: return "Re-entry"
    case .steady: return "Steady"
    case .lockedIn: return "Locked In"
    }
  }

  var explanation: String {
    switch self {
    case .friction:
      return "You are switching or hesitating before settling into the next block."
    case .wandering:
      return "Recent activity drifted away from the planned focus path."
    case .reEntry:
      return "You returned to planned work after a drift segment."
    case .steady:
      return "Recent activity is stable and aligned with your planned work."
    case .lockedIn:
      return "You have sustained planned focus long enough to be in a strong flow."
    }
  }
}

struct DayFocusWindow: Identifiable, Equatable, Sendable {
  var id: String
  var day: String
  var startMinutes: Int
  var endMinutes: Int
  var label: String
  var focusCategoryIDs: [String]
  var createdAt: Int
  var updatedAt: Int

  init(
    id: String = UUID().uuidString,
    day: String,
    startMinutes: Int,
    endMinutes: Int,
    label: String = "",
    focusCategoryIDs: [String],
    createdAt: Int = 0,
    updatedAt: Int = 0
  ) {
    self.id = id
    self.day = day
    self.startMinutes = min(max(0, startMinutes), 24 * 60)
    self.endMinutes = min(max(0, endMinutes), 24 * 60)
    self.label = label
    self.focusCategoryIDs = focusCategoryIDs
    self.createdAt = createdAt
    self.updatedAt = updatedAt
  }

  var durationMinutes: Int {
    max(0, endMinutes - startMinutes)
  }

  var isValid: Bool {
    endMinutes > startMinutes
  }

  func forDay(_ day: String, fallbackCategoryIDs: [String]) -> DayFocusWindow {
    var copy = self
    if copy.day != day {
      copy.createdAt = 0
      copy.updatedAt = 0
    }
    copy.day = day
    copy.focusCategoryIDs = copy.resolvedCategoryIDs(fallbackCategoryIDs: fallbackCategoryIDs)
    return copy
  }

  func resolvedCategoryIDs(fallbackCategoryIDs: [String]) -> [String] {
    let fallback = Array(NSOrderedSet(array: fallbackCategoryIDs)) as? [String] ?? fallbackCategoryIDs
    if focusCategoryIDs.isEmpty {
      return fallback
    }
    let available = Set(fallback)
    let filtered = focusCategoryIDs.filter { available.contains($0) }
    if filtered.isEmpty, !fallback.isEmpty {
      return fallback
    }
    return filtered
  }

  static func defaultWindow(day: String, index: Int, focusCategoryIDs: [String]) -> DayFocusWindow {
    let startMinutes = min(18 * 60, (5 * 60) + (index * 90))
    let endMinutes = min(24 * 60, startMinutes + 120)
    let defaultLabel = "Focus block \(index + 1)"
    let now = Int(Date().timeIntervalSince1970)
    return DayFocusWindow(
      day: day,
      startMinutes: startMinutes,
      endMinutes: endMinutes,
      label: defaultLabel,
      focusCategoryIDs: focusCategoryIDs,
      createdAt: now,
      updatedAt: now
    )
  }
}

struct DayRecoveryAnnotation: Equatable, Sendable {
  var eventID: String
  var day: String
  var startTs: Int
  var endTs: Int
  var triggerCategory: String
  var recoveryCategory: String
  var pullReason: String
  var returnReason: String
  var createdAt: Int
  var updatedAt: Int
}

struct DayRecoveryEvent: Identifiable, Equatable, Sendable {
  var id: String
  var day: String
  var windowID: String
  var windowLabel: String
  var windowStartMinutes: Int
  var windowEndMinutes: Int
  var driftStartMinutes: Int
  var driftEndMinutes: Int
  var recoveryStartMinutes: Int?
  var recoveryEndMinutes: Int?
  var triggerCategory: String
  var recoveryCategory: String?
  var driftMinutes: Int
  var recovered: Bool
}

struct PlanVsDriftWindowSnapshot: Identifiable, Equatable, Sendable {
  var id: String
  var label: String
  var startMinutes: Int
  var endMinutes: Int
  var plannedMinutes: Int
  var onPlanMinutes: Int
  var driftMinutes: Int
  var recoveryCount: Int
}

struct DayFocusDriftSnapshot: Equatable, Sendable {
  var plannedMinutes: Int
  var onPlanMinutes: Int
  var driftMinutes: Int
  var recoveryCount: Int
  var driftRatio: Double
  var averageRecoveryMinutes: Int?
  var fastestRecoveryMinutes: Int?
  var unresolvedRecoveryCount: Int
  var mostCommonDriftCategories: [String]
  var windows: [PlanVsDriftWindowSnapshot]
  var recoveryEvents: [DayRecoveryEvent]
  var attentionState: AttentionGradientState?
  var attentionMessage: String

  static let empty = DayFocusDriftSnapshot(
    plannedMinutes: 0,
    onPlanMinutes: 0,
    driftMinutes: 0,
    recoveryCount: 0,
    driftRatio: 0,
    averageRecoveryMinutes: nil,
    fastestRecoveryMinutes: nil,
    unresolvedRecoveryCount: 0,
    mostCommonDriftCategories: [],
    windows: [],
    recoveryEvents: [],
    attentionState: nil,
    attentionMessage: "Add focus windows to compare planned work against drift."
  )
}
