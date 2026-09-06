import AVFoundation
import Foundation
import Speech

/// A local-only voice capability probe. It intentionally has no knowledge of
/// timeline, task, capture, or provider data.
@MainActor
final class VoiceCapabilityService: NSObject, ObservableObject {
  enum State: Equatable {
    case idle
    case requestingPermission
    case ready
    case listening
    case unavailable(String)
    case denied(String)
    case failed(String)

    var message: String {
      switch self {
      case .idle:
        return "Hold the microphone button to test local transcription."
      case .requestingPermission:
        return "Requesting microphone and speech-recognition access..."
      case .ready:
        return "Ready. Hold the microphone button to speak."
      case .listening:
        return "Listening locally. Release when you finish speaking."
      case .unavailable(let message), .denied(let message), .failed(let message):
        return message
      }
    }
  }

  @Published private(set) var state: State = .idle
  @Published private(set) var transcript = ""

  private let recognizer = SFSpeechRecognizer(locale: Locale.current)
  private let synthesizer = AVSpeechSynthesizer()
  private var audioEngine: AVAudioEngine?
  private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
  private var recognitionTask: SFSpeechRecognitionTask?
  private var isStarting = false

  var isListening: Bool {
    if case .listening = state {
      return true
    }
    return false
  }

  func startPressToTalk() {
    guard !isStarting, !isListening else { return }
    isStarting = true
    Task {
      let authorized = await requestRequiredPermissions()
      isStarting = false
      guard authorized else { return }
      startRecognition()
    }
  }

  func stopPressToTalk() {
    guard isListening else { return }
    audioEngine?.stop()
    audioEngine?.inputNode.removeTap(onBus: 0)
    recognitionRequest?.endAudio()
    state = .ready
  }

  func clearTranscript() {
    transcript = ""
  }

  func speakTranscript() {
    let text = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !text.isEmpty else { return }
    synthesizer.stopSpeaking(at: .immediate)
    let utterance = AVSpeechUtterance(string: text)
    utterance.voice = AVSpeechSynthesisVoice(language: Locale.current.identifier)
    synthesizer.speak(utterance)
  }

  private func requestRequiredPermissions() async -> Bool {
    state = .requestingPermission

    let microphoneGranted = await requestMicrophoneAccess()
    guard microphoneGranted else {
      state = .denied("Microphone access is required for this local test.")
      return false
    }

    let speechStatus = await requestSpeechAuthorization()
    guard speechStatus == .authorized else {
      state = .denied("Speech recognition was not authorized. You can still use typed chat.")
      return false
    }

    guard let recognizer else {
      state = .unavailable("Speech recognition is unavailable for the current language.")
      return false
    }

    guard recognizer.isAvailable else {
      state = .unavailable("Speech recognition is temporarily unavailable. No audio was sent anywhere.")
      return false
    }

    guard recognizer.supportsOnDeviceRecognition else {
      state = .unavailable("On-device speech recognition is unavailable for the current language.")
      return false
    }

    return true
  }

  private func startRecognition() {
    guard let recognizer else { return }

    recognitionTask?.cancel()
    audioEngine?.stop()
    audioEngine?.inputNode.removeTap(onBus: 0)

    let engine = AVAudioEngine()
    let request = SFSpeechAudioBufferRecognitionRequest()
    request.shouldReportPartialResults = true
    request.requiresOnDeviceRecognition = true

    let inputNode = engine.inputNode
    let format = inputNode.outputFormat(forBus: 0)
    guard format.sampleRate > 0 else {
      state = .failed("No microphone input is available. Check System Settings and try again.")
      return
    }

    inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
      request.append(buffer)
    }

    audioEngine = engine
    recognitionRequest = request
    transcript = ""
    state = .listening

    recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
      Task { @MainActor [weak self] in
        guard let self else { return }
        if let result {
          self.transcript = result.bestTranscription.formattedString
        }
        if let error, self.isListening {
          self.finishWithError(error)
        }
      }
    }

    do {
      engine.prepare()
      try engine.start()
    } catch {
      finishWithError(error)
    }
  }

  private func finishWithError(_ error: Error) {
    audioEngine?.stop()
    audioEngine?.inputNode.removeTap(onBus: 0)
    recognitionRequest?.endAudio()
    recognitionTask?.cancel()
    state = .failed("Speech recognition stopped: \(error.localizedDescription)")
  }

  private func requestMicrophoneAccess() async -> Bool {
    let status = AVCaptureDevice.authorizationStatus(for: .audio)
    switch status {
    case .authorized:
      return true
    case .notDetermined:
      return await withCheckedContinuation { continuation in
        AVCaptureDevice.requestAccess(for: .audio) { granted in
          continuation.resume(returning: granted)
        }
      }
    default:
      return false
    }
  }

  private func requestSpeechAuthorization() async -> SFSpeechRecognizerAuthorizationStatus {
    let status = SFSpeechRecognizer.authorizationStatus()
    guard status == .notDetermined else { return status }

    return await withCheckedContinuation { continuation in
      SFSpeechRecognizer.requestAuthorization { status in
        continuation.resume(returning: status)
      }
    }
  }
}
