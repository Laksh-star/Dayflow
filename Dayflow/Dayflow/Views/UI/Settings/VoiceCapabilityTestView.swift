import SwiftUI

struct VoiceCapabilityTestView: View {
  @Environment(\.dismiss) private var dismiss
  @StateObject private var voiceService = VoiceCapabilityService()

  var body: some View {
    VStack(alignment: .leading, spacing: 20) {
      HStack(alignment: .top) {
        VStack(alignment: .leading, spacing: 5) {
          Text("Voice review test")
            .font(.custom("InstrumentSerif", size: 28))
            .foregroundColor(SettingsStyle.text)
          Text("Developer-only local speech capability check")
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
        .foregroundColor(SettingsStyle.secondary)
        .help("Close")
      }

      VStack(alignment: .leading, spacing: 10) {
        Text(voiceService.state.message)
          .font(.custom("Figtree", size: 14))
          .foregroundColor(SettingsStyle.text)

        Text("Audio and transcript stay in memory for this test and are discarded when this panel closes.")
          .font(.custom("Figtree", size: 12))
          .foregroundColor(SettingsStyle.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }

      VoicePressToTalkButton(service: voiceService)

      VStack(alignment: .leading, spacing: 8) {
        Text("Transcript")
          .font(.custom("Figtree", size: 12).weight(.semibold))
          .foregroundColor(SettingsStyle.secondary)

        Text(voiceService.transcript.isEmpty ? "No speech captured yet." : voiceService.transcript)
          .font(.custom("Figtree", size: 14))
          .foregroundColor(voiceService.transcript.isEmpty ? SettingsStyle.meta : SettingsStyle.text)
          .frame(maxWidth: .infinity, minHeight: 92, alignment: .topLeading)
          .padding(12)
          .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.black.opacity(0.04)))
      }

      HStack(spacing: 10) {
        SettingsSecondaryButton(
          title: "Clear",
          systemImage: "trash",
          isDisabled: voiceService.transcript.isEmpty,
          action: { voiceService.clearTranscript() }
        )
        SettingsSecondaryButton(
          title: "Speak transcript",
          systemImage: "speaker.wave.2",
          isDisabled: voiceService.transcript.isEmpty,
          action: { voiceService.speakTranscript() }
        )
        Spacer()
      }
    }
    .padding(28)
    .frame(width: 520)
    .background(Color(hex: "FFFAF5"))
  }
}

private struct VoicePressToTalkButton: View {
  @ObservedObject var service: VoiceCapabilityService

  var body: some View {
    HStack(spacing: 10) {
      Image(systemName: service.isListening ? "mic.fill" : "mic")
        .font(.system(size: 16, weight: .semibold))
      Text(service.isListening ? "Listening... release to stop" : "Hold to talk")
        .font(.custom("Figtree", size: 14).weight(.semibold))
    }
    .foregroundColor(.white)
    .frame(maxWidth: .infinity)
    .padding(.vertical, 13)
    .background(
      RoundedRectangle(cornerRadius: 8, style: .continuous)
        .fill(service.isListening ? Color.red.opacity(0.85) : SettingsStyle.ink)
    )
    .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    .gesture(
      DragGesture(minimumDistance: 0)
        .onChanged { _ in service.startPressToTalk() }
        .onEnded { _ in service.stopPressToTalk() }
    )
    .accessibilityLabel("Hold to talk")
    .accessibilityHint("Hold while speaking, then release to finish")
  }
}
