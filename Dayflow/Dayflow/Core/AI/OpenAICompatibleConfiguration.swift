import Foundation

enum OpenAICompatiblePreset: String, Codable, CaseIterable {
  case openRouter = "openrouter"
  case custom
}

struct OpenAICompatibleConfiguration: Codable, Equatable {
  static let openRouterBaseURL = "https://openrouter.ai/api/v1"

  let preset: OpenAICompatiblePreset
  let baseURL: String
  let modelID: String

  init(preset: OpenAICompatiblePreset, baseURL: String, modelID: String) {
    self.preset = preset
    self.baseURL = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
    self.modelID = modelID.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  static func openRouter(modelID: String = "") -> OpenAICompatibleConfiguration {
    OpenAICompatibleConfiguration(
      preset: .openRouter,
      baseURL: openRouterBaseURL,
      modelID: modelID
    )
  }

  var chatCompletionsURL: URL? {
    LocalEndpointUtilities.chatCompletionsURL(baseURL: baseURL)
  }

  var isComplete: Bool {
    !baseURL.isEmpty && !modelID.isEmpty && chatCompletionsURL != nil
  }
}

enum OpenAICompatiblePreferences {
  static let keychainProvider = "openai_compatible"
  private static let configurationKey = "llmOpenAICompatibleConfigurationV1"
  private static let legacyProfileKey = "llmOpenAICompatibleProfile"
  private static let legacyBaseURLKey = "llmOpenAICompatibleBaseURL"
  private static let legacyModelIDKey = "llmOpenAICompatibleModelId"

  static func load(from defaults: UserDefaults = .standard) -> OpenAICompatibleConfiguration? {
    if let data = defaults.data(forKey: configurationKey),
      let configuration = try? JSONDecoder().decode(OpenAICompatibleConfiguration.self, from: data)
    {
      return configuration
    }
    return loadLegacyConfiguration(from: defaults)
  }

  @discardableResult
  static func save(
    _ configuration: OpenAICompatibleConfiguration,
    to defaults: UserDefaults = .standard
  ) -> Bool {
    guard let data = try? JSONEncoder().encode(configuration) else { return false }
    let previousValue = defaults.object(forKey: configurationKey)
    defaults.set(data, forKey: configurationKey)
    guard load(from: defaults) == configuration else {
      if let previousValue {
        defaults.set(previousValue, forKey: configurationKey)
      } else {
        defaults.removeObject(forKey: configurationKey)
      }
      return false
    }
    return true
  }

  static func reset(in defaults: UserDefaults = .standard) {
    defaults.removeObject(forKey: configurationKey)
    defaults.removeObject(forKey: legacyProfileKey)
    defaults.removeObject(forKey: legacyBaseURLKey)
    defaults.removeObject(forKey: legacyModelIDKey)
  }

  private static func loadLegacyConfiguration(from defaults: UserDefaults)
    -> OpenAICompatibleConfiguration?
  {
    let baseURL = defaults.string(forKey: legacyBaseURLKey)?
      .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    let modelID = defaults.string(forKey: legacyModelIDKey)?
      .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    guard !baseURL.isEmpty, !modelID.isEmpty else { return nil }

    let profile = defaults.string(forKey: legacyProfileKey)?
      .trimmingCharacters(in: .whitespacesAndNewlines)
      .lowercased() ?? ""
    let preset: OpenAICompatiblePreset = profile == OpenAICompatiblePreset.openRouter.rawValue
      ? .openRouter
      : .custom
    let configuration = OpenAICompatibleConfiguration(
      preset: preset,
      baseURL: baseURL,
      modelID: modelID
    )
    return configuration.isComplete ? configuration : nil
  }
}

struct OpenAICompatibleRuntimeConfiguration: Sendable {
  let endpoint: String
  let modelID: String
  let bearerToken: String?
  let analyticsProvider: String

  init(
    configuration: OpenAICompatibleConfiguration,
    bearerToken: String?,
    analyticsProvider: String = OpenAICompatiblePreferences.keychainProvider
  ) {
    endpoint = configuration.baseURL
    modelID = configuration.modelID

    let trimmedToken = bearerToken?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    self.bearerToken = trimmedToken.isEmpty ? nil : trimmedToken

    let trimmedProvider = analyticsProvider.trimmingCharacters(in: .whitespacesAndNewlines)
    self.analyticsProvider =
      trimmedProvider.isEmpty
      ? OpenAICompatiblePreferences.keychainProvider
      : trimmedProvider
  }
}
