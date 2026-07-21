import SwiftUI

struct WeeklyHeader: View {
  let title: String
  let canNavigateForward: Bool
  let onPrevious: () -> Void
  let onNext: () -> Void
  var onExportMarkdown: (() -> Void)? = nil

  var body: some View {
    ZStack {
      HStack(spacing: 14) {
        WeeklyNavigationButton(assetName: "LeftArrow") {
          onPrevious()
        }

        Text(title)
          .font(.custom("InstrumentSerif-Regular", size: 20))
          .foregroundStyle(Color.black)
          .multilineTextAlignment(.center)
          .frame(width: 344)

        WeeklyNavigationButton(assetName: "RightArrow", isEnabled: canNavigateForward) {
          onNext()
        }
      }

      if let onExportMarkdown {
        Button(action: onExportMarkdown) {
          HStack(spacing: 6) {
            Image(systemName: "square.and.arrow.up")
              .font(.system(size: 12, weight: .semibold))

            Text("Export Markdown")
              .font(.custom("Figtree-Medium", size: 13))
          }
          .foregroundStyle(Color(hex: "5E4B3E"))
          .padding(.horizontal, 12)
          .padding(.vertical, 8)
          .background(Color(hex: "FFF7EF"))
          .clipShape(Capsule(style: .continuous))
          .overlay(
            Capsule(style: .continuous)
              .stroke(Color(hex: "E8D8C8"), lineWidth: 1.2)
          )
        }
        .buttonStyle(DayflowPressScaleButtonStyle())
        .pointingHandCursorOnHover(reassertOnPressEnd: true)
        .frame(maxWidth: .infinity, alignment: .trailing)
      }
    }
    .frame(maxWidth: .infinity)
    .frame(height: 29)
  }
}

private struct WeeklyNavigationButton: View {
  let assetName: String
  var isEnabled = true
  let action: () -> Void

  @State private var isHovering = false

  private let arrowSize: CGFloat = 24
  private let hoverCircleSize: CGFloat = 30

  var body: some View {
    Button {
      guard isEnabled else { return }
      action()
    } label: {
      ZStack {
        Circle()
          .fill(Color(hex: "FFEBD3").opacity(0.79))
          .frame(width: hoverCircleSize, height: hoverCircleSize)
          .opacity(isHovering && isEnabled ? 1 : 0)

        Image(assetName)
          .resizable()
          .scaledToFit()
          .frame(width: arrowSize, height: arrowSize)
          .opacity(isEnabled ? 1 : 0.35)
      }
      .frame(width: hoverCircleSize, height: hoverCircleSize)
      .contentShape(Circle())
    }
    .buttonStyle(DayflowPressScaleButtonStyle(enabled: isEnabled))
    .disabled(!isEnabled)
    .onHover { hovering in
      withAnimation(.easeOut(duration: 0.12)) {
        isHovering = isEnabled && hovering
      }
    }
    .onChange(of: isEnabled) { _, enabled in
      if !enabled {
        isHovering = false
      }
    }
    .pointingHandCursorOnHover(enabled: isEnabled, reassertOnPressEnd: true)
  }
}
