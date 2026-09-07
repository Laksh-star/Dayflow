import Foundation
import GRDB

extension StorageManager {
  func fetchTasks(forDay day: String) -> [DayflowTask] {
    (try? timedRead("fetchTasks") { db in
      try Row.fetchAll(
        db,
        sql: """
          SELECT id, title, status, created_day, planned_day, category_id, project_name,
                 estimate_minutes, notes, created_at, updated_at, completed_at
          FROM dayflow_tasks
          WHERE planned_day = ? OR (planned_day IS NULL AND status IN ('inbox', 'in_progress'))
          ORDER BY CASE status WHEN 'done' THEN 1 WHEN 'dropped' THEN 1 ELSE 0 END,
                   updated_at DESC
        """,
        arguments: [day]
      ).compactMap(Self.taskFromRow)
    }) ?? []
  }

  func saveTask(_ task: DayflowTask) {
    try? timedWrite("saveTask") { db in
      try db.execute(
        sql: """
          INSERT INTO dayflow_tasks(
            id, title, status, created_day, planned_day, category_id, project_name,
            estimate_minutes, notes, created_at, updated_at, completed_at
          ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
          ON CONFLICT(id) DO UPDATE SET
            title = excluded.title, status = excluded.status, planned_day = excluded.planned_day,
            category_id = excluded.category_id, project_name = excluded.project_name,
            estimate_minutes = excluded.estimate_minutes, notes = excluded.notes,
            updated_at = excluded.updated_at, completed_at = excluded.completed_at
        """,
        arguments: [
          task.id.uuidString, task.title, task.status.rawValue, task.createdDay, task.plannedDay,
          task.categoryID, task.projectName, task.estimateMinutes, task.notes, task.createdAt,
          task.updatedAt, task.completedAt,
        ]
      )
    }
  }

  func deleteTask(id: UUID) {
    try? timedWrite("deleteTask") { db in
      try db.execute(sql: "DELETE FROM dayflow_tasks WHERE id = ?", arguments: [id.uuidString])
    }
  }

  func fetchManualCaptures(forDay day: String) -> [ManualCapture] {
    (try? timedRead("fetchManualCaptures") { db in
      try Row.fetchAll(
        db,
        sql: """
          SELECT id, day, body, kind, start_ts, end_ts, category_id, project_name, task_id,
                 source, source_payload, created_at, updated_at
          FROM manual_captures WHERE day = ?
          ORDER BY COALESCE(start_ts, created_at) ASC, created_at ASC
        """,
        arguments: [day]
      ).compactMap(Self.captureFromRow)
    }) ?? []
  }

  func saveManualCapture(_ capture: ManualCapture) {
    try? timedWrite("saveManualCapture") { db in
      try db.execute(
        sql: """
          INSERT INTO manual_captures(
            id, day, body, kind, start_ts, end_ts, category_id, project_name, task_id,
            source, source_payload, created_at, updated_at
          ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
          ON CONFLICT(id) DO UPDATE SET
            body = excluded.body, kind = excluded.kind, start_ts = excluded.start_ts,
            end_ts = excluded.end_ts, category_id = excluded.category_id,
            project_name = excluded.project_name, task_id = excluded.task_id,
            source_payload = excluded.source_payload, updated_at = excluded.updated_at
        """,
        arguments: [
          capture.id.uuidString, capture.day, capture.body, capture.kind.rawValue,
          capture.startTs, capture.endTs, capture.categoryID, capture.projectName,
          capture.taskID?.uuidString, capture.source.rawValue, capture.sourcePayload,
          capture.createdAt, capture.updatedAt,
        ]
      )
    }
  }

  func deleteManualCapture(id: UUID) {
    try? timedWrite("deleteManualCapture") { db in
      try db.execute(sql: "DELETE FROM manual_captures WHERE id = ?", arguments: [id.uuidString])
    }
  }

  func saveDayReviewDecision(_ decision: DayReviewDecision) {
    try? timedWrite("saveDayReviewDecision") { db in
      try db.execute(
        sql: """
          INSERT INTO day_review_decisions(id, day, task_id, kind, payload_json, created_at)
          VALUES (?, ?, ?, ?, ?, ?)
        """,
        arguments: [
          decision.id.uuidString, decision.day, decision.taskID?.uuidString,
          decision.kind.rawValue, decision.payloadJSON, decision.createdAt,
        ]
      )
    }
  }

  func fetchDayReviewDecisions(forDay day: String) -> [DayReviewDecision] {
    (try? timedRead("fetchDayReviewDecisions") { db in
      try Row.fetchAll(
        db,
        sql: "SELECT id, day, task_id, kind, payload_json, created_at FROM day_review_decisions WHERE day = ? ORDER BY created_at ASC",
        arguments: [day]
      ).compactMap { row in
        guard let id = UUID(uuidString: row["id"]),
          let kind = DayReviewDecisionKind(rawValue: row["kind"])
        else { return nil }
        return DayReviewDecision(
          id: id, day: row["day"], taskID: (row["task_id"] as String?).flatMap(UUID.init(uuidString:)),
          kind: kind, payloadJSON: row["payload_json"], createdAt: row["created_at"]
        )
      }
    }) ?? []
  }

  func fetchTaskEvidenceLinks(forTask taskID: UUID) -> [TaskEvidenceLink] {
    (try? timedRead("fetchTaskEvidenceLinks") { db in
      try Row.fetchAll(
        db,
        sql: "SELECT id, task_id, day, source, source_id, strength, matched_by, created_at FROM task_evidence_links WHERE task_id = ? ORDER BY created_at DESC",
        arguments: [taskID.uuidString]
      ).compactMap { row in
        guard let id = UUID(uuidString: row["id"]),
          let source = TaskEvidenceSource(rawValue: row["source"]),
          let strength = TaskEvidenceStrength(rawValue: row["strength"])
        else { return nil }
        return TaskEvidenceLink(
          id: id, taskID: taskID, day: row["day"], source: source, sourceID: row["source_id"],
          strength: strength, matchedBy: row["matched_by"], createdAt: row["created_at"]
        )
      }
    }) ?? []
  }

  func saveTaskEvidenceLink(_ link: TaskEvidenceLink) {
    try? timedWrite("saveTaskEvidenceLink") { db in
      try db.execute(
        sql: """
          INSERT INTO task_evidence_links(id, task_id, day, source, source_id, strength, matched_by, created_at)
          VALUES (?, ?, ?, ?, ?, ?, ?, ?)
          ON CONFLICT(task_id, source, source_id) DO UPDATE SET strength = excluded.strength, matched_by = excluded.matched_by
        """,
        arguments: [
          link.id.uuidString, link.taskID.uuidString, link.day, link.source.rawValue, link.sourceID,
          link.strength.rawValue, link.matchedBy, link.createdAt,
        ]
      )
    }
  }

  func deleteTaskEvidenceLink(id: UUID) {
    try? timedWrite("deleteTaskEvidenceLink") { db in
      try db.execute(sql: "DELETE FROM task_evidence_links WHERE id = ?", arguments: [id.uuidString])
    }
  }

  func hasImportedMobileCapture(sourcePath: String) -> Bool {
    (try? timedRead("hasImportedMobileCapture") { db in
      try Bool.fetchOne(db, sql: "SELECT EXISTS(SELECT 1 FROM mobile_capture_imports WHERE source_path = ?)", arguments: [sourcePath])
    }) ?? false
  }

  func recordMobileCaptureImport(sourcePath: String, importedAt: Int) {
    try? timedWrite("recordMobileCaptureImport") { db in
      try db.execute(
        sql: "INSERT OR IGNORE INTO mobile_capture_imports(source_path, imported_at) VALUES (?, ?)",
        arguments: [sourcePath, importedAt]
      )
    }
  }

  private static func taskFromRow(_ row: Row) -> DayflowTask? {
    guard let id = UUID(uuidString: row["id"]), let status = DayflowTaskStatus(rawValue: row["status"]) else { return nil }
    return DayflowTask(
      id: id, title: row["title"], status: status, createdDay: row["created_day"],
      plannedDay: row["planned_day"], categoryID: row["category_id"], projectName: row["project_name"],
      estimateMinutes: row["estimate_minutes"], notes: row["notes"], createdAt: row["created_at"],
      updatedAt: row["updated_at"], completedAt: row["completed_at"]
    )
  }

  private static func captureFromRow(_ row: Row) -> ManualCapture? {
    guard let id = UUID(uuidString: row["id"]), let kind = ManualCaptureKind(rawValue: row["kind"]),
      let source = ManualCaptureSource(rawValue: row["source"])
    else { return nil }
    return ManualCapture(
      id: id, day: row["day"], body: row["body"], kind: kind, startTs: row["start_ts"], endTs: row["end_ts"],
      categoryID: row["category_id"], projectName: row["project_name"],
      taskID: (row["task_id"] as String?).flatMap(UUID.init(uuidString:)), source: source,
      sourcePayload: row["source_payload"], createdAt: row["created_at"], updatedAt: row["updated_at"]
    )
  }
}
