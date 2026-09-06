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
          Text("Developer-only speech capability check")
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

      VStack(alignment: .leading, spacing: 8) {
        Text("Transcription")
          .font(.custom("Figtree", size: 12).weight(.semibold))
          .foregroundColor(SettingsStyle.secondary)

        Picker("Transcription", selection: $voiceService.transcriptionMode) {
          ForEach(VoiceTranscriptionMode.allCases) { mode in
            Text(mode.title).tag(mode)
          }
        }
        .pickerStyle(.segmented)
        .disabled(voiceService.isListening)

        Text(transcriptionDisclosure)
          .font(.custom("Figtree", size: 12))
          .foregroundColor(SettingsStyle.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }

      VStack(alignment: .leading, spacing: 10) {
        Text(voiceService.state.message)
          .font(.custom("Figtree", size: 14))
          .foregroundColor(SettingsStyle.text)

        Text("The transcript stays only in this test panel until you clear it or close the panel.")
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

  private var transcriptionDisclosure: String {
    switch voiceService.transcriptionMode {
    case .onDevice:
      return "On-device recognition keeps held audio on this Mac. It may be less accurate for natural pauses or longer phrases."
    case .openAIHighAccuracy:
      if voiceService.hasDirectOpenAIConfiguration {
        return "When you release, Dayflow sends that held audio once to OpenAI's gpt-transcribe API. The temporary audio file is deleted after the request."
      }
      return "Requires a direct api.openai.com provider configuration and API key in Settings. Dayflow will not send audio to another compatible provider."
    }
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
    .onLongPressGesture(
      minimumDuration: .infinity,
      maximumDistance: .infinity,
      pressing: { isPressing in
        if isPressing {
          service.startPressToTalk()
        } else {
          service.stopPressToTalk()
        }
      },
      perform: {}
    )
    .accessibilityLabel("Hold to talk")
    .accessibilityHint("Hold while speaking, then release to finish")
  }
}
