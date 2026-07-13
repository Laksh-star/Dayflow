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
  @Published var projectRulesText: String
  @Published var isProjectRulesSaved = true
  @Published var projectRollups: [ProjectTimeRollup] = []
  @Published var projectRuleSuggestions: [ProjectRuleSuggestion] = []
  @Published var projectRollupStatusMessage: String?
  @Published var togglAPITokenText: String
  @Published var togglWorkspaceIDText: String
  @Published var togglProjectMappingsText: String
  @Published var togglProjects: [TogglProject] = []
  @Published var togglDraftEntries: [TogglExportDraftEntry] = []
  @Published var isTogglSettingsSaved = true
  @Published var isTogglProjectMappingsSaved = true
  @Published var isLoadingTogglProjects = false
  @Published var isPreparingTogglDraft = false
  @Published var isSubmittingTogglEntries = false
  @Published var togglStatusMessage: String?
  @Published var togglErrorMessage: String?
  @Published var showSubmitTogglConfirm = false

  @Published var exportStartDate: Date
  @Published var exportEndDate: Date
  @Published var isExportingTimelineRange = false
  @Published var exportStatusMessage: String?
  @Published var exportErrorMessage: String?
  @Published var reprocessDayDate: Date
  @Published var isReprocessingDay = false
  @Published var reprocessStatusMessage: String?
  @Published var reprocessErrorMessage: String?
  @Published var showReprocessDayConfirm = false
  @Published var repairSummary: FailedBatchRepairSummary?
  @Published var isRefreshingRepairSummary = false
  @Published var isDedupingFailedCards = false
  @Published var isRetryingFailedBatches = false
  @Published var repairStatusMessage: String?
  @Published var repairErrorMessage: String?
  @Published var showRetryFailedBatchesConfirm = false
  @Published var repairProviderOverrideId = "current"
  @Published var repairModelOverrideText = ""

  var repairProviderOverrideSupportsModel: Bool {
    repairProviderOverrideId == OpenAICompatibleProviderSettings.providerID
      || repairProviderOverrideId == LLMProviderID.gemini.rawValue
  }

  var repairProviderOverrideLabel: String {
    switch repairProviderOverrideId {
    case "current":
      return "current provider"
    case OpenAICompatibleProviderSettings.providerID:
      return "API"
    case LLMProviderID.gemini.rawValue:
      return "Gemini"
    case "chatgpt_codex":
      return "ChatGPT CLI"
    case "chatgpt_claude":
      return "Claude CLI"
    case LLMProviderID.ollama.rawValue:
      return "Local"
    default:
      return "selected provider"
    }
  }

  init() {
    analyticsEnabled = AnalyticsService.shared.isOptedIn
    showDockIcon = UserDefaults.standard.object(forKey: "showDockIcon") as? Bool ?? true
    showTimelineAppIcons =
      UserDefaults.standard.object(forKey: "showTimelineAppIcons") as? Bool ?? true
    showDailyGoalPopups = DayGoalPreferences.showDailyGoalPopups
    saveAllTimelapsesToDisk = TimelapsePreferences.saveAllTimelapsesToDisk
    outputLanguageOverride = LLMOutputLanguagePreferences.override
    projectRulesText = ProjectTaggingService.rulesText
    togglAPITokenText = TogglExportSettings.loadAPIToken()
    togglWorkspaceIDText = TogglExportSettings.workspaceID
    togglProjectMappingsText = TogglExportSettings.projectMappingsText
    exportStartDate = timelineDisplayDate(from: Date())
    exportEndDate = timelineDisplayDate(from: Date())
    reprocessDayDate = timelineDisplayDate(from: Date())
    refreshRepairSummary()
    refreshProjectRollups()
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

  func markProjectRulesEdited() {
    isProjectRulesSaved = projectRulesText.trimmingCharacters(in: .whitespacesAndNewlines)
      == ProjectTaggingService.rulesText.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  func saveProjectRules() {
    projectRulesText = projectRulesText.trimmingCharacters(in: .whitespacesAndNewlines)
    ProjectTaggingService.rulesText = projectRulesText
    isProjectRulesSaved = true
    refreshProjectRollups()
  }

  func refreshProjectRollups() {
    let today = DateFormatter.yyyyMMdd.string(from: timelineDisplayDate(from: Date()))
    let cards = StorageManager.shared.fetchTimelineCards(forDay: today)
    let rules = ProjectTaggingService.rules(from: projectRulesText)
    projectRollups = ProjectTaggingService.rollups(for: cards, rules: rules)
    projectRuleSuggestions = ProjectTaggingService.untaggedSuggestions(for: cards, rules: rules)
    projectRollupStatusMessage =
      cards.isEmpty
      ? "No cards found for today's timeline yet."
      : "\(cards.count) card\(cards.count == 1 ? "" : "s") scanned for today."
  }

  func addProjectRuleSuggestion(_ suggestion: ProjectRuleSuggestion) {
    let pattern = suggestion.pattern.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !pattern.isEmpty else { return }

    let projectName = suggestedProjectName(from: pattern)
    var lines = projectRulesText
      .components(separatedBy: .newlines)
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
      .filter { !$0.isEmpty }
    lines.append("\(projectName)=\(pattern)")
    projectRulesText = lines.joined(separator: "\n")
    markProjectRulesEdited()
  }

  func markTogglSettingsEdited() {
    isTogglSettingsSaved =
      togglAPITokenText.trimmingCharacters(in: .whitespacesAndNewlines)
      == TogglExportSettings.loadAPIToken().trimmingCharacters(in: .whitespacesAndNewlines)
      && togglWorkspaceIDText.trimmingCharacters(in: .whitespacesAndNewlines)
        == TogglExportSettings.workspaceID.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  func markTogglProjectMappingsEdited() {
    isTogglProjectMappingsSaved =
      togglProjectMappingsText.trimmingCharacters(in: .whitespacesAndNewlines)
      == TogglExportSettings.projectMappingsText.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  func saveTogglSettings() {
    togglAPITokenText = togglAPITokenText.trimmingCharacters(in: .whitespacesAndNewlines)
    togglWorkspaceIDText = togglWorkspaceIDText.trimmingCharacters(in: .whitespacesAndNewlines)
    let tokenSaved = TogglExportSettings.saveAPIToken(togglAPITokenText)
    TogglExportSettings.workspaceID = togglWorkspaceIDText
    isTogglSettingsSaved = tokenSaved
    togglErrorMessage = tokenSaved ? nil : "Couldn't save Toggl API token to Keychain."
    if tokenSaved {
      togglStatusMessage = "Toggl settings saved."
    }
  }

  func saveTogglProjectMappings() {
    togglProjectMappingsText = togglProjectMappingsText.trimmingCharacters(in: .whitespacesAndNewlines)
    TogglExportSettings.projectMappingsText = togglProjectMappingsText
    isTogglProjectMappingsSaved = true
    togglStatusMessage = "Toggl project mappings saved."
    if !togglDraftEntries.isEmpty {
      prepareTogglDraft()
    }
  }

  func loadTogglProjects() {
    guard !isLoadingTogglProjects else { return }
    let token = currentTogglToken()
    let workspaceID = togglWorkspaceIDText.trimmingCharacters(in: .whitespacesAndNewlines)

    guard !token.isEmpty else {
      togglErrorMessage = "Add and save a Toggl API token first."
      return
    }
    guard !workspaceID.isEmpty else {
      togglErrorMessage = "Add a Toggl workspace ID first."
      return
    }

    isLoadingTogglProjects = true
    togglStatusMessage = nil
    togglErrorMessage = nil

    Task {
      do {
        let projects = try await TogglExportService.fetchProjects(
          apiToken: token,
          workspaceID: workspaceID
        )
        togglProjects = projects
        togglStatusMessage = "Loaded \(projects.count) Toggl project\(projects.count == 1 ? "" : "s")."
        if !togglDraftEntries.isEmpty {
          prepareTogglDraft()
        }
      } catch {
        togglErrorMessage = error.localizedDescription
      }
      isLoadingTogglProjects = false
    }
  }

  func prepareTogglDraft() {
    guard !isPreparingTogglDraft else { return }
    let start = timelineDisplayDate(from: exportStartDate)
    let end = timelineDisplayDate(from: exportEndDate)
    let token = currentTogglToken()
    let workspaceID = togglWorkspaceIDText.trimmingCharacters(in: .whitespacesAndNewlines)

    guard start <= end else {
      togglErrorMessage = "Start date must be on or before end date."
      return
    }

    isPreparingTogglDraft = true
    togglStatusMessage = nil
    togglErrorMessage = nil

    Task.detached(priority: .userInitiated) { [
      start,
      end,
      token,
      workspaceID,
      togglProjects,
      projectRulesText,
      togglProjectMappingsText
    ] in
      let cards = Self.timelineCards(from: start, through: end)
      let rules = ProjectTaggingService.rules(from: projectRulesText)
      let mappings = TogglExportSettings.projectMappings(from: togglProjectMappingsText)
      var entries = TogglExportService.draftEntries(
        from: cards,
        projects: togglProjects,
        rules: rules,
        projectMappings: mappings
      )
      var duplicateStatus: String?

      if !token.isEmpty, !workspaceID.isEmpty, !entries.isEmpty {
        do {
          let existing = try await TogglExportService.fetchTimeEntries(
            apiToken: token,
            start: start,
            end: Calendar.current.date(byAdding: .day, value: 1, to: end) ?? end
          )
          entries = TogglExportService.markingExistingDuplicates(
            draftEntries: entries,
            existingEntries: existing
          )
          let duplicateCount = entries.filter { $0.duplicateWarning != nil }.count
          if duplicateCount > 0 {
            duplicateStatus = "\(duplicateCount) possible duplicate\(duplicateCount == 1 ? "" : "s") found in Toggl and unchecked."
          }
        } catch {
          duplicateStatus = "Draft prepared, but existing Toggl entries could not be checked: \(error.localizedDescription)"
        }
      } else if !entries.isEmpty {
        duplicateStatus = "Draft prepared without duplicate checks. Save a Toggl token and workspace ID to check existing entries."
      }

      await MainActor.run {
        self.togglDraftEntries = entries
        let baseMessage =
          entries.isEmpty
          ? "No timeline cards found for the selected range."
          : "Prepared \(entries.count) Toggl draft entr\(entries.count == 1 ? "y" : "ies"). Review before submitting."
        self.togglStatusMessage = [baseMessage, duplicateStatus].compactMap(\.self).joined(separator: " ")
        self.isPreparingTogglDraft = false
      }
    }
  }

  func updateTogglDraftEntry(_ entry: TogglExportDraftEntry) {
    guard let index = togglDraftEntries.firstIndex(where: { $0.id == entry.id }) else { return }
    togglDraftEntries[index] = entry
  }

  func submitSelectedTogglEntries() {
    guard !isSubmittingTogglEntries else { return }
    let token = currentTogglToken()
    let workspaceID = togglWorkspaceIDText.trimmingCharacters(in: .whitespacesAndNewlines)
    let selectedEntries = togglDraftEntries.filter(\.isIncluded)

    guard !token.isEmpty else {
      togglErrorMessage = "Add and save a Toggl API token first."
      return
    }
    guard !workspaceID.isEmpty else {
      togglErrorMessage = "Add a Toggl workspace ID first."
      return
    }
    guard !selectedEntries.isEmpty else {
      togglErrorMessage = "Select at least one Toggl draft entry."
      return
    }

    isSubmittingTogglEntries = true
    togglStatusMessage = "Submitting \(selectedEntries.count) Toggl entr\(selectedEntries.count == 1 ? "y" : "ies")..."
    togglErrorMessage = nil

    Task {
      var submitted = 0
      do {
        for entry in selectedEntries {
          try await TogglExportService.createTimeEntry(
            apiToken: token,
            workspaceID: workspaceID,
            entry: entry
          )
          submitted += 1
          togglStatusMessage = "Submitted \(submitted) of \(selectedEntries.count) Toggl entries..."
        }

        let submittedIDs = Set(selectedEntries.map(\.id))
        togglDraftEntries.removeAll { submittedIDs.contains($0.id) }
        togglStatusMessage = "Submitted \(submitted) Toggl entr\(submitted == 1 ? "y" : "ies")."
      } catch {
        togglErrorMessage = "Submitted \(submitted) before failure. \(error.localizedDescription)"
      }
      isSubmittingTogglEntries = false
    }
  }

  private func currentTogglToken() -> String {
    let unsaved = togglAPITokenText.trimmingCharacters(in: .whitespacesAndNewlines)
    return unsaved.isEmpty ? TogglExportSettings.loadAPIToken() : unsaved
  }

  private func suggestedProjectName(from pattern: String) -> String {
    let base = pattern
      .split(separator: ".")
      .first
      .map(String.init) ?? pattern
    return base
      .replacingOccurrences(of: "-", with: " ")
      .replacingOccurrences(of: "_", with: " ")
      .capitalized
  }

  nonisolated private static func timelineCards(from start: Date, through end: Date) -> [TimelineCard] {
    let calendar = Calendar.current
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd"

    var cards: [TimelineCard] = []
    var cursor = start
    while cursor <= end {
      cards.append(contentsOf: StorageManager.shared.fetchTimelineCards(forDay: formatter.string(from: cursor)))
      guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
      cursor = next
    }
    return cards
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

      var cardsByDay: [(day: Date, cards: [TimelineCard])] = []
      var totalActivities = 0
      var dayCount = 0

      while cursor <= endDate {
        let dayString = dayFormatter.string(from: cursor)
        let cards = StorageManager.shared.fetchTimelineCards(forDay: dayString)
        totalActivities += cards.count
        cardsByDay.append((day: cursor, cards: cards))
        dayCount += 1

        guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
        cursor = next
      }

      let exportText = MarkdownV2RangeExportBuilder.makeMarkdown(
        start: start,
        end: end,
        cardsByDay: cardsByDay
      )
      let finalDayCount = dayCount
      let finalActivityCount = totalActivities

      await MainActor.run {
        self.presentSavePanelAndWrite(
          exportText: exportText,
          startDate: start,
          endDate: end,
          dayCount: finalDayCount,
          activityCount: finalActivityCount
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

  func refreshRepairSummary() {
    guard !isRefreshingRepairSummary else { return }
    let dayString = DateFormatter.yyyyMMdd.string(from: timelineDisplayDate(from: reprocessDayDate))

    isRefreshingRepairSummary = true
    repairErrorMessage = nil

    Task.detached(priority: .userInitiated) { [dayString] in
      let summary = StorageManager.shared.failedBatchRepairSummary(forDay: dayString)
      await MainActor.run {
        self.repairSummary = summary
        self.isRefreshingRepairSummary = false
      }
    }
  }

  func dedupeFailedCardsForSelectedDay() {
    guard !isDedupingFailedCards else { return }
    let dayString = DateFormatter.yyyyMMdd.string(from: timelineDisplayDate(from: reprocessDayDate))

    isDedupingFailedCards = true
    repairStatusMessage = nil
    repairErrorMessage = nil

    Task.detached(priority: .userInitiated) { [dayString] in
      let deletedCount = StorageManager.shared.dedupeFailedTimelineCards(forDay: dayString)
      let summary = StorageManager.shared.failedBatchRepairSummary(forDay: dayString)

      await MainActor.run {
        self.repairSummary = summary
        self.repairStatusMessage =
          deletedCount == 0
          ? "No duplicate failed cards found."
          : "Removed \(deletedCount) duplicate failed card\(deletedCount == 1 ? "" : "s")."
        self.isDedupingFailedCards = false
      }
    }
  }

  func retryFailedBatchesForSelectedDay() {
    guard !isRetryingFailedBatches else { return }
    let dayString = DateFormatter.yyyyMMdd.string(from: timelineDisplayDate(from: reprocessDayDate))
    let batchIds =
      repairSummary?.retryableBatchIds
      ?? StorageManager.shared.failedBatchRepairSummary(forDay: dayString).retryableBatchIds

    guard !batchIds.isEmpty else {
      repairStatusMessage = nil
      repairErrorMessage = "No retryable failed batches found for \(dayString)."
      return
    }

    isRetryingFailedBatches = true
    repairErrorMessage = nil
    let override = repairProcessingOverride()
    let providerLabel = repairProviderOverrideLabel
    repairStatusMessage =
      "Retrying \(batchIds.count) failed batch\(batchIds.count == 1 ? "" : "es") with \(providerLabel)..."

    AnalysisManager.shared.reprocessSpecificBatches(
      batchIds,
      override: override,
      progressHandler: { [weak self] message in
        Task { @MainActor in
          self?.repairStatusMessage = message
        }
      },
      completion: { [weak self] result in
        Task { @MainActor in
          guard let self else { return }
          switch result {
          case .success:
            let summary = StorageManager.shared.failedBatchRepairSummary(forDay: dayString)
            self.repairSummary = summary
            self.repairStatusMessage = "Retry complete. \(summary.failedBatchCount) failed batch\(summary.failedBatchCount == 1 ? "" : "es") remain."
          case .failure(let error):
            self.repairErrorMessage = error.localizedDescription
          }
          self.isRetryingFailedBatches = false
        }
      }
    )
  }

  private func repairProcessingOverride() -> LLMProcessingOverride? {
    switch repairProviderOverrideId {
    case "current":
      return nil
    case OpenAICompatibleProviderSettings.providerID:
      return LLMProcessingOverride(
        providerID: .openAICompatible,
        modelID: repairModelOverrideText
      )
    case LLMProviderID.gemini.rawValue:
      return LLMProcessingOverride(
        providerID: .gemini,
        modelID: repairModelOverrideText
      )
    case "chatgpt_codex":
      return LLMProcessingOverride(providerID: .chatGPTClaude, chatTool: .codex)
    case "chatgpt_claude":
      return LLMProcessingOverride(providerID: .chatGPTClaude, chatTool: .claude)
    case LLMProviderID.ollama.rawValue:
      return LLMProcessingOverride(providerID: .ollama)
    default:
      return nil
    }
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
}
