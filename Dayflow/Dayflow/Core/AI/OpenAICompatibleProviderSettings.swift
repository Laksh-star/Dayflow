import Foundation

enum OpenAICompatibleProviderProfile: String, CaseIterable, Identifiable {
  case openAI = "openai"
  case openRouter = "openrouter"
  case liteLLM = "litellm"
  case localProxy = "local_proxy"
  case custom = "custom"

  var id: String { rawValue }

  var displayName: String {
    switch self {
    case .openAI: return "OpenAI"
    case .openRouter: return "OpenRouter"
    case .liteLLM: return "LiteLLM"
    case .localProxy: return "Local proxy"
    case .custom: return "Custom"
    }
  }

  var defaultBaseURL: String {
    switch self {
    case .openAI:
      return "https://api.openai.com"
    case .openRouter:
      return "https://openrouter.ai/api/v1"
    case .liteLLM:
      return "http://localhost:4000"
    case .localProxy:
      return "http://localhost:1234"
    case .custom:
      return OpenAICompatibleProviderSettings.defaultBaseURL
    }
  }

  var defaultModelID: String {
    switch self {
    case .openAI:
      return OpenAICompatibleProviderSettings.defaultModelID
    case .openRouter:
      return "openai/gpt-4o-mini"
    case .liteLLM:
      return OpenAICompatibleProviderSettings.defaultModelID
    case .localProxy:
      return "qwen2.5vl:7b"
    case .custom:
      return OpenAICompatibleProviderSettings.defaultModelID
    }
  }

  var defaultAuthMode: OpenAICompatibleAuthMode {
    switch self {
    case .localProxy:
      return .none
    case .openAI, .openRouter, .liteLLM, .custom:
      return .bearer
    }
  }
}

enum OpenAICompatibleAuthMode: String, CaseIterable, Identifiable {
  case bearer
  case apiKeyHeader = "api_key_header"
  case customHeader = "custom_header"
  case none

  var id: String { rawValue }

  var displayName: String {
    switch self {
    case .bearer: return "Bearer token"
    case .apiKeyHeader: return "x-api-key"
    case .customHeader: return "Custom header"
    case .none: return "No auth header"
    }
  }
}

enum OpenAICompatibleProviderSettings {
  static let providerID = "openai_compatible"
  static let apiKeyProvider = "openai_compatible"

  private static let profileDefaultsKey = "llmOpenAICompatibleProfile"
  private static let baseURLDefaultsKey = "llmOpenAICompatibleBaseURL"
  private static let modelIDDefaultsKey = "llmOpenAICompatibleModelId"
  private static let authModeDefaultsKey = "llmOpenAICompatibleAuthMode"
  private static let customHeaderNameDefaultsKey = "llmOpenAICompatibleCustomHeaderName"
  private static let useMaxCompletionTokensDefaultsKey = "llmOpenAICompatibleUseMaxCompletionTokens"

  static let defaultBaseURL = "https://api.openai.com"
  static let defaultModelID = "gpt-4o-mini"
  static let defaultCustomHeaderName = "Authorization"

  static func loadProfile(from defaults: UserDefaults = .standard) -> OpenAICompatibleProviderProfile {
    let raw = defaults.string(forKey: profileDefaultsKey) ?? ""
    return OpenAICompatibleProviderProfile(rawValue: raw) ?? .openAI
  }

  static func saveProfile(_ value: OpenAICompatibleProviderProfile, to defaults: UserDefaults = .standard) {
    defaults.set(value.rawValue, forKey: profileDefaultsKey)
  }

  static func applyProfileDefaults(
    _ profile: OpenAICompatibleProviderProfile,
    to defaults: UserDefaults = .standard
  ) {
    saveProfile(profile, to: defaults)
    saveBaseURL(profile.defaultBaseURL, to: defaults)
    saveModelID(profile.defaultModelID, to: defaults)
    saveAuthMode(profile.defaultAuthMode, to: defaults)
  }

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

  static func loadAuthMode(from defaults: UserDefaults = .standard) -> OpenAICompatibleAuthMode {
    let raw = defaults.string(forKey: authModeDefaultsKey) ?? ""
    return OpenAICompatibleAuthMode(rawValue: raw) ?? loadProfile(from: defaults).defaultAuthMode
  }

  static func saveAuthMode(_ value: OpenAICompatibleAuthMode, to defaults: UserDefaults = .standard) {
    defaults.set(value.rawValue, forKey: authModeDefaultsKey)
  }

  static func loadCustomHeaderName(from defaults: UserDefaults = .standard) -> String {
    let saved = defaults.string(forKey: customHeaderNameDefaultsKey)?
      .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    return saved.isEmpty ? defaultCustomHeaderName : saved
  }

  static func saveCustomHeaderName(_ value: String, to defaults: UserDefaults = .standard) {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    defaults.set(trimmed.isEmpty ? defaultCustomHeaderName : trimmed, forKey: customHeaderNameDefaultsKey)
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

  static func loadUsesMaxCompletionTokensOverride(from defaults: UserDefaults = .standard) -> Bool? {
    guard defaults.object(forKey: useMaxCompletionTokensDefaultsKey) != nil else { return nil }
    return defaults.bool(forKey: useMaxCompletionTokensDefaultsKey)
  }

  static func saveUsesMaxCompletionTokensOverride(_ value: Bool?, to defaults: UserDefaults = .standard) {
    if let value {
      defaults.set(value, forKey: useMaxCompletionTokensDefaultsKey)
    } else {
      defaults.removeObject(forKey: useMaxCompletionTokensDefaultsKey)
    }
  }

  static func authorizationHeaders(
    apiKey: String? = loadAPIKey(),
    from defaults: UserDefaults = .standard
  ) -> [String: String] {
    let trimmedKey = apiKey?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    guard !trimmedKey.isEmpty else { return [:] }

    switch loadAuthMode(from: defaults) {
    case .bearer:
      return ["Authorization": "Bearer \(trimmedKey)"]
    case .apiKeyHeader:
      return ["x-api-key": trimmedKey]
    case .customHeader:
      let header = loadCustomHeaderName(from: defaults)
      guard !header.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [:] }
      return [header: trimmedKey]
    case .none:
      return [:]
    }
  }

  static func usesMaxCompletionTokens(modelId: String, baseURL: String) -> Bool {
    if let override = loadUsesMaxCompletionTokensOverride() {
      return override
    }

    let normalizedModel = modelId.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    return normalizedModel.hasPrefix("gpt-5") || normalizedModel.hasPrefix("o1")
      || normalizedModel.hasPrefix("o3") || normalizedModel.hasPrefix("o4")
  }
}
