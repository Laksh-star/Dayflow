//
//  DayDistractionSummarySection.swift
//  Dayflow
//
//  Distraction section for the Day Summary right rail.
//

import SwiftUI

struct DayDistractionSummarySection: View {
  let totalCapturedText: String
  let totalDistractedText: String
  let distractedRatio: Double
  let patternTitle: String
  let patternDescription: String
  let focusDriftSnapshot: DayFocusDriftSnapshot
  let recoveryAnnotationsByEventID: [String: DayRecoveryAnnotation]
  let isSelectionEmpty: Bool
  let categories: [TimelineCategory]
  let selectedCategoryIDs: Set<UUID>
  let isEditingCategories: Bool
  var onEditCategories: () -> Void
  var onToggleCategory: (TimelineCategory) -> Void
  var onDoneEditing: () -> Void

  private enum Design {
    static let sectionSpacing: CGFloat = 16
    static let editButtonSize: CGFloat = 20
    static let editorWidth: CGFloat = 358
    static let editorOffsetX: CGFloat = -18
    static let editorOffsetY: CGFloat = 28
    static let titleColor = Color(hex: "333333")
    static let subtitleColor = Color(hex: "707070")
  }

  var body: some View {
    VStack(alignment: .leading, spacing: Design.sectionSpacing) {
      header

      if isSelectionEmpty {
        Text("Edit categories to calculate distractions.")
          .font(.custom("Figtree", size: 11))
          .foregroundColor(Design.subtitleColor)
      }

      DistractionSummaryCard(
        totalCaptured: totalCapturedText,
        totalDistracted: totalDistractedText,
        distractedRatio: distractedRatio,
        patternTitle: patternTitle,
        patternDescription: patternDescription
      )
      .frame(maxWidth: .infinity)

      if focusDriftSnapshot.recoveryCount > 0 || focusDriftSnapshot.unresolvedRecoveryCount > 0 {
        RecoveryLoopCard(
          snapshot: focusDriftSnapshot,
          annotationsByEventID: recoveryAnnotationsByEventID
        )
      }
    }
    .opacity(isSelectionEmpty ? 0.45 : 1)
    .overlay(alignment: .topLeading) {
      if isEditingCategories {
        DayCategorySelectionEditor(
          categories: categories,
          selectedCategoryIDs: selectedCategoryIDs,
          helperText: "Pick the categories that count towards Distractions",
          onToggle: onToggleCategory,
          onDone: onDoneEditing
        )
        .frame(width: Design.editorWidth, alignment: .leading)
        .offset(x: Design.editorOffsetX, y: Design.editorOffsetY)
        .onTapGesture {}
      }
    }
  }

  private var header: some View {
    HStack(alignment: .center, spacing: 6) {
      Text("Distractions so far")
        .font(.custom("InstrumentSerif-Regular", size: 22))
        .foregroundColor(Design.titleColor)

      Spacer()

      CategoryEditCircleButton(
        action: onEditCategories,
        diameter: Design.editButtonSize
      )
    }
  }
}

private struct RecoveryLoopCard: View {
  let snapshot: DayFocusDriftSnapshot
  let annotationsByEventID: [String: DayRecoveryAnnotation]

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      VStack(alignment: .leading, spacing: 3) {
        Text("Recovery Loop")
          .font(.custom("InstrumentSerif-Regular", size: 16))
          .foregroundColor(Color(hex: "333333"))
        Text("Tracks drift and return events only inside planned blocks.")
          .font(.custom("Figtree", size: 11))
          .foregroundColor(Color(hex: "707070"))
      }

      HStack(spacing: 14) {
        metric(title: "Recoveries", value: "\(snapshot.recoveryCount)")
        metric(title: "Avg return", value: snapshot.averageRecoveryMinutes.map { "\($0)m" } ?? "—")
        metric(title: "Unresolved", value: "\(snapshot.unresolvedRecoveryCount)")
      }

      VStack(alignment: .leading, spacing: 8) {
        ForEach(snapshot.recoveryEvents.prefix(4)) { event in
          VStack(alignment: .leading, spacing: 2) {
            Text(line(for: event))
              .font(.custom("Figtree", size: 12).weight(.medium))
              .foregroundColor(Color(hex: "333333"))
              .fixedSize(horizontal: false, vertical: true)

            if let annotation = annotationsByEventID[event.id] {
              let note = [annotation.pullReason, annotation.returnReason]
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: " • ")
              if !note.isEmpty {
                Text(note)
                  .font(.custom("Figtree", size: 11))
                  .foregroundColor(Color(hex: "707070"))
                  .fixedSize(horizontal: false, vertical: true)
              }
            }
          }
        }
      }

      if snapshot.mostCommonDriftCategories.isEmpty == false {
        Text("Common drift: \(snapshot.mostCommonDriftCategories.joined(separator: ", "))")
          .font(.custom("Figtree", size: 11))
          .foregroundColor(Color(hex: "707070"))
      }
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 12)
    .background(Color(hex: "F7F7F7"))
    .overlay(
      RoundedRectangle(cornerRadius: 8)
        .stroke(Color.white, lineWidth: 1)
    )
    .clipShape(RoundedRectangle(cornerRadius: 8))
  }

  private func metric(title: String, value: String) -> some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(title)
        .font(.custom("Figtree", size: 11))
        .foregroundColor(Color(hex: "707070"))
      Text(value)
        .font(.custom("InstrumentSerif-Regular", size: 18))
        .foregroundColor(Color(hex: "F3854B"))
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private func line(for event: DayRecoveryEvent) -> String {
    if event.recovered, let recoveryCategory = event.recoveryCategory {
      return "Drifted for \(event.driftMinutes) min, returned via \(recoveryCategory)."
    }
    return "Drift unresolved in \(timeRange(start: event.windowStartMinutes, end: event.windowEndMinutes))."
  }

  private func timeRange(start: Int, end: Int) -> String {
    "\(clock(start)) - \(clock(end))"
  }

  private func clock(_ minutes: Int) -> String {
    let clamped = ((minutes % (24 * 60)) + (24 * 60)) % (24 * 60)
    let hour24 = clamped / 60
    let minute = clamped % 60
    let period = hour24 >= 12 ? "PM" : "AM"
    let hour12 = hour24 == 0 ? 12 : (hour24 > 12 ? hour24 - 12 : hour24)
    return String(format: "%d:%02d %@", hour12, minute, period)
  }
}
