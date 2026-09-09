//
//  LogoBadgeView.swift
//  Dayflow
//
//  Plain logo asset renderer.
//

import SwiftUI

struct LogoBadgeView: View {
  let imageName: String
  var size: CGFloat = 100

  var body: some View {
    Image(imageName)
      .resizable()
      .interpolation(.high)
      .scaledToFit()
      .frame(width: size, height: size)
      .accessibilityHidden(true)
  }
}

struct DaywardBrandMark: View {
  var size: CGFloat = 100

  var body: some View {
    ZStack {
      Circle()
        .fill(Color(hex: "FFF5EE"))
        .overlay {
          Circle()
            .stroke(Color(hex: "F1D9CB"), lineWidth: max(1, size * 0.025))
        }

      Image(systemName: "sun.horizon.fill")
        .font(.system(size: size * 0.48, weight: .medium))
        .foregroundStyle(Color(hex: "FF7A45"))
    }
    .frame(width: size, height: size)
    .accessibilityLabel("Dayward")
  }
}
