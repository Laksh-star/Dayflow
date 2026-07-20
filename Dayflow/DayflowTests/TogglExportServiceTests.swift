import XCTest

@testable import Dayflow

final class TogglExportServiceTests: XCTestCase {
  func testDraftEntriesSkipProcessingFailedCards() {
    let cards = [
      makeCard(
        recordId: 1,
        start: "9:00 AM",
        end: "9:15 AM",
        title: "Processing failed",
        category: "System",
        summary: "Failed to process recording."
      ),
      makeCard(
        recordId: 2,
        start: "9:15 AM",
        end: "9:45 AM",
        title: "Dayflow export cleanup",
        category: "Engineering / Product",
        summary: "Worked on dayflow export mappings."
      ),
    ]

    let drafts = TogglExportService.draftEntries(
      from: cards,
      projects: [],
      rules: [ProjectTaggingRule(id: "dayflow", project: "Dayflow", patterns: ["dayflow"])],
      projectMappings: []
    )

    XCTAssertEqual(drafts.count, 1)
    XCTAssertEqual(drafts.first?.sourceTitle, "Dayflow export cleanup")
    XCTAssertEqual(drafts.first?.sourceProject, "Dayflow")
  }

  func testDraftEntriesConsolidateAdjacentCardsByProject() {
    let cards = [
      makeCard(
        recordId: 1,
        start: "9:00 AM",
        end: "9:20 AM",
        title: "Dayflow retry cleanup",
        summary: "Worked on dayflow processing repair."
      ),
      makeCard(
        recordId: 2,
        start: "9:25 AM",
        end: "9:45 AM",
        title: "Dayflow Toggl export",
        summary: "Refined dayflow Toggl export consolidation."
      ),
      makeCard(
        recordId: 3,
        start: "10:20 AM",
        end: "10:40 AM",
        title: "Coding notes review",
        summary: "Reviewed coding notes in Xcode."
      ),
    ]

    let drafts = TogglExportService.draftEntries(
      from: cards,
      projects: [],
      rules: [
        ProjectTaggingRule(id: "dayflow", project: "Dayflow", patterns: ["dayflow"]),
        ProjectTaggingRule(id: "coding", project: "Coding", patterns: ["coding", "xcode"]),
      ],
      projectMappings: []
    )

    XCTAssertEqual(drafts.count, 2)
    XCTAssertEqual(drafts[0].sourceProject, "Dayflow")
    XCTAssertEqual(drafts[0].durationMinutes, 45)
    XCTAssertEqual(drafts[0].cardRecordId, nil)
    XCTAssertTrue(drafts[0].description.hasPrefix("Dayflow: "))
    XCTAssertTrue(drafts[0].description.contains("Dayflow retry cleanup"))
    XCTAssertTrue(drafts[0].description.contains("Dayflow Toggl export"))

    XCTAssertEqual(drafts[1].sourceProject, "Coding")
    XCTAssertEqual(drafts[1].durationMinutes, 20)
    XCTAssertEqual(drafts[1].cardRecordId, 3)
  }

  private func makeCard(
    recordId: Int64,
    start: String,
    end: String,
    title: String,
    category: String = "Engineering / Product",
    summary: String = "Worked on Dayflow.",
    day: String = "2026-07-19"
  ) -> TimelineCard {
    TimelineCard(
      recordId: recordId,
      batchId: nil,
      startTimestamp: start,
      endTimestamp: end,
      category: category,
      subcategory: "",
      title: title,
      summary: summary,
      detailedSummary: summary,
      day: day,
      distractions: nil,
      videoSummaryURL: nil,
      otherVideoSummaryURLs: nil,
      appSites: nil
    )
  }
}
