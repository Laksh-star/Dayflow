import AppKit
import Combine
import Foundation
import UniformTypeIdentifiers

@MainActor
final class OtherSettingsViewModel: ObservableObject {
  @Published var analyticsEnabled: Bool {
    didSet {
      guard analyticsEnabled != oldValue else { return }
      AnalyticsService.shared.setOptIn(analyticsEnabled)
    }
  }
  @Published var showDockIcon: Bool {
    didSet {
      guard showDockIcon != oldValue else { return }
      UserDefaults.standard.set(showDockIcon, forKey: "showDockIcon")
      NSApp.setActivationPolicy(showDockIcon ? .regular : .accessory)
    }
  }
  @Published var showTimelineAppIcons: Bool {
    didSet {
      guard showTimelineAppIcons != oldValue else { return }
      UserDefaults.standard.set(showTimelineAppIcons, forKey: "showTimelineAppIcons")
    }
  }
  @Published var showDailyGoalPopups: Bool {
    didSet {
      guard showDailyGoalPopups != oldValue else { return }
      DayGoalPreferences.showDailyGoalPopups = showDailyGoalPopups
    }
  }
  @Published var saveAllTimelapsesToDisk: Bool {
    didSet {
      guard saveAllTimelapsesToDisk != oldValue else { return }
      TimelapsePreferences.saveAllTimelapsesToDisk = saveAllTimelapsesToDisk
    }
  }
  @Published var outputLanguageOverride: String
  @Published var isOutputLanguageOverrideSaved: Bool = true

  @Published var exportStartDate: Date
  @Published var exportEndDate: Date
  @Published var isExportingTimelineRange = false
  @Published var exportStatusMessage: String?
  @Published var exportErrorMessage: String?
  @Published var togglMappingText: String
  @Published var togglImportEmail: String
  @Published var togglKnownProjectsText: String
  @Published var togglRounding: TogglRounding
  @Published var togglExportMode: TogglExportMode
  @Published var togglIncludePersonal: Bool
  @Published var togglIncludeDistractions: Bool
  @Published var togglDraftRows: [TogglDraftRow] = []
  @Published var togglUnknownProjects: [String] = []
  @Published var togglStatusMessage: String?
  @Published var togglErrorMessage: String?
  @Published var reprocessDayDate: Date
  @Published var isReprocessingDay = false
  @Published var reprocessStatusMessage: String?
  @Published var reprocessErrorMessage: String?
  @Published var showReprocessDayConfirm = false

  init() {
    analyticsEnabled = AnalyticsService.shared.isOptedIn
    showDockIcon = UserDefaults.standard.object(forKey: "showDockIcon") as? Bool ?? true
    showTimelineAppIcons =
      UserDefaults.standard.object(forKey: "showTimelineAppIcons") as? Bool ?? true
    showDailyGoalPopups = DayGoalPreferences.showDailyGoalPopups
    saveAllTimelapsesToDisk = TimelapsePreferences.saveAllTimelapsesToDisk
    outputLanguageOverride = LLMOutputLanguagePreferences.override
    exportStartDate = timelineDisplayDate(from: Date())
    exportEndDate = timelineDisplayDate(from: Date())
    togglMappingText = TogglMappingPreferences.mappingText
    togglImportEmail = TogglMappingPreferences.importEmail
    togglKnownProjectsText = TogglMappingPreferences.knownProjectsText
    togglRounding = TogglMappingPreferences.rounding
    togglExportMode = TogglMappingPreferences.exportMode
    togglIncludePersonal = TogglMappingPreferences.includePersonal
    togglIncludeDistractions = TogglMappingPreferences.includeDistractions
    reprocessDayDate = timelineDisplayDate(from: Date())
    refreshTogglDraft()
  }

  func markOutputLanguageOverrideEdited() {
    let trimmed = outputLanguageOverride.trimmingCharacters(in: .whitespacesAndNewlines)
    let savedValue = LLMOutputLanguagePreferences.override
    isOutputLanguageOverrideSaved = trimmed == savedValue
  }

  func saveOutputLanguageOverride() {
    let trimmed = outputLanguageOverride.trimmingCharacters(in: .whitespacesAndNewlines)
    outputLanguageOverride = trimmed
    LLMOutputLanguagePreferences.override = trimmed
    isOutputLanguageOverrideSaved = true
  }

  func resetOutputLanguageOverride() {
    outputLanguageOverride = ""
    LLMOutputLanguagePreferences.override = ""
    isOutputLanguageOverrideSaved = true
  }

  func refreshAnalyticsState() {
    analyticsEnabled = AnalyticsService.shared.isOptedIn
  }

  func exportTimelineRange() {
    guard !isExportingTimelineRange else { return }

    let start = timelineDisplayDate(from: exportStartDate)
    let end = timelineDisplayDate(from: exportEndDate)

    guard start <= end else {
      exportErrorMessage = "Start date must be on or before end date."
      exportStatusMessage = nil
      return
    }

    isExportingTimelineRange = true
    exportStatusMessage = nil
    exportErrorMessage = nil

    Task.detached(priority: .userInitiated) { [start, end] in
      let calendar = Calendar.current
      let dayFormatter = DateFormatter()
      dayFormatter.dateFormat = "yyyy-MM-dd"

      var cursor = start
      let endDate = end

      var sections: [String] = []
      var totalActivities = 0
      var dayCount = 0

      while cursor <= endDate {
        let dayString = dayFormatter.string(from: cursor)
        let cards = StorageManager.shared.fetchTimelineCards(forDay: dayString)
        totalActivities += cards.count
        let section = TimelineClipboardFormatter.makeMarkdown(for: cursor, cards: cards)
        sections.append(section)
        dayCount += 1

        guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
        cursor = next
      }

      let divider = "\n\n---\n\n"
      let exportText = sections.joined(separator: divider)

      await MainActor.run {
        self.presentSavePanelAndWrite(
          exportText: exportText,
          startDate: start,
          endDate: end,
          dayCount: dayCount,
          activityCount: totalActivities
        )
      }
    }
  }

  func reprocessSelectedDay() {
    guard !isReprocessingDay else { return }

    let normalizedDate = timelineDisplayDate(from: reprocessDayDate)
    let dayString = DateFormatter.yyyyMMdd.string(from: normalizedDate)

    isReprocessingDay = true
    reprocessErrorMessage = nil
    reprocessStatusMessage = "Starting reprocess for \(dayString)…"

    AnalysisManager.shared.reprocessDay(
      dayString,
      progressHandler: { [weak self] message in
        Task { @MainActor in
          self?.reprocessStatusMessage = message
        }
      },
      completion: { [weak self] result in
        Task { @MainActor in
          guard let self else { return }
          switch result {
          case .success:
            if self.reprocessStatusMessage == nil {
              self.reprocessStatusMessage = "Reprocess completed."
            }
          case .failure(let error):
            self.reprocessErrorMessage = error.localizedDescription
          }
          self.isReprocessingDay = false
        }
      })
  }

  func saveTogglMappings() {
    TogglMappingPreferences.mappingText = togglMappingText
    TogglMappingPreferences.importEmail = togglImportEmail
    TogglMappingPreferences.knownProjectsText = togglKnownProjectsText
    TogglMappingPreferences.rounding = togglRounding
    TogglMappingPreferences.exportMode = togglExportMode
    TogglMappingPreferences.includePersonal = togglIncludePersonal
    TogglMappingPreferences.includeDistractions = togglIncludeDistractions
    refreshTogglDraft()
  }

  func resetTogglMappings() {
    togglMappingText = TogglMappingPreferences.defaultMappingText
    togglKnownProjectsText = TogglMappingPreferences.knownProjectsText
    saveTogglMappings()
  }

  func refreshTogglDraft() {
    togglErrorMessage = nil
    togglStatusMessage = nil

    let start = timelineDisplayDate(from: exportStartDate)
    let end = timelineDisplayDate(from: exportEndDate)
    guard start <= end else {
      togglDraftRows = []
      togglErrorMessage = "Start date must be on or before end date."
      return
    }

    let mappings = TogglMappingParser.parse(togglMappingText)
    let knownProjects = TogglProjectCatalog.parse(togglKnownProjectsText)
    let cards = timelineCards(from: start, through: end)
    let previousRows = togglDraftRows.reduce(into: [String: TogglDraftRow]()) { rows, row in
      rows[row.reviewKey] = row
    }
    togglDraftRows = TogglDraftExportService.buildRows(
      from: cards,
      mappings: mappings,
      rounding: togglRounding,
      mode: togglExportMode,
      includePersonal: togglIncludePersonal,
      includeDistractions: togglIncludeDistractions
    ).map { generatedRow in
      guard let previousRow = previousRows[generatedRow.reviewKey] else { return generatedRow }
      var row = generatedRow
      row.description = previousRow.description
      row.togglProject = previousRow.togglProject
      row.isIncluded = previousRow.isIncluded && generatedRow.skippedReason == nil
      return row
    }

    togglUnknownProjects = TogglProjectCatalog.unknownProjects(
      rows: togglDraftRows,
      knownProjects: knownProjects
    )

    let exportableCount = togglDraftRows.filter { !$0.isSkipped }.count
    let skippedCount = togglDraftRows.count - exportableCount
    let baseStatus =
      "\(exportableCount) exportable entr\(exportableCount == 1 ? "y" : "ies"), \(skippedCount) skipped."
    if togglUnknownProjects.isEmpty {
      togglStatusMessage = baseStatus
    } else {
      togglStatusMessage = nil
      togglErrorMessage =
        "Unknown Toggl projects: \(togglUnknownProjects.joined(separator: ", ")). Add them to Known Toggl projects or update the mappings before export."
    }
  }

  func exportTogglDraftCSV() {
    saveTogglMappings()

    let exportableRows = togglDraftRows.filter { !$0.isSkipped }
    guard !exportableRows.isEmpty else {
      togglErrorMessage = "No exportable Toggl rows for this range."
      return
    }
    let email = togglImportEmail.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !email.isEmpty else {
      togglErrorMessage = "Enter the Toggl account email used for CSV imports."
      return
    }
    guard togglUnknownProjects.isEmpty else {
      togglErrorMessage =
        "Export blocked. Unknown Toggl projects: \(togglUnknownProjects.joined(separator: ", "))."
      return
    }

    let csv = TogglDraftExportService.makeCSV(rows: exportableRows, email: email)
    presentTogglSavePanelAndWrite(csv)
  }

  @MainActor
  private func presentSavePanelAndWrite(
    exportText: String,
    startDate: Date,
    endDate: Date,
    dayCount: Int,
    activityCount: Int
  ) {
    let dayFormatter = DateFormatter()
    dayFormatter.dateFormat = "yyyy-MM-dd"

    let savePanel = NSSavePanel()
    savePanel.title = "Export timeline"
    savePanel.prompt = "Export"
    savePanel.nameFieldStringValue =
      "Dayflow timeline \(dayFormatter.string(from: startDate)) to \(dayFormatter.string(from: endDate)).md"
    savePanel.allowedContentTypes = [.text, .plainText]
    savePanel.canCreateDirectories = true

    let response = savePanel.runModal()

    defer { isExportingTimelineRange = false }

    guard response == .OK, let url = savePanel.url else {
      exportStatusMessage = nil
      exportErrorMessage = "Export canceled"
      return
    }

    do {
      try exportText.write(to: url, atomically: true, encoding: .utf8)
      exportErrorMessage = nil
      exportStatusMessage =
        "Saved \(activityCount) activit\(activityCount == 1 ? "y" : "ies") across \(dayCount) day\(dayCount == 1 ? "" : "s") to \(url.lastPathComponent)"

      AnalyticsService.shared.capture(
        "timeline_exported",
        [
          "start_day": dayFormatter.string(from: startDate),
          "end_day": dayFormatter.string(from: endDate),
          "day_count": dayCount,
          "activity_count": activityCount,
          "format": "markdown",
          "file_extension": url.pathExtension.lowercased(),
        ])
    } catch {
      exportStatusMessage = nil
      exportErrorMessage = "Couldn't save file: \(error.localizedDescription)"
    }
  }

  private func timelineCards(from start: Date, through end: Date) -> [TimelineCard] {
    let calendar = Calendar.current
    let dayFormatter = DateFormatter()
    dayFormatter.dateFormat = "yyyy-MM-dd"

    var cursor = start
    var cards: [TimelineCard] = []
    while cursor <= end {
      cards.append(contentsOf: StorageManager.shared.fetchTimelineCards(forDay: dayFormatter.string(from: cursor)))
      guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
      cursor = next
    }
    return cards
  }

  private func presentTogglSavePanelAndWrite(_ csv: String) {
    let dayFormatter = DateFormatter()
    dayFormatter.dateFormat = "yyyy-MM-dd"
    let start = timelineDisplayDate(from: exportStartDate)
    let end = timelineDisplayDate(from: exportEndDate)

    let savePanel = NSSavePanel()
    savePanel.title = "Export Toggl draft"
    savePanel.prompt = "Export"
    savePanel.nameFieldStringValue =
      "Dayflow Toggl draft \(dayFormatter.string(from: start)) to \(dayFormatter.string(from: end)).csv"
    savePanel.allowedContentTypes = [.commaSeparatedText]
    savePanel.canCreateDirectories = true

    let response = savePanel.runModal()
    guard response == .OK, let url = savePanel.url else {
      togglStatusMessage = nil
      togglErrorMessage = "Toggl export canceled"
      return
    }

    do {
      try csv.write(to: url, atomically: true, encoding: .utf8)
      togglErrorMessage = nil
      togglStatusMessage = "Saved Toggl draft to \(url.lastPathComponent)"
      AnalyticsService.shared.capture(
        "toggl_draft_exported",
        [
          "row_count": togglDraftRows.filter { !$0.isSkipped }.count,
          "skipped_count": togglDraftRows.filter(\.isSkipped).count,
          "rounding": togglRounding.rawValue,
          "mode": togglExportMode.rawValue,
        ])
    } catch {
      togglStatusMessage = nil
      togglErrorMessage = "Couldn't save Toggl draft: \(error.localizedDescription)"
    }
  }
}
