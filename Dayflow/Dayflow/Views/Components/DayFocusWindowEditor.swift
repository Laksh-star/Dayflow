import SwiftUI

struct DayFocusWindowEditor: View {
  @Binding var windows: [DayFocusWindow]
  let focusCategories: [DayGoalCategorySnapshot]
  var onChanged: () -> Void = {}

  private enum Design {
    static let border = Color(hex: "E7DFDF")
    static let muted = Color(hex: "7A7A7A")
    static let background = Color(hex: "FCFCFC").opacity(0.82)
    static let chipBackground = Color(hex: "F8F6F5")
    static let accent = Color(hex: "FF8046")
    static let rowLabelWidth: CGFloat = 220
    static let timeControlWidth: CGFloat = 146
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack {
        VStack(alignment: .leading, spacing: 3) {
          Text("Focus windows")
            .font(.custom("Figtree", size: 14).weight(.semibold))
            .foregroundColor(.black)
          Text("Optional: add planned blocks for drift analysis. These do not replace your daily focus goal.")
            .font(.custom("Figtree", size: 11))
            .foregroundColor(Design.muted)
          Text("These chips come from your Focus goal categories. Filled chips count as on-plan for this block; gray chips are ignored.")
            .font(.custom("Figtree", size: 11))
            .foregroundColor(Design.muted)
        }

        Spacer()

        Button {
          addWindow()
        } label: {
          Label("Add window", systemImage: "plus")
            .font(.custom("Figtree", size: 12).weight(.medium))
            .foregroundColor(.white)
            .padding(.horizontal, 10)
            .frame(height: 28)
            .background(Design.accent)
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .pointingHandCursor()
      }

      if windows.isEmpty {
        RoundedRectangle(cornerRadius: 6)
          .fill(Design.chipBackground)
          .overlay(
            Text("No focus windows yet. Add one or more blocks if you want Plan vs Drift, Recovery Loop, and Attention Gradient for specific times of day.")
              .font(.custom("Figtree", size: 12))
              .foregroundColor(Design.muted)
              .padding(.horizontal, 14)
          )
          .frame(height: 56)
      } else {
        VStack(spacing: 8) {
          ForEach(Array(windows.enumerated()), id: \.element.id) { index, window in
            FocusWindowRow(
              window: binding(for: index),
              focusCategories: focusCategories,
              onRemove: {
                windows.removeAll { $0.id == window.id }
                onChanged()
              },
              onChanged: onChanged
            )
          }
        }
      }
    }
    .padding(14)
    .background(Design.background)
    .clipShape(RoundedRectangle(cornerRadius: 6))
    .overlay(
      RoundedRectangle(cornerRadius: 6)
        .stroke(Design.border, lineWidth: 1)
    )
  }

  private func binding(for index: Int) -> Binding<DayFocusWindow> {
    Binding(
      get: { windows[index] },
      set: { windows[index] = $0 }
    )
  }

  private func addWindow() {
    let fallbackCategoryIDs = focusCategories.map(\.categoryID)
    let nextIndex = windows.count
    let template =
      DayFocusWindow.defaultWindow(
        day: windows.first?.day ?? "",
        index: nextIndex,
        focusCategoryIDs: fallbackCategoryIDs
      )
    windows.append(template)
    onChanged()
  }
}

private struct FocusWindowRow: View {
  @Binding var window: DayFocusWindow
  let focusCategories: [DayGoalCategorySnapshot]
  var onRemove: () -> Void
  var onChanged: () -> Void

  private enum Layout {
    static let rowLabelWidth: CGFloat = 220
    static let timeControlWidth: CGFloat = 146
  }

  private let increments = stride(from: 0, through: 24 * 60 - 15, by: 15).map { $0 }

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(alignment: .center, spacing: 8) {
        TextField("Window label", text: labelBinding)
          .textFieldStyle(.plain)
          .font(.custom("Figtree", size: 12))
          .padding(.horizontal, 10)
          .frame(width: Layout.rowLabelWidth, alignment: .leading)
          .frame(height: 30)
          .background(Color.white)
          .clipShape(RoundedRectangle(cornerRadius: 6))
          .overlay(
            RoundedRectangle(cornerRadius: 6)
              .stroke(Color(hex: "E6DDD5"), lineWidth: 1)
          )

        Spacer(minLength: 0)

        Button(role: .destructive, action: onRemove) {
          Image(systemName: "trash")
            .font(.system(size: 12, weight: .semibold))
            .foregroundColor(Color(hex: "8A8582"))
            .frame(width: 28, height: 28)
            .background(Color(hex: "FFF6F2"))
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .pointingHandCursor()
      }

      HStack(spacing: 8) {
        FocusWindowTimeMenu(
          title: "Start",
          selection: startBinding,
          options: increments,
          width: Layout.timeControlWidth
        )

        FocusWindowTimeMenu(
          title: "End",
          selection: endBinding,
          options: increments,
          width: Layout.timeControlWidth
        )

        VStack(alignment: .leading, spacing: 2) {
          Text(rangeSummary)
            .font(.custom("Figtree", size: 11).weight(.medium))
            .foregroundColor(Color(hex: "5F5A56"))
            .lineLimit(1)

          Text(durationSummary)
            .font(.custom("Figtree", size: 11))
            .foregroundColor(Color(hex: "7A7A7A"))
            .lineLimit(1)
        }

        Spacer(minLength: 0)
      }

      VStack(alignment: .leading, spacing: 6) {
        Text("Counts as on-plan in this window")
          .font(.custom("Figtree", size: 11).weight(.medium))
          .foregroundColor(Color(hex: "5F5A56"))

        Text("Choose one or more of your Focus goal categories for this block.")
          .font(.custom("Figtree", size: 11))
          .foregroundColor(Color(hex: "7A7A7A"))
      }

      DayGoalFlowLayout(spacing: 6, rowSpacing: 6) {
        ForEach(focusCategories) { category in
          Button {
            toggleCategory(category.categoryID)
          } label: {
            GoalCategoryChip(
              title: category.name,
              colorHex: category.colorHex,
              status: selectedCategoryIDs.contains(category.categoryID) ? .focus : .untracked,
              leadingAccessory: .selectionIndicator,
              untrackedStyle: .neutral
            )
          }
          .buttonStyle(.plain)
          .pointingHandCursor()
        }
      }
    }
    .padding(12)
    .background(Color(hex: "F8F6F5"))
    .clipShape(RoundedRectangle(cornerRadius: 6))
    .overlay(
      RoundedRectangle(cornerRadius: 6)
        .stroke(Color(hex: "E6DDD5"), lineWidth: 1)
    )
  }

  private var selectedCategoryIDs: Set<String> {
    Set(window.focusCategoryIDs)
  }

  private var durationSummary: String {
    let minutes = max(0, window.endMinutes - window.startMinutes)
    let hours = minutes / 60
    let remainder = minutes % 60
    if hours > 0 && remainder > 0 {
      return "\(hours)h \(remainder)m planned"
    }
    if hours > 0 {
      return "\(hours)h planned"
    }
    return "\(remainder)m planned"
  }

  private var rangeSummary: String {
    "\(timeString(window.startMinutes)) - \(timeString(window.endMinutes))"
  }

  private var labelBinding: Binding<String> {
    Binding(
      get: { window.label },
      set: {
        window.label = $0
        touch()
      }
    )
  }

  private var startBinding: Binding<Int> {
    Binding(
      get: { window.startMinutes },
      set: {
        window.startMinutes = $0
        if window.endMinutes <= window.startMinutes {
          window.endMinutes = min(24 * 60, window.startMinutes + 60)
        }
        touch()
      }
    )
  }

  private var endBinding: Binding<Int> {
    Binding(
      get: { window.endMinutes },
      set: {
        window.endMinutes = $0
        if window.endMinutes <= window.startMinutes {
          window.startMinutes = max(0, window.endMinutes - 60)
        }
        touch()
      }
    )
  }

  private func toggleCategory(_ categoryID: String) {
    if let existingIndex = window.focusCategoryIDs.firstIndex(of: categoryID) {
      window.focusCategoryIDs.remove(at: existingIndex)
    } else {
      window.focusCategoryIDs.append(categoryID)
    }
    touch()
  }

  private func touch() {
    window.updatedAt = Int(Date().timeIntervalSince1970)
    onChanged()
  }

  private func timeString(_ minutes: Int) -> String {
    let clamped = ((minutes % (24 * 60)) + (24 * 60)) % (24 * 60)
    let hour24 = clamped / 60
    let minute = clamped % 60
    let period = hour24 >= 12 ? "PM" : "AM"
    let hour12 = hour24 == 0 ? 12 : (hour24 > 12 ? hour24 - 12 : hour24)
    return String(format: "%d:%02d %@", hour12, minute, period)
  }
}

private struct FocusWindowTimeMenu: View {
  let title: String
  @Binding var selection: Int
  let options: [Int]
  var width: CGFloat = 132

  var body: some View {
    Menu {
      ForEach(options, id: \.self) { option in
        Button {
          selection = option
        } label: {
          Text(timeString(option))
        }
      }
    } label: {
      HStack(spacing: 6) {
        Text(title)
          .font(.custom("Figtree", size: 11))
          .foregroundColor(Color(hex: "7A7A7A"))
        Text(timeString(selection))
          .font(.custom("Figtree", size: 12).weight(.medium))
          .foregroundColor(.black)
          .lineLimit(1)
        Image(systemName: "chevron.down")
          .font(.system(size: 10, weight: .semibold))
          .foregroundColor(Color(hex: "7A7A7A"))
      }
      .padding(.horizontal, 10)
      .frame(width: width, alignment: .leading)
      .frame(height: 30)
      .background(Color.white)
      .clipShape(RoundedRectangle(cornerRadius: 6))
      .overlay(
        RoundedRectangle(cornerRadius: 6)
          .stroke(Color(hex: "E6DDD5"), lineWidth: 1)
      )
    }
    .menuStyle(.borderlessButton)
    .pointingHandCursor()
  }

  private func timeString(_ minutes: Int) -> String {
    let clamped = ((minutes % (24 * 60)) + (24 * 60)) % (24 * 60)
    let hour24 = clamped / 60
    let minute = clamped % 60
    let period = hour24 >= 12 ? "PM" : "AM"
    let hour12 = hour24 == 0 ? 12 : (hour24 > 12 ? hour24 - 12 : hour24)
    return String(format: "%d:%02d %@", hour12, minute, period)
  }
}
