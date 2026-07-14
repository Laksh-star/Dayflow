import XCTest

@testable import Dayflow

final class PrivacyAndProjectRulesTests: XCTestCase {
  func testPrivacyDomainDetectionMatchesUrlInWindowTitle() {
    let defaults = UserDefaults(suiteName: "DayflowTests.PrivacyDomain")!
    defaults.removePersistentDomain(forName: "DayflowTests.PrivacyDomain")
    RecordingPrivacyPreferences.saveBlockedDomains(["mail.google.com"], defaults: defaults)

    let match = RecordingPrivacyPreferences.privacyMatch(
      for: RecordingPrivacyContext(
        applicationName: "Google Chrome",
        bundleIdentifier: "com.google.Chrome",
        windowTitle: "Inbox - https://mail.google.com/mail/u/0/#inbox"
      ),
      defaults: defaults
    )

    XCTAssertEqual(match?.ruleType, .domain)
    XCTAssertEqual(match?.matchedValue, "mail.google.com")
  }

  func testPrivacyPresetAddsExpectedRules() {
    XCTAssertTrue(RecordingPrivacyPreset.gmail.domains.contains("mail.google.com"))
    XCTAssertTrue(RecordingPrivacyPreset.passwordManagers.windowTitleKeywords.contains("passkey"))
  }

  func testProjectSuggestionsUseUntaggedAppSites() {
    let cards = [
      TimelineCard(
        recordId: nil,
        batchId: nil,
        startTimestamp: "9:00 AM",
        endTimestamp: "9:30 AM",
        category: "Engineering",
        subcategory: "Build",
        title: "Implemented API settings",
        summary: "Worked in GitHub",
        detailedSummary: "",
        day: "2026-07-10",
        distractions: nil,
        videoSummaryURL: nil,
        otherVideoSummaryURLs: nil,
        appSites: AppSites(primary: "github.com", secondary: nil)
      )
    ]

    let suggestions = ProjectTaggingService.untaggedSuggestions(for: cards, rules: [])
    XCTAssertTrue(suggestions.contains { $0.pattern == "github.com" })
  }

  func testMobileContextNotesMatchFilenameDate() throws {
    let originalPath = MobileContextSettings.inboxFolderPath
    let tempFolder = FileManager.default.temporaryDirectory
      .appendingPathComponent("DayflowMobileContextTests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: tempFolder, withIntermediateDirectories: true)
    defer {
      MobileContextSettings.inboxFolderPath = originalPath
      try? FileManager.default.removeItem(at: tempFolder)
    }

    MobileContextSettings.inboxFolderPath = tempFolder.path
    let noteURL = tempFolder.appendingPathComponent("2026-07-14-client-call.md")
    try "# Client call\nCaptured from iPhone.".write(to: noteURL, atomically: true, encoding: .utf8)

    let notes = MobileContextService.notes(forDay: "2026-07-14")
    XCTAssertEqual(notes.count, 1)
    XCTAssertEqual(notes.first?.title, "Client call")
  }
}
