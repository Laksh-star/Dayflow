import XCTest

@testable import Dayflow

@MainActor
final class VoiceCapabilityServiceTests: XCTestCase {
  func testAssemblerReplacesRevisedSegmentAtSameTimestamp() {
    var assembler = VoiceTranscriptAssembler()
    assembler.ingest([segment(0, "Okay I am")])
    assembler.ingest([segment(0, "Okay I'm")])

    XCTAssertEqual(assembler.text, "Okay I'm")
  }

  func testAssemblerPreservesNewSegmentAfterNaturalPause() {
    var assembler = VoiceTranscriptAssembler()
    assembler.ingest([segment(0, "Today I reviewed the proposal."), segment(3.2, "Then I drafted the follow-up.")])

    XCTAssertEqual(assembler.text, "Today I reviewed the proposal. Then I drafted the follow-up.")
  }

  func testAssemblerDoesNotDuplicateRepeatedPartialResults() {
    var assembler = VoiceTranscriptAssembler()
    let partial = [segment(0, "Okay"), segment(0.4, "I"), segment(0.8, "am")]
    assembler.ingest(partial)
    assembler.ingest(partial)

    XCTAssertEqual(assembler.text, "Okay I am")
  }

  func testAssemblerKeepsChronologicalOrderWhenResultsArriveOutOfOrder() {
    var assembler = VoiceTranscriptAssembler()
    assembler.ingest([segment(1.0, "later")])
    assembler.ingest([segment(0.0, "earlier")])

    XCTAssertEqual(assembler.text, "earlier later")
  }

  private func segment(_ start: TimeInterval, _ text: String) -> VoiceTranscriptSegment {
    VoiceTranscriptSegment(start: start, duration: 0.25, text: text)
  }
}
