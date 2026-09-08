import XCTest

@testable import Dayflow

final class DayReviewAnswerServiceTests: XCTestCase {
  func testFinishedFallbackDoesNotInferCompletionFromCapture() {
    let answer = DayReviewAnswerService.localAnswer(
      question: DayReviewPrompt.finished.question,
      cards: [],
      tasks: [task("Write brief", status: .planned)],
      captures: [capture("Wrote notes for the brief")]
    )

    XCTAssertTrue(answer.contains("No tasks are marked done."))
    XCTAssertTrue(answer.contains("Manual captures: 1."))
  }

  func testRemainingFallbackListsOnlyOpenTasks() {
    let answer = DayReviewAnswerService.localAnswer(
      question: DayReviewPrompt.remaining.question,
      cards: [],
      tasks: [task("Send proposal", status: .planned), task("Archive notes", status: .done)],
      captures: []
    )

    XCTAssertTrue(answer.contains("Send proposal"))
    XCTAssertFalse(answer.contains("Archive notes"))
  }

  func testNextFallbackRequiresMatchingEvidence() {
    let answer = DayReviewAnswerService.localAnswer(
      question: DayReviewPrompt.next.question,
      cards: [],
      tasks: [task("Prepare proposal", status: .planned)],
      captures: [capture("Prepared a proposal outline")]
    )

    XCTAssertTrue(answer.contains("Next: Prepare proposal."))
    XCTAssertTrue(answer.contains("matching activity"))
  }

  func testRecommendedTaskPrefersOpenTaskWithMatchingEvidence() {
    let recommended = DayReviewAnswerService.recommendedTask(
      from: [task("Prepare proposal", status: .planned), task("Archive receipts", status: .planned)],
      cards: [],
      captures: [capture("Prepared a proposal outline")]
    )

    XCTAssertEqual(recommended?.title, "Prepare proposal")
  }

  func testNextFallbackDoesNotChooseWithoutEvidence() {
    let answer = DayReviewAnswerService.localAnswer(
      question: DayReviewPrompt.next.question,
      cards: [],
      tasks: [task("Prepare proposal", status: .planned)],
      captures: []
    )

    XCTAssertTrue(answer.contains("not enough same-day evidence"))
  }

  private func task(_ title: String, status: DayflowTaskStatus) -> DayflowTask {
    DayflowTask(id: UUID(), title: title, status: status, createdDay: "2026-09-08", plannedDay: "2026-09-08", categoryID: nil, projectName: nil, estimateMinutes: nil, notes: "", createdAt: 0, updatedAt: 0, completedAt: nil)
  }

  private func capture(_ body: String) -> ManualCapture {
    ManualCapture(id: UUID(), day: "2026-09-08", body: body, kind: .note, startTs: nil, endTs: nil, categoryID: nil, projectName: nil, taskID: nil, source: .review, sourcePayload: nil, createdAt: 0, updatedAt: 0)
  }
}
