import AppKit
import SwiftUI

struct WeeklyInteractionGraphPrototypeSection: View {
  let snapshot: WeeklyInteractionGraphSnapshot
  @State private var selectedNodeID: String?

  enum Design {
    static let sectionSize = CGSize(width: 660, height: 706)
    static let cornerRadius: CGFloat = 6
    static let borderColor = Color(hex: "E7DDD5")
    static let background = Color(hex: "FBF6F0")
    static let titleColor = Color(hex: "B46531")
    static let titleOrigin = CGPoint(x: 29, y: 22)
    static let subtitleOrigin = CGPoint(x: 29, y: 56)
    static let graphOrigin = CGPoint(x: 24, y: 92)
    static let graphSize = CGSize(width: 602, height: 438)
    static let inspectorOrigin = CGPoint(x: 29, y: 540)
    static let inspectorSize = CGSize(width: 602, height: 86)
    static let legendY: CGFloat = 668
  }

  var layout: WeeklyInteractionGraphLayout {
    WeeklyInteractionGraphLayoutBuilder.layout(
      snapshot: snapshot,
      in: CGRect(origin: .zero, size: Design.graphSize)
    )
  }

  var body: some View {
    let layout = layout

    ZStack(alignment: .topLeading) {
      RoundedRectangle(cornerRadius: Design.cornerRadius, style: .continuous)
        .fill(Design.background)

      Text(snapshot.title)
        .font(.custom("InstrumentSerif-Regular", size: 20))
        .foregroundStyle(Design.titleColor)
        .offset(x: Design.titleOrigin.x, y: Design.titleOrigin.y)

      Text(snapshot.subtitle)
        .font(.custom("Figtree-Regular", size: 12))
        .foregroundStyle(.black)
        .offset(x: Design.subtitleOrigin.x, y: Design.subtitleOrigin.y)

      graphLayer(layout: layout)
        .frame(width: Design.graphSize.width, height: Design.graphSize.height)
        .offset(x: Design.graphOrigin.x, y: Design.graphOrigin.y)

      WeeklyInteractionGraphInspector(
        node: selectedNode,
        connections: connections(for: selectedNodeID)
      )
      .frame(width: Design.inspectorSize.width, height: Design.inspectorSize.height)
      .offset(x: Design.inspectorOrigin.x, y: Design.inspectorOrigin.y)

      WeeklyInteractionGraphLegend()
        .frame(maxWidth: .infinity)
        .offset(y: Design.legendY)
    }
    .frame(width: Design.sectionSize.width, height: Design.sectionSize.height)
    .clipShape(RoundedRectangle(cornerRadius: Design.cornerRadius, style: .continuous))
    .overlay(
      RoundedRectangle(cornerRadius: Design.cornerRadius, style: .continuous)
        .stroke(Design.borderColor, lineWidth: 1)
    )
  }

  func graphLayer(layout: WeeklyInteractionGraphLayout) -> some View {
    ZStack {
      Canvas { context, _ in
        for edge in layout.edges.sorted(by: edgeSort(lhs:rhs:)) {
          context.stroke(
            edge.path,
            with: .color(edge.color.opacity(edge.opacity)),
            style: StrokeStyle(lineWidth: edge.lineWidth, lineCap: .round, lineJoin: .round)
          )
        }

        for dot in layout.connectorDots {
          let rect = CGRect(
            x: dot.center.x - (dot.diameter / 2),
            y: dot.center.y - (dot.diameter / 2),
            width: dot.diameter,
            height: dot.diameter
          )
          let path = Path(ellipseIn: rect)
          context.fill(path, with: .color(Design.background))
          context.stroke(
            path,
            with: .color(dot.color),
            lineWidth: 1.5
          )
        }
      }

      ForEach(layout.nodes) { node in
        Button {
          selectedNodeID = selectedNodeID == node.id ? nil : node.id
        } label: {
          WeeklyInteractionGraphNodeBadge(
            node: node,
            isSelected: selectedNodeID == node.id
          )
        }
        .buttonStyle(.plain)
        .pointingHandCursorOnHover(reassertOnPressEnd: true)
        .frame(width: node.diameter, height: node.diameter)
        .position(node.center)
      }
    }
  }

  func edgeSort(
    lhs: WeeklyInteractionGraphEdgeLayout,
    rhs: WeeklyInteractionGraphEdgeLayout
  ) -> Bool {
    if lhs.zIndex == rhs.zIndex {
      return lhs.id < rhs.id
    }
    return lhs.zIndex < rhs.zIndex
  }

  private var selectedNode: WeeklyInteractionGraphNode? {
    guard let selectedNodeID else { return nil }
    return snapshot.nodes.first(where: { $0.id == selectedNodeID })
  }

  private func connections(for nodeID: String?) -> [WeeklyInteractionGraphConnection] {
    guard let nodeID else { return [] }
    let namesByID = Dictionary(uniqueKeysWithValues: snapshot.nodes.map { ($0.id, $0.title) })
    var counts: [String: Int] = [:]

    for edge in snapshot.edges {
      if edge.sourceID == nodeID {
        counts[edge.targetID, default: 0] += edge.transitionCount
      } else if edge.targetID == nodeID {
        counts[edge.sourceID, default: 0] += edge.transitionCount
      }
    }

    return counts.compactMap { id, count in
      guard let title = namesByID[id] else { return nil }
      return WeeklyInteractionGraphConnection(id: id, title: title, count: count)
    }
    .sorted {
      if $0.count == $1.count {
        return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
      }
      return $0.count > $1.count
    }
    .prefix(2)
    .map { $0 }
  }
}

private struct WeeklyInteractionGraphConnection: Identifiable {
  let id: String
  let title: String
  let count: Int
}

private struct WeeklyInteractionGraphInspector: View {
  let node: WeeklyInteractionGraphNode?
  let connections: [WeeklyInteractionGraphConnection]

  var body: some View {
    VStack(alignment: .leading, spacing: 7) {
      if let node {
        HStack(alignment: .firstTextBaseline) {
          Text(node.title)
            .font(.custom("Figtree-SemiBold", size: 13))
            .foregroundStyle(Color(hex: "2A2521"))
          Spacer()
          Text(durationText(node.totalMinutes))
            .font(.custom("SpaceMono-Regular", size: 11))
            .foregroundStyle(Color(hex: "6F6258"))
        }

        HStack(spacing: 14) {
          contextMetric("Work", minutes: node.workMinutes, color: .work)
          contextMetric("Personal", minutes: node.personalMinutes, color: .personal)
          contextMetric("Distraction", minutes: node.distractionMinutes, color: .distraction)
          Spacer(minLength: 0)
        }

        Text(connectionText)
          .font(.custom("Figtree-Regular", size: 11))
          .foregroundStyle(Color(hex: "6F6258"))
          .lineLimit(1)
      } else {
        Text("Inspect an application")
          .font(.custom("Figtree-SemiBold", size: 13))
          .foregroundStyle(Color(hex: "2A2521"))
        Text("Select a circle to see its recorded time split and strongest switches.")
          .font(.custom("Figtree-Regular", size: 11))
          .foregroundStyle(Color(hex: "6F6258"))
      }
    }
    .padding(.horizontal, 13)
    .padding(.vertical, 10)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    .background(Color(hex: "F7F1EB"))
    .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
    .overlay {
      RoundedRectangle(cornerRadius: 5, style: .continuous)
        .stroke(Color(hex: "E7DDD5"), lineWidth: 1)
    }
  }

  private var connectionText: String {
    guard !connections.isEmpty else {
      return "No prominent application switches were recorded for this app."
    }
    let values = connections.map { "\($0.title) (\($0.count))" }.joined(separator: "  ·  ")
    return "Most switches with: \(values)"
  }

  private func contextMetric(
    _ title: String,
    minutes: Int,
    color: WeeklyInteractionGraphCategory
  ) -> some View {
    HStack(spacing: 4) {
      Circle()
        .fill(color.borderColor)
        .frame(width: 6, height: 6)
      Text("\(title) \(durationText(minutes))")
        .font(.custom("Figtree-Regular", size: 10))
        .foregroundStyle(Color(hex: "6F6258"))
    }
  }

  private func durationText(_ minutes: Int) -> String {
    guard minutes >= 60 else { return "\(minutes)m" }
    return "\(minutes / 60)h \(minutes % 60)m"
  }
}
