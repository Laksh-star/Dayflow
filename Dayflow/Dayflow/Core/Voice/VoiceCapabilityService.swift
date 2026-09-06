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

enum VoiceTranscriptionMode: String, CaseIterable, Identifiable {
  case onDevice
  case openAIHighAccuracy

  var id: String { rawValue }

  var title: String {
    switch self {
    case .onDevice:
      return "On-device"
    case .openAIHighAccuracy:
      return "OpenAI high accuracy"
    }
  }
}

private struct OpenAITranscriptionConfiguration {
  let endpoint: URL
  let apiKey: String

  static func load() -> OpenAITranscriptionConfiguration? {
    guard let configuration = OpenAICompatiblePreferences.load(),
      let endpoint = audioTranscriptionsURL(from: configuration.baseURL),
      let apiKey = KeychainManager.shared.retrieve(for: OpenAICompatiblePreferences.keychainProvider)?
        .trimmingCharacters(in: .whitespacesAndNewlines),
      !apiKey.isEmpty
    else {
      return nil
    }
    return OpenAITranscriptionConfiguration(endpoint: endpoint, apiKey: apiKey)
  }

  static func isDirectOpenAIConfigured() -> Bool {
    guard let configuration = OpenAICompatiblePreferences.load() else { return false }
    return audioTranscriptionsURL(from: configuration.baseURL) != nil
  }

  private static func audioTranscriptionsURL(from baseURL: String) -> URL? {
    guard var components = URLComponents(string: baseURL.trimmingCharacters(in: .whitespacesAndNewlines)),
      components.scheme == "https",
      components.host?.lowercased() == "api.openai.com"
    else {
      return nil
    }

    let path = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    let apiPath = path.isEmpty ? "v1" : path
    components.path = "/\(apiPath)/audio/transcriptions"
    components.query = nil
    components.fragment = nil
    return components.url
  }
}

private enum OpenAITranscriptionError: LocalizedError {
  case emptyRecording
  case invalidResponse
  case requestFailed(statusCode: Int)

  var errorDescription: String? {
    switch self {
    case .emptyRecording:
      return "The microphone recording was empty. Hold the button while speaking, then try again."
    case .invalidResponse:
      return "OpenAI returned an unreadable transcription response."
    case .requestFailed(let statusCode):
      return "OpenAI transcription request failed (HTTP \(statusCode))."
    }
  }
}

private struct OpenAITranscriptionClient {
  private struct Response: Decodable {
    let text: String
  }

  func transcribe(fileURL: URL, configuration: OpenAITranscriptionConfiguration) async throws -> String {
    let boundary = "DayflowVoice-\(UUID().uuidString)"
    var request = URLRequest(url: configuration.endpoint)
    request.httpMethod = "POST"
    request.setValue("Bearer \(configuration.apiKey)", forHTTPHeaderField: "Authorization")
    request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
    request.httpBody = try multipartBody(fileURL: fileURL, boundary: boundary)
    request.timeoutInterval = 25

    let sessionConfiguration = URLSessionConfiguration.ephemeral
    sessionConfiguration.timeoutIntervalForRequest = 25
    sessionConfiguration.timeoutIntervalForResource = 35
    let session = URLSession(configuration: sessionConfiguration)
    let (data, response) = try await session.data(for: request)
    guard let httpResponse = response as? HTTPURLResponse else {
      throw OpenAITranscriptionError.invalidResponse
    }
    guard (200...299).contains(httpResponse.statusCode) else {
      throw OpenAITranscriptionError.requestFailed(statusCode: httpResponse.statusCode)
    }
    guard let result = try? JSONDecoder().decode(Response.self, from: data) else {
      throw OpenAITranscriptionError.invalidResponse
    }
    return result.text
  }

  private func multipartBody(fileURL: URL, boundary: String) throws -> Data {
    let audioData = try Data(contentsOf: fileURL)
    guard !audioData.isEmpty else {
      throw OpenAITranscriptionError.emptyRecording
    }
    var body = Data()
    func append(_ string: String) {
      body.append(string.data(using: .utf8)!)
    }

    append("--\(boundary)\r\n")
    append("Content-Disposition: form-data; name=\"model\"\r\n\r\n")
    append("gpt-transcribe\r\n")
    append("--\(boundary)\r\n")
    append("Content-Disposition: form-data; name=\"file\"; filename=\"voice-review.wav\"\r\n")
    append("Content-Type: audio/wav\r\n\r\n")
    body.append(audioData)
    append("\r\n--\(boundary)--\r\n")
    return body
  }
}

/// A developer-only voice capability probe. It intentionally has no knowledge
/// of timeline, task, or capture data.
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
        return "Hold the microphone button to speak."
      case .requestingPermission:
        return "Requesting microphone access..."
      case .ready:
        return "Ready. Hold the microphone button to speak."
      case .listening:
        return "Listening. Release when you finish speaking."
      case .finishing:
        return "Finishing transcription..."
      case .unavailable(let message), .denied(let message), .failed(let message):
        return message
      }
    }
  }

  @Published private(set) var state: State = .idle
  @Published private(set) var transcript = ""
  @Published var transcriptionMode: VoiceTranscriptionMode = .onDevice

  private let recognizer = SFSpeechRecognizer(locale: Locale.current)
  private let synthesizer = AVSpeechSynthesizer()
  private var audioEngine: AVAudioEngine?
  private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
  private var recognitionTask: SFSpeechRecognitionTask?
  private var cloudRecordingURL: URL?
  private var cloudOutputFile: AVAudioFile?
  private var openAITranscriptionConfiguration: OpenAITranscriptionConfiguration?
  private var isStarting = false
  private var activeSessionID: UUID?
  private var transcriptAssembler = VoiceTranscriptAssembler()

  var hasDirectOpenAIConfiguration: Bool {
    OpenAITranscriptionConfiguration.isDirectOpenAIConfigured()
  }

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
      let authorized = await requestRequiredPermissions(for: transcriptionMode)
      isStarting = false
      guard authorized else { return }
      switch transcriptionMode {
      case .onDevice:
        startRecognition()
      case .openAIHighAccuracy:
        startCloudRecording()
      }
    }
  }

  func stopPressToTalk() {
    guard case .listening = state else { return }
    state = .finishing
    switch transcriptionMode {
    case .onDevice:
      audioEngine?.stop()
      audioEngine?.inputNode.removeTap(onBus: 0)
      recognitionRequest?.endAudio()
      scheduleFinishFallback(for: activeSessionID)
    case .openAIHighAccuracy:
      finishCloudRecording()
    }
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

  private func requestRequiredPermissions(for mode: VoiceTranscriptionMode) async -> Bool {
    state = .requestingPermission

    let microphoneGranted = await requestMicrophoneAccess()
    guard microphoneGranted else {
      state = .denied("Microphone access is required for this test.")
      return false
    }

    guard mode == .onDevice else {
      guard let configuration = OpenAITranscriptionConfiguration.load() else {
        state = .unavailable("OpenAI high accuracy needs a direct api.openai.com provider configuration and API key in Settings.")
        return false
      }
      openAITranscriptionConfiguration = configuration
      return true
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

  private func startCloudRecording() {
    let configuration = openAITranscriptionConfiguration
    tearDownRecognition(cancelTask: true)
    openAITranscriptionConfiguration = configuration

    let engine = AVAudioEngine()
    let inputNode = engine.inputNode
    let format = inputNode.outputFormat(forBus: 0)
    guard format.sampleRate > 0 else {
      state = .failed("No microphone input is available. Check System Settings and try again.")
      return
    }

    let fileURL = FileManager.default.temporaryDirectory
      .appendingPathComponent("dayflow-voice-\(UUID().uuidString)")
      .appendingPathExtension("wav")
    guard let outputFile = try? AVAudioFile(
      forWriting: fileURL,
      settings: format.settings,
      commonFormat: .pcmFormatInt16,
      interleaved: false
    ) else {
      state = .failed("Dayflow could not prepare a temporary audio recording.")
      return
    }

    inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
      try? outputFile.write(from: buffer)
    }

    audioEngine = engine
    cloudRecordingURL = fileURL
    cloudOutputFile = outputFile
    transcript = ""
    transcriptAssembler.reset()
    state = .listening
    activeSessionID = UUID()

    do {
      engine.prepare()
      try engine.start()
    } catch {
      cloudOutputFile = nil
      removeCloudRecording()
      finishWithError(error)
    }
  }

  private func finishCloudRecording() {
    let sessionID = activeSessionID
    let recordingURL = cloudRecordingURL
    audioEngine?.stop()
    audioEngine?.inputNode.removeTap(onBus: 0)
    audioEngine = nil
    // Releasing the file before reading it flushes the WAV header and final frames.
    cloudOutputFile = nil
    cloudRecordingURL = nil

    guard let sessionID, let recordingURL else {
      state = .failed("The temporary audio recording was unavailable.")
      return
    }

    Task { [weak self] in
      defer { try? FileManager.default.removeItem(at: recordingURL) }
      guard let configuration = self?.openAITranscriptionConfiguration else {
        await MainActor.run {
          guard self?.activeSessionID == sessionID else { return }
          self?.activeSessionID = nil
          self?.state = .unavailable("OpenAI high accuracy needs a direct api.openai.com provider configuration and API key in Settings.")
        }
        return
      }

      do {
        let text = try await OpenAITranscriptionClient().transcribe(
          fileURL: recordingURL,
          configuration: configuration
        )
        await MainActor.run {
          guard self?.activeSessionID == sessionID else { return }
          self?.transcript = Self.normalizedTranscript(text)
          self?.activeSessionID = nil
          self?.openAITranscriptionConfiguration = nil
          self?.state = .ready
        }
      } catch {
        await MainActor.run {
          guard self?.activeSessionID == sessionID else { return }
          self?.activeSessionID = nil
          self?.openAITranscriptionConfiguration = nil
          self?.state = .failed(Self.openAIErrorMessage(for: error))
        }
      }
    }
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
    openAITranscriptionConfiguration = nil
    cloudOutputFile = nil
    removeCloudRecording()
  }

  private func removeCloudRecording() {
    guard let cloudRecordingURL else { return }
    try? FileManager.default.removeItem(at: cloudRecordingURL)
    self.cloudRecordingURL = nil
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

  private static func openAIErrorMessage(for error: Error) -> String {
    if let urlError = error as? URLError, urlError.code == .timedOut {
      return "OpenAI transcription timed out. Check your connection, then try a short 3-5 second recording."
    }
    return "OpenAI transcription stopped: \(error.localizedDescription)"
  }
}
