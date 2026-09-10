import XCTest

@testable import Dayflow

final class ManualCaptureExportTests: XCTestCase {
  func testManualCaptureTimeIncludesOnlyExplicitRanges() {
    let captures = [
      capture(kind: .offlineWork, start: 100, end: 700),
      capture(kind: .note, start: nil, end: nil),
      capture(kind: .meeting, start: 800, end: 800),
    ]

    XCTAssertEqual(DaySummaryStats.computeManualCaptureTime(from: captures), 600)
  }

  func testTimedMeetingExportsAsSeparateManualTogglRow() {
    let rows = TogglDraftExportService.buildRows(
      from: [],
      manualCaptures: [capture(kind: .meeting, start: 1_725_960_000, end: 1_725_961_800)],
      mappings: [
        TogglProjectMapping(
          dayflowProject: "Meetings",
          keywords: [],
          destination: .togglProject("Consulting")
        )
      ],
      rounding: .exact,
      mode: .detailed,
      includePersonal: false,
      includeDistractions: false
    )

    XCTAssertEqual(rows.count, 1)
    XCTAssertTrue(rows[0].isManual)
    XCTAssertEqual(rows[0].togglProject, "Consulting")
    XCTAssertEqual(rows[0].sourceCountLabel, "1 manual capture")

    let csv = TogglDraftExportService.makeCSV(rows: rows, email: "person@example.com")
    XCTAssertTrue(csv.contains("dayward,manual,meetings"))
  }

  private func capture(kind: ManualCaptureKind, start: Int?, end: Int?) -> ManualCapture {
    ManualCapture(
      id: UUID(), day: "2026-09-10", body: "Client planning meeting", kind: kind,
      startTs: start, endTs: end, categoryID: nil, projectName: nil, taskID: nil,
      source: .review, sourcePayload: nil, createdAt: 0, updatedAt: 0
    )
  }
}
