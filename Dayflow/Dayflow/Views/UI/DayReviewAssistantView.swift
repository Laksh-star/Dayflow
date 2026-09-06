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
  @State private var question = ""
  @State private var answer = ""
  @State private var isShowingCaptureForm = false

  var body: some View {
    VStack(spacing: 0) {
      header
      Divider()
      ScrollView {
        VStack(alignment: .leading, spacing: 22) {
          taskSection
          captureSection
          reviewSection
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
        Text("Review day")
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
    reviewSectionCard(title: "Tasks", subtitle: "Small intentions for this day. Completion is always your decision.") {
      HStack(spacing: 8) {
        TextField("Add a task", text: $taskTitle)
          .textFieldStyle(.roundedBorder)
          .onSubmit(addTask)
        Button(action: addTask) { Image(systemName: "plus") }
          .buttonStyle(.borderedProminent)
          .disabled(taskTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
          .help("Add task")
      }
      ForEach(tasks) { task in
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
      if tasks.isEmpty {
        emptyText("No tasks yet. Add only the work you want to keep visible.")
      }
    }
  }

  private var captureSection: some View {
    reviewSectionCard(title: "Manual captures", subtitle: "Record activity Dayflow could not see, without inventing tracked time.") {
      Button(isShowingCaptureForm ? "Hide capture" : "Add capture") { isShowingCaptureForm.toggle() }
        .buttonStyle(.bordered)
      if isShowingCaptureForm {
        VStack(alignment: .leading, spacing: 10) {
          TextField("What happened?", text: $captureBody)
            .textFieldStyle(.roundedBorder)
          Picker("Type", selection: $captureKind) {
            ForEach(ManualCaptureKind.allCases, id: \.self) { Text($0.label).tag($0) }
          }
          .pickerStyle(.segmented)
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
        emptyText("No manual captures for this day.")
      }
    }
  }

  private var reviewSection: some View {
    reviewSectionCard(title: "Review", subtitle: "Suggestions are evidence, not automatic decisions.") {
      let suggestions = makeSuggestions()
      if suggestions.isEmpty {
        emptyText("No review suggestions yet.")
      }
      ForEach(suggestions) { suggestion in
        switch suggestion.kind {
        case .likelyWork(let task, let minutes):
          HStack {
            Text("Likely work found: \(minutes)m related to \(task.title)")
              .font(.custom("Figtree", size: 13))
            Spacer()
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
    reviewSectionCard(title: "Ask about this day", subtitle: "Answers are based only on this day’s local tasks, captures, and timeline cards.") {
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
          .disabled(question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
      }
      if !answer.isEmpty {
        VStack(alignment: .leading, spacing: 8) {
          Text(answer)
            .font(.custom("Figtree", size: 14))
          Button("Speak answer") { voiceService.speak(text: answer) }
            .buttonStyle(.bordered)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.black.opacity(0.035)))
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
    let capture = ManualCapture(id: UUID(), day: day, body: body, kind: captureKind, startTs: includeCaptureTime ? Int(captureStart.timeIntervalSince1970) : nil, endTs: includeCaptureTime ? Int(captureEnd.timeIntervalSince1970) : nil, categoryID: nil, projectName: nil, taskID: nil, source: .desktop, sourcePayload: nil, createdAt: now, updatedAt: now)
    storageManager.saveManualCapture(capture)
    captureBody = ""
    isShowingCaptureForm = false
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
  private func deleteCapture(_ capture: ManualCapture) { storageManager.deleteManualCapture(id: capture.id); reload() }
  private func carryForward(_ task: DayflowTask) {
    var updated = task
    updated.status = .deferred
    updated.plannedDay = Calendar.current.date(byAdding: .day, value: 1, to: Date())?.formatted(.iso8601.year().month().day())
    updated.updatedAt = Int(Date().timeIntervalSince1970)
    storageManager.saveTask(updated)
    storageManager.saveDayReviewDecision(DayReviewDecision(id: UUID(), day: day, taskID: task.id, kind: .carryForward, payloadJSON: "{}", createdAt: updated.updatedAt))
    reload()
  }

  private func makeSuggestions() -> [DayReviewSuggestion] {
    let openTasks = tasks.filter { $0.status != .done && $0.status != .dropped }
    return openTasks.compactMap { task in
      let words = Set(task.title.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }).filter { $0.count > 3 })
      let matches = cards.filter { card in
        let text = "\(card.title) \(card.summary)".lowercased()
        return words.contains { text.contains($0) }
      }
      if !matches.isEmpty { return DayReviewSuggestion(id: "work-\(task.id)", kind: .likelyWork(task: task, minutes: matches.count * 15)) }
      return DayReviewSuggestion(id: "carry-\(task.id)", kind: .carryForward(task: task))
    }
  }

  private func answerQuestion() {
    let normalized = question.lowercased()
    if normalized.contains("unfinished") || normalized.contains("task") {
      let open = tasks.filter { $0.status != .done && $0.status != .dropped }.map(\.title)
      answer = open.isEmpty ? "There are no unfinished tasks for this day." : "Still open: \(open.joined(separator: ", "))."
    } else if normalized.contains("capture") || normalized.contains("offline") {
      answer = captures.isEmpty ? "There are no manual captures for this day." : "Manual captures: \(captures.map(\.body).joined(separator: "; "))."
    } else {
      let titles = cards.prefix(4).map(\.title)
      answer = titles.isEmpty ? "There are no processed desktop cards for this day yet." : "Dayflow recorded \(cards.count) desktop activity cards. The main threads were: \(titles.joined(separator: "; "))."
    }
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
