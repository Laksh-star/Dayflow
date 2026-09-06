import XCTest

@testable import Dayflow

@MainActor
final class VoiceCapabilityServiceTests: XCTestCase {
  func testMergedTranscriptUsesCumulativeRecognitionResult() {
    let merged = VoiceCapabilityService.mergedTranscript(
      existing: "Today I reviewed the proposal",
      incoming: "Today I reviewed the proposal and sent feedback"
    )

    XCTAssertEqual(merged, "Today I reviewed the proposal and sent feedback")
  }

  func testMergedTranscriptAppendsFreshSegmentAfterNaturalPause() {
    let merged = VoiceCapabilityService.mergedTranscript(
      existing: "Today I reviewed the proposal.",
      incoming: "Then I drafted the follow-up."
    )

    XCTAssertEqual(merged, "Today I reviewed the proposal. Then I drafted the follow-up.")
  }

  func testMergedTranscriptDoesNotDiscardPriorTextOnPartialRegression() {
    let merged = VoiceCapabilityService.mergedTranscript(
      existing: "Today I reviewed the proposal and sent feedback",
      incoming: "Today I reviewed the proposal"
    )

    XCTAssertEqual(merged, "Today I reviewed the proposal and sent feedback")
  }

  func testMergedTranscriptRemovesBoundaryOverlap() {
    let merged = VoiceCapabilityService.mergedTranscript(
      existing: "I reviewed the proposal",
      incoming: "proposal before lunch"
    )

    XCTAssertEqual(merged, "I reviewed the proposal before lunch")
  }
}
