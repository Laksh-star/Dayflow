import Foundation

enum PersonalAssistantMarkdown {
  static func append(to base: String, tasks: [DayflowTask], captures: [ManualCapture], decisions: [DayReviewDecision]) -> String {
    var sections: [String] = [base]
    if !tasks.isEmpty {
      let lines = tasks.map { task in
        let mark = task.status == .done ? "x" : " "
        let estimate = task.estimateMinutes.map { " (\($0)m estimate)" } ?? ""
        return "- [\(mark)] \(task.title)\(estimate)"
      }
      sections.append("## Tasks\n" + lines.joined(separator: "\n"))
    }
    if !captures.isEmpty {
      let lines = captures.map { capture in
        let time = capture.durationMinutes.map { " | \($0)m" } ?? ""
        return "- \(capture.kind.label)\(time) | \(capture.body)"
      }
      sections.append("## Manual captures\n" + lines.joined(separator: "\n"))
    }
    if !decisions.isEmpty {
      let lines = decisions.map { "- \($0.kind.rawValue.replacingOccurrences(of: "_", with: " ").capitalized)" }
      sections.append("## Review decisions\n" + lines.joined(separator: "\n"))
    }
    return sections.joined(separator: "\n\n")
  }
}
