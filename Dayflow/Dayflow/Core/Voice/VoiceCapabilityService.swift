import AVFoundation
import Foundation
import Speech

struct VoiceTranscriptSegment: Equatable {
  var start: TimeInterval
  var duration: TimeInterval
  var text: String
}

struct VoiceTranscriptAssembler {
  private static let timestampTolerance: TimeInterval = 0.08
  private(set) var segments: [VoiceTranscriptSegment] = []

  var text: String {
    segments.map(\.text).joined(separator: " ")
  }

  mutating func reset() {
    segments.removeAll()
  }

  mutating func ingest(_ incoming: [VoiceTranscriptSegment]) {
    for candidate in incoming where !candidate.text.isEmpty {
      if let index = nearestSegmentIndex(to: candidate.start) {
        // Partial recognition routinely revises an earlier segment. Replace it
        // at the same timestamp instead of appending duplicate words.
        segments[index] = candidate
      } else {
        segments.append(candidate)
      }
    }
    segments.sort { $0.start < $1.start }
  }

  private func nearestSegmentIndex(to timestamp: TimeInterval) -> Int? {
    guard let candidate = segments.indices.min(by: {
      abs(segments[$0].start - timestamp) < abs(segments[$1].start - timestamp)
    }) else {
      return nil
    }
    return abs(segments[candidate].start - timestamp) <= Self.timestampTolerance ? candidate : nil
  }
}

/// A local-only voice capability probe. It intentionally has no knowledge of
/// timeline, task, capture, or provider data.
@MainActor
final class VoiceCapabilityService: NSObject, ObservableObject {
  enum State: Equatable {
    case idle
    case requestingPermission
    case ready
    case listening
    case finishing
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
      case .finishing:
        return "Finishing transcription..."
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
  private var activeSessionID: UUID?
  private var transcriptAssembler = VoiceTranscriptAssembler()

  var isListening: Bool {
    switch state {
    case .listening, .finishing:
      return true
    default:
      return false
    }
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
    guard case .listening = state else { return }
    state = .finishing
    audioEngine?.stop()
    audioEngine?.inputNode.removeTap(onBus: 0)
    recognitionRequest?.endAudio()
    scheduleFinishFallback(for: activeSessionID)
  }

  func clearTranscript() {
    transcriptAssembler.reset()
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

    tearDownRecognition(cancelTask: true)

    let engine = AVAudioEngine()
    let request = SFSpeechAudioBufferRecognitionRequest()
    request.shouldReportPartialResults = true
    request.requiresOnDeviceRecognition = true
    request.taskHint = .dictation

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
    transcriptAssembler.reset()
    transcript = ""
    state = .listening
    let sessionID = UUID()
    activeSessionID = sessionID

    recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
      Task { @MainActor [weak self] in
        guard let self else { return }
        guard self.activeSessionID == sessionID else { return }
        if let result {
          self.transcriptAssembler.ingest(
            result.bestTranscription.segments.map {
              VoiceTranscriptSegment(
                start: $0.timestamp,
                duration: $0.duration,
                text: Self.normalizedTranscript($0.substring)
              )
            }
          )
          self.transcript = self.transcriptAssembler.text
          if result.isFinal {
            self.finishRecognition(sessionID: sessionID)
            return
          }
        }
        if let error {
          if case .finishing = self.state {
            self.finishRecognition(sessionID: sessionID)
          } else {
            self.finishWithError(error)
          }
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
    tearDownRecognition(cancelTask: true)
    state = .failed("Speech recognition stopped: \(error.localizedDescription)")
  }

  private func finishRecognition(sessionID: UUID) {
    guard activeSessionID == sessionID else { return }
    tearDownRecognition(cancelTask: false)
    state = .ready
  }

  private func scheduleFinishFallback(for sessionID: UUID?) {
    guard let sessionID else { return }
    Task { [weak self] in
      try? await Task.sleep(for: .seconds(2))
      guard !Task.isCancelled else { return }
      guard let self, self.activeSessionID == sessionID else { return }
      guard case .finishing = self.state else { return }
      self.finishRecognition(sessionID: sessionID)
    }
  }

  private func tearDownRecognition(cancelTask: Bool) {
    audioEngine?.stop()
    audioEngine?.inputNode.removeTap(onBus: 0)
    recognitionRequest?.endAudio()
    if cancelTask {
      recognitionTask?.cancel()
    }
    audioEngine = nil
    recognitionRequest = nil
    recognitionTask = nil
    activeSessionID = nil
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

  private static func normalizedTranscript(_ text: String) -> String {
    text
      .split(whereSeparator: { $0.isWhitespace })
      .joined(separator: " ")
  }
}
