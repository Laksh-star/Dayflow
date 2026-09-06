import Foundation

enum DayflowTaskStatus: String, CaseIterable, Codable, Sendable {
  case inbox
  case planned
  case inProgress = "in_progress"
  case done
  case deferred
  case dropped

  var label: String {
    switch self {
    case .inbox: return "Inbox"
    case .planned: return "Planned"
    case .inProgress: return "In progress"
    case .done: return "Done"
    case .deferred: return "Deferred"
    case .dropped: return "Dropped"
    }
  }
}

enum ManualCaptureKind: String, CaseIterable, Codable, Sendable {
  case offlineWork = "offline_work"
  case meeting
  case personal
  case note

  var label: String {
    switch self {
    case .offlineWork: return "Offline work"
    case .meeting: return "Meeting"
    case .personal: return "Personal"
    case .note: return "Note"
    }
  }
}

enum ManualCaptureSource: String, Codable, Sendable {
  case desktop
  case mobileShortcut = "mobile_shortcut"
  case review
  case conversation
}

struct DayflowTask: Identifiable, Equatable, Sendable {
  let id: UUID
  var title: String
  var status: DayflowTaskStatus
  let createdDay: String
  var plannedDay: String?
  var categoryID: String?
  var projectName: String?
  var estimateMinutes: Int?
  var notes: String
  let createdAt: Int
  var updatedAt: Int
  var completedAt: Int?
}

struct ManualCapture: Identifiable, Equatable, Sendable {
  let id: UUID
  let day: String
  var body: String
  var kind: ManualCaptureKind
  var startTs: Int?
  var endTs: Int?
  var categoryID: String?
  var projectName: String?
  var taskID: UUID?
  let source: ManualCaptureSource
  var sourcePayload: String?
  let createdAt: Int
  var updatedAt: Int

  var durationMinutes: Int? {
    guard let startTs, let endTs, endTs > startTs else { return nil }
    return Int((Double(endTs - startTs) / 60).rounded())
  }
}

enum DayReviewDecisionKind: String, Codable, Sendable {
  case complete
  case carryForward = "carry_forward"
  case deferTask = "defer"
  case drop
  case linkEvidence = "link_evidence"
  case createTask = "create_task"
  case dismiss
}

struct DayReviewDecision: Identifiable, Equatable, Sendable {
  let id: UUID
  let day: String
  let taskID: UUID?
  let kind: DayReviewDecisionKind
  let payloadJSON: String
  let createdAt: Int
}

struct DayReviewSuggestion: Identifiable, Equatable, Sendable {
  enum Kind: Equatable, Sendable {
    case likelyWork(task: DayflowTask, minutes: Int)
    case carryForward(task: DayflowTask)
    case unlinkedCapture(capture: ManualCapture)
  }

  let id: String
  let kind: Kind
}
