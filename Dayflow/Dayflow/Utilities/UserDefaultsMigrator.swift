import Foundation

enum UserDefaultsMigrator {
  private static let sentinelKey = "didMigrateFromSandboxDefaults"
  private static let skippedKeyPrefixes = ["NS", "Apple", "AV", "SU"]
  private static let priorDevBundleID = "teleportlabs.com.Dayflow.dev"

  static func migrateIfNeeded(
    defaults: UserDefaults = .standard,
    fileManager: FileManager = .default
  ) {
    if defaults.bool(forKey: sentinelKey) {
      return
    }

    guard let bundleId = Bundle.main.bundleIdentifier else {
      defaults.set(true, forKey: sentinelKey)
      return
    }

    // Dayward has a new bundle identifier. Preserve existing local settings
    // from the prior fork before considering the older sandbox migration.
    if bundleId != priorDevBundleID,
      let priorDomain = defaults.persistentDomain(forName: priorDevBundleID),
      priorDomain.isEmpty == false
    {
      let filteredPrior = priorDomain.filter { key, _ in
        guard key != sentinelKey else { return false }
        return skippedKeyPrefixes.contains { prefix in key.hasPrefix(prefix) } == false
      }
      if filteredPrior.isEmpty == false {
        var mergedDomain = defaults.persistentDomain(forName: bundleId) ?? [:]
        for (key, value) in filteredPrior where mergedDomain[key] == nil {
          mergedDomain[key] = value
        }
        defaults.setPersistentDomain(mergedDomain, forName: bundleId)
        defaults.set(true, forKey: sentinelKey)
        print("UserDefaultsMigrator: copied \(filteredPrior.count) settings from the prior Dev build")
        return
      }
    }

    let containerPlistURL = fileManager.homeDirectoryForCurrentUser
      .appendingPathComponent(
        "Library/Containers/\(bundleId)/Data/Library/Preferences/\(bundleId).plist")

    guard fileManager.fileExists(atPath: containerPlistURL.path) else {
      defaults.set(true, forKey: sentinelKey)
      return
    }

    guard let legacyDomain = NSDictionary(contentsOf: containerPlistURL) as? [String: Any],
      legacyDomain.isEmpty == false
    else {
      defaults.set(true, forKey: sentinelKey)
      return
    }

    let filteredLegacy = legacyDomain.filter { key, _ in
      guard key != sentinelKey else { return false }
      return skippedKeyPrefixes.contains { prefix in key.hasPrefix(prefix) } == false
    }

    if filteredLegacy.isEmpty {
      defaults.set(true, forKey: sentinelKey)
      return
    }

    var mergedDomain = defaults.persistentDomain(forName: bundleId) ?? [:]
    for (key, value) in filteredLegacy {
      mergedDomain[key] = value
    }

    defaults.setPersistentDomain(mergedDomain, forName: bundleId)
    defaults.set(true, forKey: sentinelKey)

    print("UserDefaultsMigrator: migrated \(filteredLegacy.count) keys from sandbox defaults")
  }
}
