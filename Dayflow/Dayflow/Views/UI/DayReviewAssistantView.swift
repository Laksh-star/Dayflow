import AppKit
import SwiftUI

struct DayReviewAssistantView: View {
  let day: String
  let categories: [TimelineCategory]
  let storageManager: StorageManaging

  @Environment(\.dismiss) private var dismiss
  @StateObject private var voiceService = VoiceCapabilityService()
  @State private var tasks: [DayflowTask] = []
  @State private var captures: [ManualCapture] = []
  @State private var cards: [TimelineCard] = []
  @State private var taskTitle = ""
  @State private var captureBody = ""
  @State private var captureKind: ManualCaptureKind = .offlineWork
  @State private var includeCaptureTime = false
  @State private var captureStart = Date()
  @State private var captureEnd = Date().addingTimeInterval(30 * 60)
  @State private var captureTaskID: UUID?
  @State private var question = ""
  @State private var answer = ""
  @State private var isShowingCaptureForm = false
  @State private var isAnswering = false
  @State private var answerSource = ""
  @State private var recommendedTask: DayflowTask?
  @State private var inboxStatus = ""
  @State private var isAssistantExpanded = false

  var body: some View {
    VStack(spacing: 0) {
      header
      Divider()
      ScrollView {
        VStack(alignment: .leading, spacing: 22) {
          captureSection
          taskSection
          conversationSection
        }
        .padding(24)
      }
    }
    .frame(minWidth: 680, minHeight: 650)
    .background(Color(hex: "FFFAF5"))
    .onAppear(perform: reload)
  }

  private var header: some View {
    HStack(alignment: .top) {
      VStack(alignment: .leading, spacing: 4) {
        Text("Close the day")
          .font(.custom("InstrumentSerif", size: 30))
          .foregroundColor(SettingsStyle.text)
        Text(day)
          .font(.custom("Figtree", size: 13))
          .foregroundColor(SettingsStyle.secondary)
      }
      Spacer()
      Button(action: { dismiss() }) {
        Image(systemName: "xmark")
          .font(.system(size: 12, weight: .semibold))
          .frame(width: 28, height: 28)
      }
      .buttonStyle(.plain)
      .help("Close")
    }
    .padding(24)
  }

  private var taskSection: some View {
    reviewSectionCard(title: "2. Resolve tasks", subtitle: "Only open tasks need a decision. Completion is always yours to confirm.") {
      HStack(spacing: 8) {
        TextField("Add a task", text: $taskTitle)
          .textFieldStyle(.roundedBorder)
          .onSubmit(addTask)
        Button(action: addTask) { Image(systemName: "plus") }
          .buttonStyle(.borderedProminent)
          .disabled(taskTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
          .help("Add task")
      }
      ForEach(openTasks) { task in
        HStack(spacing: 10) {
          Button(action: { toggleTask(task) }) {
            Image(systemName: task.status == .done ? "checkmark.circle.fill" : "circle")
              .foregroundColor(task.status == .done ? Color(hex: "44A464") : SettingsStyle.secondary)
          }
          .buttonStyle(.plain)
          Text(task.title)
            .font(.custom("Figtree", size: 14))
            .strikethrough(task.status == .done)
          Spacer()
          Menu(task.status.label) {
            ForEach(DayflowTaskStatus.allCases, id: \.self) { status in
              Button(status.label) { updateTask(task, status: status) }
            }
          }
          .font(.custom("Figtree", size: 12))
          Button(role: .destructive, action: { deleteTask(task) }) { Image(systemName: "trash") }
            .buttonStyle(.plain)
            .help("Delete task")
        }
      }
      if openTasks.isEmpty {
        emptyText("No open tasks for this day.")
      }
      taskEvidenceSuggestions
    }
  }

  private var captureSection: some View {
    reviewSectionCard(title: "1. Add offline activity", subtitle: "Only record meaningful work Dayflow could not see.") {
      HStack {
        Button(isShowingCaptureForm ? "Hide form" : "Add offline activity") { isShowingCaptureForm.toggle() }
          .buttonStyle(.bordered)
        Spacer()
        Menu("Mobile inbox") {
          Button("Choose folder", action: chooseMobileInbox)
          Button("Import now", action: importMobileInbox)
        }
        .buttonStyle(.bordered)
      }
      if !inboxStatus.isEmpty { emptyText(inboxStatus) }
      if isShowingCaptureForm {
        VStack(alignment: .leading, spacing: 10) {
          TextField("What happened?", text: $captureBody)
            .textFieldStyle(.roundedBorder)
          Picker("Type", selection: $captureKind) {
            ForEach(ManualCaptureKind.allCases, id: \.self) { Text($0.label).tag($0) }
          }
          .pickerStyle(.segmented)
          Picker("Task", selection: $captureTaskID) {
            Text("No linked task").tag(UUID?.none)
            ForEach(tasks.filter { $0.status != .dropped }) { task in
              Text(task.title).tag(Optional(task.id))
            }
          }
          Toggle("Add a time range", isOn: $includeCaptureTime)
          if includeCaptureTime {
            HStack {
              DatePicker("Start", selection: $captureStart, displayedComponents: [.hourAndMinute])
              DatePicker("End", selection: $captureEnd, displayedComponents: [.hourAndMinute])
            }
          }
          HStack {
            Spacer()
            Button("Save capture", action: addCapture)
              .buttonStyle(.borderedProminent)
              .disabled(captureBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || (includeCaptureTime && captureEnd <= captureStart))
          }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.black.opacity(0.035)))
      }
      ForEach(captures) { capture in
        HStack(alignment: .firstTextBaseline, spacing: 10) {
          Text(capture.kind.label)
            .font(.custom("Figtree", size: 12).weight(.semibold))
            .foregroundColor(SettingsStyle.secondary)
          Text(capture.body)
            .font(.custom("Figtree", size: 14))
          Spacer()
          if let minutes = capture.durationMinutes {
            Text("\(minutes)m")
              .font(.custom("Figtree", size: 12))
              .foregroundColor(SettingsStyle.secondary)
          }
          Button(role: .destructive, action: { deleteCapture(capture) }) { Image(systemName: "trash") }
            .buttonStyle(.plain)
            .help("Delete capture")
        }
      }
      if captures.isEmpty && !isShowingCaptureForm {
        emptyText("Nothing to add unless meaningful work happened away from your desktop.")
      }
    }
  }

  @ViewBuilder
  private var taskEvidenceSuggestions: some View {
    let suggestions = makeSuggestions()
    if suggestions.isEmpty == false {
      Divider().padding(.vertical, 2)
      Text("Evidence to review")
        .font(.custom("Figtree", size: 12).weight(.semibold))
        .foregroundColor(SettingsStyle.secondary)
      ForEach(suggestions) { suggestion in
        switch suggestion.kind {
        case .likelyWork(let task, let minutes, let cardIDs):
          HStack {
            Text("Likely work found: \(minutes)m related to \(task.title)")
              .font(.custom("Figtree", size: 13))
            Spacer()
            Button("Link evidence") { linkEvidence(task: task, cardIDs: cardIDs) }
              .buttonStyle(.bordered)
            Button("Mark done") { updateTask(task, status: .done, decision: .complete) }
              .buttonStyle(.bordered)
          }
        case .carryForward(let task):
          HStack {
            Text("No matching evidence for \(task.title)")
              .font(.custom("Figtree", size: 13))
            Spacer()
            Button("Carry forward") { carryForward(task) }
              .buttonStyle(.bordered)
          }
        case .unlinkedCapture(let capture):
          Text("Manual capture has no linked task: \(capture.body)")
            .font(.custom("Figtree", size: 13))
        }
      }
    }
  }

  private var conversationSection: some View {
    reviewSectionCard(title: "3. Day review assistant", subtitle: "Optional. Ask when you want help interpreting the day's evidence.") {
      Button(isAssistantExpanded ? "Hide assistant" : "Review with assistant") { isAssistantExpanded.toggle() }
        .buttonStyle(.bordered)
      if isAssistantExpanded {
      VStack(alignment: .leading, spacing: 8) {
        Text("Guided review")
          .font(.custom("Figtree", size: 12).weight(.semibold))
          .foregroundColor(SettingsStyle.secondary)
        HStack(spacing: 8) {
          ForEach(DayReviewPrompt.allCases) { prompt in
            Button(prompt.title) { ask(prompt) }
              .buttonStyle(.bordered)
              .disabled(isAnswering)
          }
        }
      }
      if !voiceService.transcript.isEmpty {
        Text(voiceService.transcript)
          .font(.custom("Figtree", size: 13))
          .padding(10)
          .frame(maxWidth: .infinity, alignment: .leading)
          .background(RoundedRectangle(cornerRadius: 8).fill(Color.black.opacity(0.04)))
          .onTapGesture { question = voiceService.transcript }
      }
      Picker("Voice", selection: $voiceService.transcriptionMode) {
        ForEach(VoiceTranscriptionMode.allCases) { mode in
          Text(mode.title).tag(mode)
        }
      }
      .pickerStyle(.segmented)
      .disabled(voiceService.isListening)
      HStack(spacing: 8) {
        TextField("Ask what happened, what is unfinished, or what to resume", text: $question)
          .textFieldStyle(.roundedBorder)
          .onSubmit(answerQuestion)
        ReviewVoiceButton(service: voiceService)
        Button("Ask", action: answerQuestion)
          .buttonStyle(.borderedProminent)
          .disabled(question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isAnswering)
      }
      if isAnswering { emptyText("Reviewing this day's evidence...") }
      if !answer.isEmpty {
        VStack(alignment: .leading, spacing: 8) {
          Text(answer)
            .font(.custom("Figtree", size: 14))
          if !answerSource.isEmpty { emptyText(answerSource) }
          if let recommendedTask, recommendedTask.status != .done, recommendedTask.status != .dropped {
            Button("Carry \(recommendedTask.title) to tomorrow") { carryForward(recommendedTask) }
              .buttonStyle(.bordered)
          }
          Button("Speak answer") { voiceService.speak(text: answer) }
            .buttonStyle(.bordered)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.black.opacity(0.035)))
      }
      }
    }
    .onChange(of: voiceService.transcript) { _, transcript in
      guard !transcript.isEmpty else { return }
      question = transcript
    }
  }

  private func reviewSectionCard<Content: View>(title: String, subtitle: String, @ViewBuilder content: () -> Content) -> some View {
    VStack(alignment: .leading, spacing: 12) {
      VStack(alignment: .leading, spacing: 3) {
        Text(title).font(.custom("InstrumentSerif", size: 22)).foregroundColor(SettingsStyle.text)
        Text(subtitle).font(.custom("Figtree", size: 12)).foregroundColor(SettingsStyle.secondary)
      }
      content()
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(16)
    .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.62)))
    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.black.opacity(0.07), lineWidth: 1))
  }

  private func emptyText(_ text: String) -> some View {
    Text(text).font(.custom("Figtree", size: 13)).foregroundColor(SettingsStyle.secondary)
  }

  private func reload() {
    tasks = storageManager.fetchTasks(forDay: day)
    captures = storageManager.fetchManualCaptures(forDay: day)
    cards = storageManager.fetchTimelineCards(forDay: day)
  }

  private func addTask() {
    let title = taskTitle.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !title.isEmpty else { return }
    let now = Int(Date().timeIntervalSince1970)
    storageManager.saveTask(DayflowTask(id: UUID(), title: title, status: .planned, createdDay: day, plannedDay: day, categoryID: nil, projectName: nil, estimateMinutes: nil, notes: "", createdAt: now, updatedAt: now, completedAt: nil))
    taskTitle = ""
    reload()
  }

  private func addCapture() {
    let body = captureBody.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !body.isEmpty else { return }
    let now = Int(Date().timeIntervalSince1970)
    let capture = ManualCapture(id: UUID(), day: day, body: body, kind: captureKind, startTs: includeCaptureTime ? Int(captureStart.timeIntervalSince1970) : nil, endTs: includeCaptureTime ? Int(captureEnd.timeIntervalSince1970) : nil, categoryID: nil, projectName: nil, taskID: captureTaskID, source: .desktop, sourcePayload: nil, createdAt: now, updatedAt: now)
    storageManager.saveManualCapture(capture)
    if let taskID = captureTaskID {
      storageManager.saveTaskEvidenceLink(TaskEvidenceLink(id: UUID(), taskID: taskID, day: day, source: .manualCapture, sourceID: capture.id.uuidString, strength: .manual, matchedBy: "user", createdAt: now))
    }
    captureBody = ""
    captureTaskID = nil
    isShowingCaptureForm = false
    NotificationCenter.default.post(name: .personalAssistantTimelineDidChange, object: nil)
    reload()
  }

  private func toggleTask(_ task: DayflowTask) { updateTask(task, status: task.status == .done ? .planned : .done) }
  private func updateTask(_ task: DayflowTask, status: DayflowTaskStatus, decision: DayReviewDecisionKind? = nil) {
    var updated = task
    updated.status = status
    updated.updatedAt = Int(Date().timeIntervalSince1970)
    updated.completedAt = status == .done ? updated.updatedAt : nil
    storageManager.saveTask(updated)
    if let decision { storageManager.saveDayReviewDecision(DayReviewDecision(id: UUID(), day: day, taskID: task.id, kind: decision, payloadJSON: "{}", createdAt: updated.updatedAt)) }
    reload()
  }
  private func deleteTask(_ task: DayflowTask) { storageManager.deleteTask(id: task.id); reload() }
  private func deleteCapture(_ capture: ManualCapture) {
    storageManager.deleteManualCapture(id: capture.id)
    NotificationCenter.default.post(name: .personalAssistantTimelineDidChange, object: nil)
    reload()
  }
  private func carryForward(_ task: DayflowTask) {
    var updated = task
    updated.status = .deferred
    updated.plannedDay = nextDayString(after: day)
    updated.updatedAt = Int(Date().timeIntervalSince1970)
    storageManager.saveTask(updated)
    storageManager.saveDayReviewDecision(DayReviewDecision(id: UUID(), day: day, taskID: task.id, kind: .carryForward, payloadJSON: "{}", createdAt: updated.updatedAt))
    reload()
  }

  private func makeSuggestions() -> [DayReviewSuggestion] {
    let openTasks = self.openTasks
    return openTasks.compactMap { task in
      let words = Set(task.title.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }).filter { $0.count > 3 })
      let matches = cards.filter { card in
        let text = "\(card.title) \(card.summary)".lowercased()
        return words.contains { text.contains($0) }
      }
      let matchedIDs = matches.compactMap(\.recordId)
      let minutes = matches.reduce(0) { partial, card in
        let duration = TimelineActivityLoader.buildActivities(from: [card]).first.map {
          Int(($0.endTime.timeIntervalSince($0.startTime) / 60).rounded())
        } ?? 0
        return partial + duration
      }
      if !matches.isEmpty { return DayReviewSuggestion(id: "work-\(task.id)", kind: .likelyWork(task: task, minutes: minutes, cardIDs: matchedIDs)) }
      return DayReviewSuggestion(id: "carry-\(task.id)", kind: .carryForward(task: task))
    }
  }

  private var openTasks: [DayflowTask] {
    tasks.filter { $0.status != .done && $0.status != .dropped }
  }

  private func linkEvidence(task: DayflowTask, cardIDs: [Int64]) {
    let now = Int(Date().timeIntervalSince1970)
    for cardID in cardIDs {
      storageManager.saveTaskEvidenceLink(TaskEvidenceLink(id: UUID(), taskID: task.id, day: day, source: .timelineCard, sourceID: String(cardID), strength: .likely, matchedBy: "deterministic", createdAt: now))
    }
    storageManager.saveDayReviewDecision(DayReviewDecision(id: UUID(), day: day, taskID: task.id, kind: .linkEvidence, payloadJSON: "{}", createdAt: now))
    reload()
  }

  private func answerQuestion() {
    let requestedQuestion = question.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !requestedQuestion.isEmpty, !isAnswering else { return }
    answerQuestion(requestedQuestion)
  }

  private func ask(_ prompt: DayReviewPrompt) {
    question = prompt.question
    answerQuestion(prompt.question)
  }

  private func answerQuestion(_ requestedQuestion: String) {
    isAnswering = true
    answer = ""
    recommendedTask = requestedQuestion.lowercased().contains("next") || requestedQuestion.lowercased().contains("resume")
      ? DayReviewAnswerService.recommendedTask(
        from: tasks.filter { $0.status != .done && $0.status != .dropped },
        cards: cards,
        captures: captures
      )
      : nil
    Task {
      do {
        let providerAnswer = try await DayReviewAnswerService().answer(question: requestedQuestion, day: day, cards: cards, tasks: tasks, captures: captures)
        await MainActor.run {
          answer = providerAnswer
          answerSource = "Provider-backed answer from this day's supplied evidence."
          isAnswering = false
        }
      } catch {
        await MainActor.run {
          answer = DayReviewAnswerService.localAnswer(question: requestedQuestion, cards: cards, tasks: tasks, captures: captures)
          answerSource = "Local evidence fallback: \(error.localizedDescription)"
          isAnswering = false
        }
      }
    }
  }

  private func nextDayString(after string: String) -> String? {
    guard let date = DateFormatter.yyyyMMdd.date(from: string),
      let next = Calendar.current.date(byAdding: .day, value: 1, to: date)
    else { return nil }
    return DateFormatter.yyyyMMdd.string(from: next)
  }

  private func chooseMobileInbox() {
    let panel = NSOpenPanel()
    panel.canChooseFiles = false
    panel.canChooseDirectories = true
    panel.allowsMultipleSelection = false
    guard panel.runModal() == .OK, let url = panel.url else { return }
    UserDefaults.standard.set(url.path, forKey: MobileCaptureInboxService.folderPathDefaultsKey)
    inboxStatus = "Mobile inbox: \(url.lastPathComponent)"
  }

  private func importMobileInbox() {
    let result = MobileCaptureInboxService().importCaptures(storageManager: storageManager)
    inboxStatus = result.summary
    if result.imported > 0 { NotificationCenter.default.post(name: .personalAssistantTimelineDidChange, object: nil) }
    reload()
  }
}

private struct ReviewVoiceButton: View {
  @ObservedObject var service: VoiceCapabilityService

  var body: some View {
    Image(systemName: service.isListening ? "mic.fill" : "mic")
      .foregroundColor(.white)
      .frame(width: 38, height: 32)
      .background(RoundedRectangle(cornerRadius: 7).fill(service.isListening ? Color.red.opacity(0.85) : SettingsStyle.ink))
      .contentShape(Rectangle())
      .onLongPressGesture(minimumDuration: .infinity, maximumDistance: .infinity, pressing: { pressed in
        pressed ? service.startPressToTalk() : service.stopPressToTalk()
      }, perform: {})
      .help("Hold to ask by voice")
  }
}
