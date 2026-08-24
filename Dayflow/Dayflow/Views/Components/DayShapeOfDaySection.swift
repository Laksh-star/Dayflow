import SwiftUI

private enum DayShapeDisplayMode: String, CaseIterable, Identifiable {
  case constellation = "Constellation"
  case trace = "Day Trace"

  var id: String { rawValue }
}

struct DayShapeOfDaySection: View {
  let archive: DayShapeArchive?
  let isCurrentDay: Bool

  @State private var mode: DayShapeDisplayMode = .constellation
  @State private var selectedPointID: String?

  private enum Design {
    static let titleColor = Color(hex: "333333")
    static let subtitleColor = Color(hex: "707070")
    static let borderColor = Color(hex: "E8E1DA")
    static let panelColor = Color.white.opacity(0.78)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack(alignment: .top, spacing: 16) {
        VStack(alignment: .leading, spacing: 3) {
          Text("Shape of your day")
            .font(.custom("InstrumentSerif-Regular", size: 24))
            .foregroundStyle(Design.titleColor)
          Text(subtitle)
            .font(.custom("Figtree-Regular", size: 12))
            .foregroundStyle(Design.subtitleColor)
        }

        Spacer()

        if archive != nil {
          Picker("Shape view", selection: $mode) {
            ForEach(DayShapeDisplayMode.allCases) { displayMode in
              Text(displayMode.rawValue).tag(displayMode)
            }
          }
          .pickerStyle(.segmented)
          .labelsHidden()
          .frame(width: 196)
        }
      }

      if let archive {
        Group {
          switch mode {
          case .constellation:
            ConstellationShapeView(archive: archive, selectedPointID: $selectedPointID)
          case .trace:
            DayTraceShapeView(archive: archive, selectedPointID: $selectedPointID)
          }
        }
        .frame(height: 300)
        .padding(12)
        .background(
          RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(Color(hex: "FFFDF9"))
        )
        .overlay(
          RoundedRectangle(cornerRadius: 6, style: .continuous)
            .stroke(Design.borderColor, lineWidth: 1)
        )

        threadLegend(archive)

        if let selected = archive.points.first(where: { $0.id == selectedPointID }) {
          Text(selected.title)
            .font(.custom("Figtree-Medium", size: 12))
            .foregroundStyle(Design.titleColor)
            .lineLimit(1)
        } else {
          Text(mode == .constellation
            ? "Threads are inferred from card titles, projects, apps, domains, and time continuity."
            : "Focus windows are shown as quiet background ranges when you have planned them.")
            .font(.custom("Figtree-Regular", size: 12))
            .foregroundStyle(Design.subtitleColor)
        }
      } else {
        Text(isCurrentDay
          ? "Shape is forming as processed cards arrive. It becomes a completed daily archive after the day closes."
          : "No processed cards are available for this day yet.")
          .font(.custom("Figtree-Regular", size: 12))
          .foregroundStyle(Design.subtitleColor)
          .frame(maxWidth: .infinity, minHeight: 110, alignment: .center)
          .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
              .fill(Color(hex: "F7F2ED"))
          )
      }
    }
    .padding(16)
    .background(
      RoundedRectangle(cornerRadius: 6, style: .continuous)
        .fill(Design.panelColor)
    )
    .overlay(
      RoundedRectangle(cornerRadius: 6, style: .continuous)
        .stroke(Design.borderColor, lineWidth: 1)
    )
  }

  private var subtitle: String {
    guard let archive else {
      return isCurrentDay ? "A local reflection of the work that is taking shape." : "A local reflection of completed work."
    }
    return "\(archive.points.count) captured intervals · \(formatDuration(archive.totalMinutes)) · saved locally"
  }

  private func threadLegend(_ archive: DayShapeArchive) -> some View {
    FlowLayout(spacing: 7) {
      ForEach(archive.threads) { thread in
        HStack(spacing: 5) {
          Circle()
            .fill(Color(hex: thread.colorHex))
            .frame(width: 7, height: 7)
          Text(thread.label)
            .font(.custom("Figtree-Regular", size: 11))
            .foregroundStyle(Design.subtitleColor)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(Color(hex: "F7F2ED"))
        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
      }
    }
  }

  private func formatDuration(_ minutes: Int) -> String {
    let hours = minutes / 60
    let remainder = minutes % 60
    if hours == 0 { return "\(remainder)m" }
    if remainder == 0 { return "\(hours)h" }
    return "\(hours)h \(remainder)m"
  }
}

private struct ConstellationShapeView: View {
  let archive: DayShapeArchive
  @Binding var selectedPointID: String?

  var body: some View {
    GeometryReader { proxy in
      let size = proxy.size
      let threadByID = Dictionary(uniqueKeysWithValues: archive.threads.map { ($0.id, $0) })

      ZStack {
        ForEach(archive.threads) { thread in
          let threadPoints = archive.points.filter { $0.threadID == thread.id }.sorted { $0.startMinute < $1.startMinute }
          Path { path in
            guard let first = threadPoints.first else { return }
            path.move(to: CGPoint(x: first.constellationX * size.width, y: first.constellationY * size.height))
            for point in threadPoints.dropFirst() {
              path.addLine(to: CGPoint(x: point.constellationX * size.width, y: point.constellationY * size.height))
            }
          }
          .stroke(Color(hex: thread.colorHex).opacity(0.22), style: StrokeStyle(lineWidth: 1.2, lineCap: .round))
        }

        ForEach(archive.points) { point in
          let thread = threadByID[point.threadID]
          let isSelected = selectedPointID == point.id
          Circle()
            .fill(Color(hex: thread?.colorHex ?? "B5AAA2"))
            .frame(width: pointSize(point.durationMinutes, selected: isSelected), height: pointSize(point.durationMinutes, selected: isSelected))
            .overlay(Circle().stroke(Color.white.opacity(0.95), lineWidth: 2))
            .shadow(color: Color.black.opacity(isSelected ? 0.16 : 0.08), radius: isSelected ? 5 : 2)
            .position(x: point.constellationX * size.width, y: point.constellationY * size.height)
            .contentShape(Circle())
            .onTapGesture { selectedPointID = point.id }
            .accessibilityLabel(point.title)
        }

        HStack {
          Text("morning")
          Spacer()
          Text("midday")
          Spacer()
          Text("late")
        }
        .font(.custom("Figtree-Regular", size: 10))
        .foregroundStyle(Color(hex: "8B8077"))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
      }
    }
  }

  private func pointSize(_ duration: Int, selected: Bool) -> CGFloat {
    let base = min(20, max(8, 5 + sqrt(Double(duration)) * 1.5))
    return selected ? base + 5 : base
  }
}

private struct DayTraceShapeView: View {
  let archive: DayShapeArchive
  @Binding var selectedPointID: String?

  private let leftInset: CGFloat = 88
  private let topInset: CGFloat = 34

  var body: some View {
    GeometryReader { proxy in
      let size = proxy.size
      let plotWidth = max(1, size.width - leftInset - 10)
      let rows = archive.threads
      let rowHeight = max(30, (size.height - topInset - 20) / CGFloat(max(rows.count, 1)))
      let threadByID = Dictionary(uniqueKeysWithValues: rows.map { ($0.id, $0) })

      ZStack(alignment: .topLeading) {
        ForEach(archive.focusWindows) { window in
          RoundedRectangle(cornerRadius: 3)
            .fill(Color(hex: "DDE6FF").opacity(0.5))
            .frame(width: CGFloat(window.endMinute - window.startMinute) / 1_440 * plotWidth, height: size.height - topInset)
            .position(
              x: leftInset + CGFloat(window.startMinute + window.endMinute) / 2 / 1_440 * plotWidth,
              y: topInset + (size.height - topInset) / 2
            )
        }

        ForEach(Array(rows.enumerated()), id: \.element.id) { index, thread in
          let y = topInset + rowHeight * CGFloat(index) + rowHeight / 2
          Text(thread.label)
            .font(.custom("Figtree-Regular", size: 10))
            .foregroundStyle(Color(hex: "70655D"))
            .frame(width: leftInset - 12, alignment: .trailing)
            .position(x: (leftInset - 12) / 2, y: y)

          RoundedRectangle(cornerRadius: 3)
            .fill(Color(hex: "F7F2ED"))
            .frame(width: plotWidth, height: max(16, rowHeight - 10))
            .position(x: leftInset + plotWidth / 2, y: y)
        }

        ForEach([0, 360, 720, 1_080, 1_440], id: \.self) { minute in
          Text(clockLabel(for: minute))
            .font(.custom("Figtree-Regular", size: 10))
            .foregroundStyle(Color(hex: "8B8077"))
            .position(x: leftInset + CGFloat(minute) / 1_440 * plotWidth, y: 10)
        }

        ForEach(archive.threads) { thread in
          let points = archive.points.filter { $0.threadID == thread.id }.sorted { $0.startMinute < $1.startMinute }
          let rowIndex = rows.firstIndex(where: { $0.id == thread.id }) ?? 0
          let y = topInset + rowHeight * CGFloat(rowIndex) + rowHeight / 2
          Path { path in
            guard let first = points.first else { return }
            path.move(to: CGPoint(x: leftInset + CGFloat(first.startMinute + first.endMinute) / 2 / 1_440 * plotWidth, y: y))
            for point in points.dropFirst() {
              path.addLine(to: CGPoint(x: leftInset + CGFloat(point.startMinute + point.endMinute) / 2 / 1_440 * plotWidth, y: y))
            }
          }
          .stroke(Color(hex: thread.colorHex).opacity(0.35), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
        }

        ForEach(archive.points) { point in
          let thread = threadByID[point.threadID]
          let rowIndex = rows.firstIndex(where: { $0.id == point.threadID }) ?? 0
          let y = topInset + rowHeight * CGFloat(rowIndex) + rowHeight / 2
          let x = leftInset + CGFloat(point.startMinute + point.endMinute) / 2 / 1_440 * plotWidth
          let selected = selectedPointID == point.id
          Circle()
            .fill(Color(hex: thread?.colorHex ?? "B5AAA2"))
            .frame(width: selected ? 16 : 11, height: selected ? 16 : 11)
            .overlay(Circle().stroke(Color.white, lineWidth: 2))
            .position(x: x, y: y)
            .contentShape(Circle())
            .onTapGesture { selectedPointID = point.id }
            .accessibilityLabel(point.title)
        }
      }
    }
  }

  private func clockLabel(for timelineMinute: Int) -> String {
    let localMinute = (timelineMinute + 4 * 60) % (24 * 60)
    let hour = localMinute / 60
    let suffix = hour >= 12 ? "PM" : "AM"
    let displayHour = hour == 0 ? 12 : (hour > 12 ? hour - 12 : hour)
    return "\(displayHour) \(suffix)"
  }
}

private struct FlowLayout: Layout {
  var spacing: CGFloat

  func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
    layout(proposal: proposal, subviews: subviews).size
  }

  func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
    let result = layout(proposal: proposal, subviews: subviews)
    for (index, subview) in subviews.enumerated() {
      subview.place(at: CGPoint(x: bounds.minX + result.origins[index].x, y: bounds.minY + result.origins[index].y), proposal: .unspecified)
    }
  }

  private func layout(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, origins: [CGPoint]) {
    let maxWidth = proposal.width ?? .greatestFiniteMagnitude
    var x: CGFloat = 0
    var y: CGFloat = 0
    var lineHeight: CGFloat = 0
    var origins: [CGPoint] = []

    for subview in subviews {
      let size = subview.sizeThatFits(.unspecified)
      if x > 0, x + size.width > maxWidth {
        x = 0
        y += lineHeight + spacing
        lineHeight = 0
      }
      origins.append(CGPoint(x: x, y: y))
      x += size.width + spacing
      lineHeight = max(lineHeight, size.height)
    }

    return (CGSize(width: proposal.width ?? x, height: y + lineHeight), origins)
  }
}
