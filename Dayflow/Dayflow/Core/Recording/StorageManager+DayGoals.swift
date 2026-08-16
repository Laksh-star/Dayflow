import Foundation
import GRDB

extension StorageManager {
  private static let emptyJSONArray = "[]"

  func fetchDayGoalPlan(forDay day: String) -> DayGoalPlan? {
    fetchDayGoalPlan(whereSQL: "day = ?", arguments: [day], label: "fetchDayGoalPlan")
  }

  func fetchMostRecentDayGoalPlan(beforeOrOn day: String) -> DayGoalPlan? {
    fetchDayGoalPlan(
      whereSQL: "day <= ?",
      arguments: [day],
      orderSQL: "ORDER BY day DESC",
      label: "fetchMostRecentDayGoalPlan"
    )
  }

  /// Number of distinct timeline days with recorded activity, excluding the
  /// given day. Used to hold the daily goal prompt back until a new user has
  /// actually used Dayflow for a few days.
  func countDistinctTimelineDays(excludingDay day: String) -> Int {
    (try? timedRead("countDistinctTimelineDays") { db in
      try Int.fetchOne(
        db,
        sql: """
              SELECT COUNT(DISTINCT day)
              FROM timeline_cards
              WHERE is_deleted = 0 AND day != ?
          """,
        arguments: [day]
      ) ?? 0
    }) ?? 0
  }

  /// How many of the most recent day-goal answers before the given day were
  /// skips, counting back from the newest until the first confirmed plan.
  /// Days with no row (app not opened, so no prompt) don't affect the streak.
  func consecutiveSkippedDayGoalCount(before day: String, limit: Int) -> Int {
    (try? timedRead("consecutiveSkippedDayGoalCount") { db in
      let skipFlags = try Int.fetchAll(
        db,
        sql: """
              SELECT is_skipped
              FROM day_goals
              WHERE day < ?
              ORDER BY day DESC
              LIMIT ?
          """,
        arguments: [day, limit]
      )

      var streak = 0
      for flag in skipFlags {
        guard flag != 0 else { break }
        streak += 1
      }
      return streak
    }) ?? 0
  }

  func saveDayGoalPlan(_ plan: DayGoalPlan) {
    let now = Int(Date().timeIntervalSince1970)
    let createdAt = plan.createdAt > 0 ? plan.createdAt : now

    try? timedWrite("saveDayGoalPlan") { db in
      try db.execute(
        sql: """
              INSERT INTO day_goals(
                  day, focus_target_minutes, distraction_limit_minutes, is_skipped,
                  created_at, updated_at
              )
              VALUES (?, ?, ?, ?, ?, ?)
              ON CONFLICT(day) DO UPDATE SET
                  focus_target_minutes = excluded.focus_target_minutes,
                  distraction_limit_minutes = excluded.distraction_limit_minutes,
                  is_skipped = excluded.is_skipped,
                  updated_at = excluded.updated_at
          """,
        arguments: [
          plan.day,
          plan.focusTargetMinutes,
          plan.distractionLimitMinutes,
          plan.isSkipped ? 1 : 0,
          createdAt,
          now,
        ])

      try db.execute(
        sql: "DELETE FROM day_goal_categories WHERE day = ?",
        arguments: [plan.day]
      )
      try db.execute(
        sql: "DELETE FROM day_focus_windows WHERE day = ?",
        arguments: [plan.day]
      )

      try insertGoalCategories(plan.focusCategories, kind: .focus, day: plan.day, db: db)
      try insertGoalCategories(
        plan.distractionCategories, kind: .distraction, day: plan.day, db: db)
      try insertFocusWindows(plan.focusWindows, day: plan.day, db: db)
    }
  }

  func fetchRecoveryAnnotations(forDay day: String) -> [DayRecoveryAnnotation] {
    (try? timedRead("fetchRecoveryAnnotations") { db in
      try Row.fetchAll(
        db,
        sql: """
              SELECT event_id, day, start_ts, end_ts, trigger_category, recovery_category,
                     pull_reason, return_reason, created_at, updated_at
              FROM day_recovery_annotations
              WHERE day = ?
              ORDER BY start_ts ASC, updated_at DESC
          """,
        arguments: [day]
      ).map { row in
        DayRecoveryAnnotation(
          eventID: row["event_id"],
          day: row["day"],
          startTs: row["start_ts"],
          endTs: row["end_ts"],
          triggerCategory: row["trigger_category"],
          recoveryCategory: row["recovery_category"],
          pullReason: row["pull_reason"],
          returnReason: row["return_reason"],
          createdAt: row["created_at"],
          updatedAt: row["updated_at"]
        )
      }
    }) ?? []
  }

  func saveRecoveryAnnotation(_ annotation: DayRecoveryAnnotation) {
    let now = Int(Date().timeIntervalSince1970)
    let createdAt = annotation.createdAt > 0 ? annotation.createdAt : now

    try? timedWrite("saveRecoveryAnnotation") { db in
      try db.execute(
        sql: """
              INSERT INTO day_recovery_annotations(
                  event_id, day, start_ts, end_ts, trigger_category, recovery_category,
                  pull_reason, return_reason, created_at, updated_at
              )
              VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
              ON CONFLICT(event_id, day) DO UPDATE SET
                  start_ts = excluded.start_ts,
                  end_ts = excluded.end_ts,
                  trigger_category = excluded.trigger_category,
                  recovery_category = excluded.recovery_category,
                  pull_reason = excluded.pull_reason,
                  return_reason = excluded.return_reason,
                  updated_at = excluded.updated_at
          """,
        arguments: [
          annotation.eventID,
          annotation.day,
          annotation.startTs,
          annotation.endTs,
          annotation.triggerCategory,
          annotation.recoveryCategory,
          annotation.pullReason,
          annotation.returnReason,
          createdAt,
          now,
        ]
      )
    }
  }

  private func fetchDayGoalPlan(
    whereSQL: String,
    arguments: StatementArguments,
    orderSQL: String = "",
    label: String
  ) -> DayGoalPlan? {
    try? timedRead(label) { db in
      guard
        let row = try Row.fetchOne(
          db,
          sql: """
                SELECT day, focus_target_minutes, distraction_limit_minutes, is_skipped,
                       created_at, updated_at
                FROM day_goals
                WHERE \(whereSQL)
                \(orderSQL)
                LIMIT 1
            """,
          arguments: arguments
        )
      else {
        return nil
      }

      let day: String = row["day"]
      let categories = try Row.fetchAll(
        db,
        sql: """
              SELECT kind, category_id, category_name, category_color_hex, sort_order
              FROM day_goal_categories
              WHERE day = ?
              ORDER BY kind, sort_order
          """,
        arguments: [day]
      )
      let focusWindows = try Row.fetchAll(
        db,
        sql: """
              SELECT id, day, start_minutes, end_minutes, label, focus_category_ids,
                     created_at, updated_at
              FROM day_focus_windows
              WHERE day = ?
              ORDER BY start_minutes ASC, updated_at DESC
          """,
        arguments: [day]
      ).compactMap { row -> DayFocusWindow? in
        DayFocusWindow(
          id: row["id"],
          day: row["day"],
          startMinutes: row["start_minutes"],
          endMinutes: row["end_minutes"],
          label: row["label"],
          focusCategoryIDs: decodeStringArray(row["focus_category_ids"]) ?? [],
          createdAt: row["created_at"],
          updatedAt: row["updated_at"]
        )
      }

      var focusCategories: [DayGoalCategorySnapshot] = []
      var distractionCategories: [DayGoalCategorySnapshot] = []

      for categoryRow in categories {
        let kindRaw: String = categoryRow["kind"]
        guard let kind = DayGoalCategoryKind(rawValue: kindRaw) else { continue }

        let snapshot = DayGoalCategorySnapshot(
          categoryID: categoryRow["category_id"],
          name: categoryRow["category_name"],
          colorHex: categoryRow["category_color_hex"],
          sortOrder: categoryRow["sort_order"]
        )

        switch kind {
        case .focus:
          focusCategories.append(snapshot)
        case .distraction:
          distractionCategories.append(snapshot)
        }
      }

      let isSkipped: Int = row["is_skipped"]

      return DayGoalPlan(
        day: day,
        focusTargetMinutes: row["focus_target_minutes"],
        distractionLimitMinutes: row["distraction_limit_minutes"],
        focusCategories: focusCategories,
        distractionCategories: distractionCategories,
        focusWindows: focusWindows,
        isSkipped: isSkipped != 0,
        createdAt: row["created_at"],
        updatedAt: row["updated_at"]
      )
    }
  }

  private func insertGoalCategories(
    _ categories: [DayGoalCategorySnapshot],
    kind: DayGoalCategoryKind,
    day: String,
    db: Database
  ) throws {
    for (index, category) in categories.enumerated() {
      try db.execute(
        sql: """
              INSERT INTO day_goal_categories(
                  day, kind, category_id, category_name, category_color_hex, sort_order
              )
              VALUES (?, ?, ?, ?, ?, ?)
          """,
        arguments: [
          day,
          kind.rawValue,
          category.categoryID,
          category.name,
          category.colorHex,
          index,
        ])
    }
  }

  private func insertFocusWindows(
    _ windows: [DayFocusWindow],
    day: String,
    db: Database
  ) throws {
    for window in windows.filter(\.isValid) {
      let createdAt = window.createdAt > 0 ? window.createdAt : Int(Date().timeIntervalSince1970)
      let updatedAt = window.updatedAt > 0 ? window.updatedAt : createdAt
      try db.execute(
        sql: """
              INSERT INTO day_focus_windows(
                  id, day, start_minutes, end_minutes, label, focus_category_ids,
                  created_at, updated_at
              )
              VALUES (?, ?, ?, ?, ?, ?, ?, ?)
          """,
        arguments: [
          window.id,
          day,
          window.startMinutes,
          window.endMinutes,
          window.label,
          encodeStringArray(window.focusCategoryIDs),
          createdAt,
          updatedAt,
        ])
    }
  }

  private func encodeStringArray(_ values: [String]) -> String {
    guard let data = try? JSONEncoder().encode(values),
      let string = String(data: data, encoding: .utf8)
    else {
      return Self.emptyJSONArray
    }
    return string
  }

  private func decodeStringArray(_ rawValue: String?) -> [String]? {
    guard let rawValue, let data = rawValue.data(using: .utf8) else {
      return nil
    }
    return try? JSONDecoder().decode([String].self, from: data)
  }
}
