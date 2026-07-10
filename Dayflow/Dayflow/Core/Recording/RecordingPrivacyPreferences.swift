import AppKit
import Foundation
@preconcurrency import ScreenCaptureKit

struct RecordingPrivacyApplication: Identifiable, Equatable, Sendable {
  let name: String
  let bundleIdentifier: String
  let appURL: URL?

  var id: String { bundleIdentifier }

  init(name: String, bundleIdentifier: String, appURL: URL? = nil) {
    self.name = name
    self.bundleIdentifier = bundleIdentifier
    self.appURL = appURL
  }
}

struct RecordingPrivacyContext: Equatable, Sendable {
  let applicationName: String?
  let bundleIdentifier: String?
  let windowTitle: String?
}

struct RecordingPrivacyMatch: Equatable, Sendable {
  enum RuleType: String, Sendable {
    case application
    case domain
    case windowTitle
  }

  let ruleType: RuleType
  let matchedValue: String
  let displayName: String

  var placeholderApplicationName: String {
    switch ruleType {
    case .application:
      return displayName
    case .domain:
      return matchedValue
    case .windowTitle:
      return "Private window"
    }
  }
}

enum RecordingPrivacyPreset: String, CaseIterable, Identifiable, Sendable {
  case gmail
  case whatsApp
  case banking
  case passwordManagers

  var id: String { rawValue }

  var title: String {
    switch self {
    case .gmail: return "Gmail"
    case .whatsApp: return "WhatsApp"
    case .banking: return "Banking"
    case .passwordManagers: return "Password managers"
    }
  }

  var domains: [String] {
    switch self {
    case .gmail:
      return ["mail.google.com", "gmail.com", "inbox.google.com"]
    case .whatsApp:
      return ["web.whatsapp.com", "whatsapp.com"]
    case .banking:
      return [
        "bankofamerica.com", "chase.com", "citi.com", "capitalone.com", "wellsfargo.com",
        "hdfcbank.com", "icicibank.com", "axisbank.com", "onlinesbi.sbi", "netbanking",
      ]
    case .passwordManagers:
      return ["1password.com", "bitwarden.com", "lastpass.com", "dashlane.com"]
    }
  }

  var windowTitleKeywords: [String] {
    switch self {
    case .gmail:
      return ["gmail", "compose", "inbox"]
    case .whatsApp:
      return ["whatsapp"]
    case .banking:
      return [
        "bank", "banking", "credit card", "debit card", "statement", "upi", "netbanking",
        "one-time password", "otp",
      ]
    case .passwordManagers:
      return [
        "password", "passkey", "one-time password", "otp", "1password", "bitwarden", "lastpass",
        "dashlane", "keychain",
      ]
    }
  }
}

enum RecordingPrivacyPreferences {
  private static let blockedApplicationIdentifiersKey =
    "recordingPrivacyBlockedApplicationIdentifiers"
  private static let blockedDomainsKey = "recordingPrivacyBlockedDomains"
  private static let blockedWindowTitleKeywordsKey = "recordingPrivacyBlockedWindowTitleKeywords"
  private static let didSeedDefaultSecretAppsKey = "recordingPrivacyDidSeedDefaultSecretApps"
  private static let didSeedDefaultSensitiveRulesKey = "recordingPrivacyDidSeedDefaultSensitiveRules"

  private static let defaultSecretAppNames: Set<String> = [
    "1password",
    "authy",
    "bitwarden",
    "dashlane",
    "enpass",
    "keeper",
    "keepassxc",
    "keychain access",
    "lastpass",
    "ledger live",
    "nordpass",
    "passwords",
    "proton pass",
    "secrets",
    "trezor suite",
    "yubico authenticator",
  ]

  private static let defaultSecretBundleHints = [
    "1password",
    "authy",
    "bitwarden",
    "dashlane",
    "enpass",
    "keeper",
    "keepass",
    "keychainaccess",
    "lastpass",
    "ledger",
    "nordpass",
    "passwords",
    "protonpass",
    "secrets",
    "trezor",
    "yubico",
  ]

  private static let defaultSensitiveDomains = [
    "mail.google.com",
    "gmail.com",
    "web.whatsapp.com",
  ]

  private static let defaultSensitiveWindowTitleKeywords = [
    "bank",
    "banking",
    "credit card",
    "debit card",
    "gmail",
    "one-time password",
    "otp",
    "passkey",
    "password",
    "upi",
    "whatsapp",
  ]

  static func blockedApplicationIdentifiers(defaults: UserDefaults = .standard) -> [String] {
    let stored = defaults.stringArray(forKey: blockedApplicationIdentifiersKey) ?? []
    return normalizedIdentifiers(from: stored)
  }

  static func blockedApplicationsText(defaults: UserDefaults = .standard) -> String {
    blockedApplicationIdentifiers(defaults: defaults).joined(separator: "\n")
  }

  static func blockedDomains(defaults: UserDefaults = .standard) -> [String] {
    let stored = defaults.stringArray(forKey: blockedDomainsKey) ?? []
    return normalizedRules(from: stored)
  }

  static func blockedWindowTitleKeywords(defaults: UserDefaults = .standard) -> [String] {
    let stored = defaults.stringArray(forKey: blockedWindowTitleKeywordsKey) ?? []
    return normalizedRules(from: stored)
  }

  static func blockedDomainsText(defaults: UserDefaults = .standard) -> String {
    blockedDomains(defaults: defaults).joined(separator: "\n")
  }

  static func blockedWindowTitleKeywordsText(defaults: UserDefaults = .standard) -> String {
    blockedWindowTitleKeywords(defaults: defaults).joined(separator: "\n")
  }

  static func saveBlockedApplicationsText(
    _ text: String,
    defaults: UserDefaults = .standard
  ) {
    saveBlockedApplicationIdentifiers(identifiers(from: text), defaults: defaults)
  }

  static func saveBlockedApplicationIdentifiers(
    _ identifiers: [String],
    defaults: UserDefaults = .standard
  ) {
    defaults.set(normalizedIdentifiers(from: identifiers), forKey: blockedApplicationIdentifiersKey)
  }

  static func saveBlockedDomains(
    _ domains: [String],
    defaults: UserDefaults = .standard
  ) {
    defaults.set(normalizedRules(from: domains), forKey: blockedDomainsKey)
  }

  static func saveBlockedWindowTitleKeywords(
    _ keywords: [String],
    defaults: UserDefaults = .standard
  ) {
    defaults.set(normalizedRules(from: keywords), forKey: blockedWindowTitleKeywordsKey)
  }

  static func saveBlockedDomainsText(
    _ text: String,
    defaults: UserDefaults = .standard
  ) {
    saveBlockedDomains(rules(from: text), defaults: defaults)
  }

  static func saveBlockedWindowTitleKeywordsText(
    _ text: String,
    defaults: UserDefaults = .standard
  ) {
    saveBlockedWindowTitleKeywords(rules(from: text), defaults: defaults)
  }

  static func seedDefaultSecretApplicationsIfNeeded(
    from applications: [RecordingPrivacyApplication],
    defaults: UserDefaults = .standard
  ) {
    guard !defaults.bool(forKey: didSeedDefaultSecretAppsKey) else { return }

    let defaultIdentifiers = defaultSecretApplicationIdentifiers(in: applications)
    if !defaultIdentifiers.isEmpty {
      saveBlockedApplicationIdentifiers(
        blockedApplicationIdentifiers(defaults: defaults) + defaultIdentifiers,
        defaults: defaults
      )
    }
    defaults.set(true, forKey: didSeedDefaultSecretAppsKey)
  }

  static func seedDefaultSensitiveRulesIfNeeded(defaults: UserDefaults = .standard) {
    guard !defaults.bool(forKey: didSeedDefaultSensitiveRulesKey) else { return }

    saveBlockedDomains(
      blockedDomains(defaults: defaults) + defaultSensitiveDomains,
      defaults: defaults
    )
    saveBlockedWindowTitleKeywords(
      blockedWindowTitleKeywords(defaults: defaults) + defaultSensitiveWindowTitleKeywords,
      defaults: defaults
    )
    defaults.set(true, forKey: didSeedDefaultSensitiveRulesKey)
  }

  static func identifiers(from text: String) -> [String] {
    normalizedIdentifiers(from: text.components(separatedBy: .newlines))
  }

  static func rules(from text: String) -> [String] {
    normalizedRules(from: text.components(separatedBy: .newlines))
  }

  static func isApplicationBlocked(
    bundleIdentifier: String?,
    applicationName: String?,
    defaults: UserDefaults = .standard
  ) -> Bool {
    let blocked = Set(blockedApplicationIdentifiers(defaults: defaults))
    guard !blocked.isEmpty else { return false }

    let candidates = [
      normalizedIdentifier(bundleIdentifier),
      normalizedIdentifier(applicationName),
    ].compactMap { $0 }

    return candidates.contains { blocked.contains($0) }
  }

  static func privacyMatch(
    for context: RecordingPrivacyContext,
    defaults: UserDefaults = .standard
  ) -> RecordingPrivacyMatch? {
    if isApplicationBlocked(
      bundleIdentifier: context.bundleIdentifier,
      applicationName: context.applicationName,
      defaults: defaults
    ) {
      let matchedValue = context.bundleIdentifier ?? context.applicationName ?? "private-app"
      return RecordingPrivacyMatch(
        ruleType: .application,
        matchedValue: matchedValue,
        displayName: context.applicationName ?? matchedValue
      )
    }

    if let windowTitle = normalizedSearchText(context.windowTitle), !windowTitle.isEmpty {
      if let domain = matchingDomainRule(in: windowTitle, defaults: defaults) {
        return RecordingPrivacyMatch(
          ruleType: .domain,
          matchedValue: domain,
          displayName: context.applicationName ?? domain
        )
      }

      if let keyword = matchingWindowTitleRule(in: windowTitle, defaults: defaults) {
        return RecordingPrivacyMatch(
          ruleType: .windowTitle,
          matchedValue: keyword,
          displayName: context.applicationName ?? "Private window"
        )
      }
    }

    return nil
  }

  @MainActor
  static func frontmostPrivacyMatch(
    defaults: UserDefaults = .standard
  ) -> RecordingPrivacyMatch? {
    privacyMatch(for: frontmostContext(), defaults: defaults)
  }

  @MainActor
  static func frontmostContext() -> RecordingPrivacyContext {
    guard let app = NSWorkspace.shared.frontmostApplication else {
      return RecordingPrivacyContext(
        applicationName: nil,
        bundleIdentifier: nil,
        windowTitle: nil
      )
    }

    return RecordingPrivacyContext(
      applicationName: app.localizedName,
      bundleIdentifier: app.bundleIdentifier,
      windowTitle: frontmostWindowTitle(for: app.processIdentifier)
    )
  }

  static func blockedScreenCaptureApplications(
    in content: SCShareableContent,
    defaults: UserDefaults = .standard
  ) -> [SCRunningApplication] {
    content.applications.filter { app in
      isApplicationBlocked(
        bundleIdentifier: app.bundleIdentifier,
        applicationName: app.applicationName,
        defaults: defaults
      )
    }
  }

  @MainActor
  static func runningApplications() -> [RecordingPrivacyApplication] {
    let apps = NSWorkspace.shared.runningApplications.compactMap {
      app -> RecordingPrivacyApplication? in
      guard app.activationPolicy == .regular else { return nil }
      guard let bundleIdentifier = app.bundleIdentifier, !bundleIdentifier.isEmpty else {
        return nil
      }

      return RecordingPrivacyApplication(
        name: app.localizedName ?? bundleIdentifier,
        bundleIdentifier: bundleIdentifier
      )
    }

    var seen = Set<String>()
    return
      apps
      .filter { app in
        let key = normalizedIdentifier(app.bundleIdentifier) ?? app.bundleIdentifier
        return seen.insert(key).inserted
      }
      .sorted {
        $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
      }
  }

  static func installedApplications() -> [RecordingPrivacyApplication] {
    let fileManager = FileManager.default
    let roots = applicationSearchRoots(fileManager: fileManager)
    var apps: [RecordingPrivacyApplication] = []

    for root in roots {
      guard
        let enumerator = fileManager.enumerator(
          at: root,
          includingPropertiesForKeys: [.isDirectoryKey, .isPackageKey],
          options: [.skipsHiddenFiles, .skipsPackageDescendants]
        )
      else {
        continue
      }

      for case let url as URL in enumerator {
        guard url.pathExtension == "app" else { continue }
        enumerator.skipDescendants()

        guard let app = installedApplication(from: url) else { continue }
        apps.append(app)
      }
    }

    var seen = Set<String>()
    return
      apps
      .filter { app in
        let key = normalizedIdentifier(app.bundleIdentifier) ?? app.bundleIdentifier
        return seen.insert(key).inserted
      }
      .sorted {
        $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
      }
  }

  static func defaultSecretApplicationIdentifiers(
    in applications: [RecordingPrivacyApplication]
  ) -> [String] {
    applications.compactMap { app in
      let name = normalizedIdentifier(app.name) ?? ""
      let compactBundle = (normalizedIdentifier(app.bundleIdentifier) ?? "")
        .replacingOccurrences(of: ".", with: "")
        .replacingOccurrences(of: "-", with: "")
        .replacingOccurrences(of: "_", with: "")

      if defaultSecretAppNames.contains(name) {
        return app.bundleIdentifier
      }
      if defaultSecretBundleHints.contains(where: { compactBundle.contains($0) }) {
        return app.bundleIdentifier
      }
      return nil
    }
  }

  private static func normalizedIdentifiers(from values: [String]) -> [String] {
    var seen = Set<String>()
    return values.compactMap { value in
      guard let normalized = normalizedIdentifier(value) else { return nil }
      return seen.insert(normalized).inserted ? normalized : nil
    }
  }

  private static func normalizedRules(from values: [String]) -> [String] {
    var seen = Set<String>()
    return values.compactMap { value in
      guard let normalized = normalizedRule(value) else { return nil }
      return seen.insert(normalized).inserted ? normalized : nil
    }
  }

  private static func normalizedIdentifier(_ value: String?) -> String? {
    guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
      !trimmed.isEmpty
    else {
      return nil
    }
    return trimmed.lowercased()
  }

  private static func normalizedRule(_ value: String?) -> String? {
    guard var trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
      !trimmed.isEmpty
    else {
      return nil
    }

    trimmed = trimmed
      .replacingOccurrences(of: "https://", with: "")
      .replacingOccurrences(of: "http://", with: "")
    if let slashIndex = trimmed.firstIndex(of: "/") {
      trimmed = String(trimmed[..<slashIndex])
    }
    return trimmed.lowercased()
  }

  private static func normalizedSearchText(_ value: String?) -> String? {
    guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
      !trimmed.isEmpty
    else {
      return nil
    }
    return trimmed.lowercased()
  }

  private static func matchingDomainRule(
    in text: String,
    defaults: UserDefaults
  ) -> String? {
    let rules = blockedDomains(defaults: defaults)
    guard !rules.isEmpty else { return nil }
    let domains = domainCandidates(in: text)
    return rules.first { rule in
      domainRuleMatches(rule: rule, text: text, domainCandidates: domains)
    }
  }

  private static func matchingWindowTitleRule(
    in text: String,
    defaults: UserDefaults
  ) -> String? {
    let rules = blockedWindowTitleKeywords(defaults: defaults)
    guard !rules.isEmpty else { return nil }
    return rules.first { text.localizedCaseInsensitiveContains($0) }
  }

  private static func domainRuleMatches(
    rule: String,
    text: String,
    domainCandidates: [String] = []
  ) -> Bool {
    let normalizedText = text.lowercased()
    if normalizedText.contains(rule) { return true }

    let bareRule = rule.replacingOccurrences(of: "www.", with: "")
    if !bareRule.isEmpty && normalizedText.contains(bareRule) { return true }

    return domainCandidates.contains { candidate in
      candidate == rule || candidate.hasSuffix(".\(rule)") || candidate == bareRule
        || candidate.hasSuffix(".\(bareRule)")
    }
  }

  private static func domainCandidates(in text: String) -> [String] {
    let pattern = #"(?i)\b(?:https?://)?(?:www\.)?([a-z0-9][a-z0-9-]*(?:\.[a-z0-9][a-z0-9-]*)+)\b"#
    guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
    let range = NSRange(text.startIndex..<text.endIndex, in: text)
    let matches = regex.matches(in: text, range: range)
    var seen = Set<String>()
    return matches.compactMap { match in
      guard match.numberOfRanges > 1,
        let swiftRange = Range(match.range(at: 1), in: text)
      else { return nil }
      let domain = String(text[swiftRange])
        .trimmingCharacters(in: CharacterSet(charactersIn: ".,;:()[]{}<>\"'"))
        .lowercased()
      guard !domain.isEmpty else { return nil }
      return seen.insert(domain).inserted ? domain : nil
    }
  }

  @MainActor
  private static func frontmostWindowTitle(for processIdentifier: pid_t) -> String? {
    guard
      let windows = CGWindowListCopyWindowInfo(
        [.optionOnScreenOnly, .excludeDesktopElements],
        kCGNullWindowID
      ) as? [[String: Any]]
    else {
      return nil
    }

    for window in windows {
      guard let ownerPID = window[kCGWindowOwnerPID as String] as? pid_t,
        ownerPID == processIdentifier
      else {
        continue
      }
      guard let layer = window[kCGWindowLayer as String] as? Int, layer == 0 else {
        continue
      }
      guard let title = window[kCGWindowName as String] as? String,
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
      else {
        continue
      }
      return title
    }
    return nil
  }

  private static func applicationSearchRoots(fileManager: FileManager) -> [URL] {
    let paths = [
      "/Applications",
      "/System/Applications",
      NSHomeDirectory() + "/Applications",
    ]

    var seen = Set<String>()
    return paths.compactMap { path in
      let url = URL(fileURLWithPath: path, isDirectory: true)
      guard fileManager.fileExists(atPath: url.path) else { return nil }
      let standardizedPath = url.standardizedFileURL.path
      return seen.insert(standardizedPath).inserted ? url : nil
    }
  }

  private static func installedApplication(from url: URL) -> RecordingPrivacyApplication? {
    guard let bundle = Bundle(url: url),
      let bundleIdentifier = bundle.bundleIdentifier,
      !bundleIdentifier.isEmpty
    else {
      return nil
    }

    let displayName =
      bundle.localizedInfoDictionary?["CFBundleDisplayName"] as? String
      ?? bundle.localizedInfoDictionary?["CFBundleName"] as? String
      ?? bundle.infoDictionary?["CFBundleDisplayName"] as? String
      ?? bundle.infoDictionary?["CFBundleName"] as? String
      ?? url.deletingPathExtension().lastPathComponent

    return RecordingPrivacyApplication(
      name: displayName,
      bundleIdentifier: bundleIdentifier,
      appURL: url
    )
  }
}
