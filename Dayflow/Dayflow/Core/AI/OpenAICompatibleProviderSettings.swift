import Foundation

enum OpenAICompatibleProviderSettings {
  static let providerID = "openai_compatible"
  static let apiKeyProvider = "openai_compatible"

  private static let baseURLDefaultsKey = "llmOpenAICompatibleBaseURL"
  private static let modelIDDefaultsKey = "llmOpenAICompatibleModelId"

  static let defaultBaseURL = "https://api.openai.com"
  static let defaultModelID = "gpt-4o-mini"

  static func loadBaseURL(from defaults: UserDefaults = .standard) -> String {
    let saved = defaults.string(forKey: baseURLDefaultsKey)?
      .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    return saved.isEmpty ? defaultBaseURL : saved
  }

  static func saveBaseURL(_ value: String, to defaults: UserDefaults = .standard) {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    defaults.set(trimmed.isEmpty ? defaultBaseURL : trimmed, forKey: baseURLDefaultsKey)
  }

  static func loadModelID(from defaults: UserDefaults = .standard) -> String {
    let saved = defaults.string(forKey: modelIDDefaultsKey)?
      .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    return saved.isEmpty ? defaultModelID : saved
  }

  static func saveModelID(_ value: String, to defaults: UserDefaults = .standard) {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    defaults.set(trimmed.isEmpty ? defaultModelID : trimmed, forKey: modelIDDefaultsKey)
  }

  static func loadAPIKey() -> String {
    KeychainManager.shared.retrieve(for: apiKeyProvider) ?? ""
  }

  @discardableResult
  static func saveAPIKey(_ value: String) -> Bool {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
      return KeychainManager.shared.delete(for: apiKeyProvider)
    }
    return KeychainManager.shared.store(trimmed, for: apiKeyProvider)
  }

  static func hasAPIKey() -> Bool {
    !loadAPIKey().trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  }

  static func usesMaxCompletionTokens(modelId: String, baseURL: String) -> Bool {
    let normalizedModel = modelId.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    return normalizedModel.hasPrefix("gpt-5") || normalizedModel.hasPrefix("o1")
      || normalizedModel.hasPrefix("o3") || normalizedModel.hasPrefix("o4")
  }
}
