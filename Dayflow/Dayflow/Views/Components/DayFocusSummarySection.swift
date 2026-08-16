//
//  DayFocusSummarySection.swift
//  Dayflow
//
//  Focus section for the Day Summary right rail.
//

import SwiftUI

struct DayFocusSummarySection: View {
  let totalFocusText: String
  let focusBlocks: [FocusBlock]
  let focusDriftSnapshot: DayFocusDriftSnapshot
  let isSelectionEmpty: Bool
  let categories: [TimelineCategory]
  let selectedCategoryIDs: Set<UUID>
  let isEditingCategories: Bool
  var onEditCategories: () -> Void
  var onToggleCategory: (TimelineCategory) -> Void
  var onDoneEditing: () -> Void

  private enum Design {
    static let sectionSpacing: CGFloat = 12
    static let cardsSpacing: CGFloat = 8
    static let editButtonSize: CGFloat = 20
    static let editorWidth: CGFloat = 358
    static let editorOffsetX: CGFloat = -18
    static let editorOffsetY: CGFloat = 28
    static let titleColor = Color(hex: "333333")
    static let subtitleColor = Color(hex: "707070")
    static let iconColor = Color(hex: "CFC7BE")
  }

  var body: some View {
    VStack(alignment: .leading, spacing: Design.sectionSpacing) {
      header

      if isSelectionEmpty {
        Text("Edit categories to calculate focus.")
          .font(.custom("Figtree", size: 11))
          .foregroundColor(Design.subtitleColor)
      }

      VStack(spacing: Design.cardsSpacing) {
        TotalFocusCard(value: totalFocusText)

        LongestFocusCard(focusBlocks: focusBlocks)

        if focusDriftSnapshot.windows.isEmpty == false {
          PlanVsDriftCard(snapshot: focusDriftSnapshot)
          AttentionGradientCard(snapshot: focusDriftSnapshot)
        }
      }
      .opacity(isSelectionEmpty ? 0.45 : 1)
    }
    .overlay(alignment: .topLeading) {
      if isEditingCategories {
        DayCategorySelectionEditor(
          categories: categories,
          selectedCategoryIDs: selectedCategoryIDs,
          helperText: "Pick the categories that count towards Focus",
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
      Text("Your focus")
        .font(.custom("InstrumentSerif-Regular", size: 22))
        .foregroundColor(Design.titleColor)

      Image(systemName: "info.circle")
        .font(.system(size: 12))
        .foregroundColor(Design.iconColor)

      Spacer()

      CategoryEditCircleButton(
        action: onEditCategories,
        diameter: Design.editButtonSize
      )
    }
  }
}

private struct PlanVsDriftCard: View {
  let snapshot: DayFocusDriftSnapshot

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      VStack(alignment: .leading, spacing: 3) {
        Text("Plan vs Drift")
          .font(.custom("InstrumentSerif-Regular", size: 16))
          .foregroundColor(Color(hex: "333333"))
        Text("Measures only the time inside your focus windows.")
          .font(.custom("Figtree", size: 11))
          .foregroundColor(Color(hex: "707070"))
      }

      HStack(spacing: 12) {
        metric(title: "Planned", value: shortMinutes(snapshot.plannedMinutes), color: Color(hex: "9C9C9C"))
        metric(title: "On plan", value: shortMinutes(snapshot.onPlanMinutes), color: Color(hex: "5E7FC0"))
        metric(title: "Drift", value: shortMinutes(snapshot.driftMinutes), color: Color(hex: "FF694B"))
      }

      GeometryReader { geo in
        let total = max(snapshot.plannedMinutes, snapshot.onPlanMinutes + snapshot.driftMinutes, 1)
        let onPlanWidth = geo.size.width * CGFloat(snapshot.onPlanMinutes) / CGFloat(total)
        let driftWidth = geo.size.width * CGFloat(snapshot.driftMinutes) / CGFloat(total)

        HStack(spacing: 0) {
          RoundedRectangle(cornerRadius: 4)
            .fill(Color(hex: "628CFF"))
            .frame(width: max(0, onPlanWidth))

          RoundedRectangle(cornerRadius: 4)
            .fill(Color(hex: "FF8C69"))
            .frame(width: max(0, driftWidth))

          Spacer(minLength: 0)
        }
        .frame(height: 10)
        .background(Color(hex: "ECECEC"))
        .clipShape(RoundedRectangle(cornerRadius: 4))
      }
      .frame(height: 10)

      VStack(alignment: .leading, spacing: 6) {
        ForEach(snapshot.windows.prefix(3)) { window in
          VStack(alignment: .leading, spacing: 2) {
            Text(window.label)
              .font(.custom("Figtree", size: 12).weight(.medium))
              .foregroundColor(Color(hex: "333333"))
              .lineLimit(1)
            HStack {
              Text(timeRange(start: window.startMinutes, end: window.endMinutes))
                .font(.custom("Figtree", size: 11))
                .foregroundColor(Color(hex: "707070"))
              Spacer()
              Text("\(shortMinutes(window.onPlanMinutes)) on plan")
                .font(.custom("Figtree", size: 11))
                .foregroundColor(Color(hex: "628CFF"))
              Text("•")
                .font(.custom("Figtree", size: 11))
                .foregroundColor(Color(hex: "A0A0A0"))
              Text("\(shortMinutes(window.driftMinutes)) drift")
                .font(.custom("Figtree", size: 11))
                .foregroundColor(Color(hex: "FF694B"))
            }
          }
        }
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

  private func metric(title: String, value: String, color: Color) -> some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(title)
        .font(.custom("Figtree", size: 11))
        .foregroundColor(Color(hex: "707070"))
      Text(value)
        .font(.custom("InstrumentSerif-Regular", size: 18))
        .foregroundColor(color)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private func shortMinutes(_ minutes: Int) -> String {
    let hours = minutes / 60
    let mins = minutes % 60
    if hours > 0 && mins > 0 {
      return "\(hours)h \(mins)m"
    }
    if hours > 0 {
      return "\(hours)h"
    }
    return "\(mins)m"
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

private struct AttentionGradientCard: View {
  let snapshot: DayFocusDriftSnapshot

  private let states: [AttentionGradientState] = [.friction, .wandering, .reEntry, .steady, .lockedIn]

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      VStack(alignment: .leading, spacing: 3) {
        Text("Attention Gradient")
          .font(.custom("InstrumentSerif-Regular", size: 16))
          .foregroundColor(Color(hex: "333333"))
        Text("Based on the last 30 minutes inside your current focus windows.")
          .font(.custom("Figtree", size: 11))
          .foregroundColor(Color(hex: "707070"))
      }

      HStack(spacing: 4) {
        ForEach(states, id: \.rawValue) { state in
          RoundedRectangle(cornerRadius: 4)
            .fill(color(for: state))
            .overlay(
              RoundedRectangle(cornerRadius: 4)
                .stroke(snapshot.attentionState == state ? Color.black.opacity(0.18) : .clear, lineWidth: 1)
            )
            .frame(height: 12)
            .opacity(snapshot.attentionState == state ? 1 : 0.45)
        }
      }

      if let state = snapshot.attentionState {
        Text(snapshot.attentionMessage.isEmpty ? state.explanation : snapshot.attentionMessage)
          .font(.custom("Figtree", size: 12))
          .foregroundColor(Color(hex: "333333"))
          .fixedSize(horizontal: false, vertical: true)
      } else {
        Text("No recent focus-window context yet.")
          .font(.custom("Figtree", size: 12))
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

  private func color(for state: AttentionGradientState) -> Color {
    switch state {
    case .friction:
      return Color(hex: "D8C8BC")
    case .wandering:
      return Color(hex: "F3A08A")
    case .reEntry:
      return Color(hex: "F3D38A")
    case .steady:
      return Color(hex: "9FD3B2")
    case .lockedIn:
      return Color(hex: "628CFF")
    }
  }
}

private struct TotalFocusCard: View {
  let value: String

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      HStack(spacing: 6) {
        Text("Total focus time")
          .font(.custom("InstrumentSerif-Regular", size: 16))
          .foregroundColor(Color(hex: "333333"))

        Image(systemName: "info.circle")
          .font(.system(size: 12))
          .foregroundColor(Color(hex: "CFC7BE"))

        Spacer()
      }

      Text(value)
        .font(.custom("InstrumentSerif-Regular", size: 34))
        .foregroundColor(Color(hex: "F3854B"))
        .frame(maxWidth: .infinity, alignment: .leading)
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 12)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(Color(hex: "F7F7F7"))
    .overlay(
      RoundedRectangle(cornerRadius: 8)
        .stroke(Color.white, lineWidth: 1)
    )
    .clipShape(RoundedRectangle(cornerRadius: 8))
  }
}
