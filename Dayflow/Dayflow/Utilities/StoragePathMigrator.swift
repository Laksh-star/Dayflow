import Foundation

enum StoragePathMigrator {
  private static let migrationFlagKey = "didMigrateToDayward"
  private static let priorDevFolder = "DayflowDev"
  private static let supportFolder = "Dayward"

  static func migrateIfNeeded() {
    let defaults = UserDefaults.standard
    if defaults.bool(forKey: migrationFlagKey) {
      print("ℹ️ StoragePathMigrator: skipping – already migrated")
      return
    }

    guard let bundleID = Bundle.main.bundleIdentifier else {
      print("⚠️ StoragePathMigrator: missing bundle identifier, marking migration as complete")
      defaults.set(true, forKey: migrationFlagKey)
      return
    }

    let fileManager = FileManager.default
    guard
      let newSupport = try? fileManager.url(
        for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
    else {
      print("⚠️ StoragePathMigrator: unable to resolve unsandboxed Application Support directory")
      return
    }

    let destinationBase = newSupport.appendingPathComponent(supportFolder, isDirectory: true)
    let previousDevBase = newSupport.appendingPathComponent(priorDevFolder, isDirectory: true)

    // The rebrand uses a new bundle and support namespace. Copy the old fork's
    // data once so it stays available as a rollback path.
    let canReplaceBootstrapDestination = isBootstrapDestination(destinationBase, fileManager: fileManager)
    if canReplaceBootstrapDestination,
      fileManager.fileExists(atPath: previousDevBase.path)
    {
      do {
        if fileManager.fileExists(atPath: destinationBase.path) {
          try fileManager.removeItem(at: destinationBase)
        }
        try fileManager.copyItem(at: previousDevBase, to: destinationBase)
        print("ℹ️ StoragePathMigrator: copied existing Dev data to \(destinationBase.path)")
        defaults.set(true, forKey: migrationFlagKey)
        return
      } catch {
        print("⚠️ StoragePathMigrator: failed to copy existing Dev data: \(error)")
        return
      }
    }

    let legacyBase = fileManager.homeDirectoryForCurrentUser
      .appendingPathComponent(
        "Library/Containers/\(bundleID)/Data/Library/Application Support/\(supportFolder)", isDirectory: true
      )

    guard fileManager.fileExists(atPath: legacyBase.path) else {
      print("ℹ️ StoragePathMigrator: no legacy data to migrate")
      defaults.set(true, forKey: migrationFlagKey)
      return
    }

    let normalizedLegacy = legacyBase.standardizedFileURL.path
    let normalizedDestination = destinationBase.standardizedFileURL.path

    if normalizedLegacy == normalizedDestination {
      print("ℹ️ StoragePathMigrator: source and destination are identical; skipping migration")
      defaults.set(true, forKey: migrationFlagKey)
      return
    }

    do {
      try fileManager.createDirectory(at: destinationBase, withIntermediateDirectories: true)
      try relocateDirectoryContents(from: legacyBase, to: destinationBase, fileManager: fileManager)
      try? fileManager.removeItem(at: legacyBase)
      print(
        "ℹ️ StoragePathMigrator: migrated data from sandbox container to \(destinationBase.path)")
      defaults.set(true, forKey: migrationFlagKey)
    } catch {
      print("⚠️ StoragePathMigrator: migration failed with error: \(error)")
    }
  }

  private static func isBootstrapDestination(_ destination: URL, fileManager: FileManager) -> Bool {
    guard fileManager.fileExists(atPath: destination.path) else { return true }
    let databaseURL = destination.appendingPathComponent("chunks.sqlite")
    guard fileManager.fileExists(atPath: databaseURL.path) else { return true }
    let size = (try? databaseURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
    return size <= 4_096
  }

  private static func relocateDirectoryContents(
    from source: URL, to destination: URL, fileManager: FileManager
  ) throws {
    let contents = try fileManager.contentsOfDirectory(
      at: source,
      includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey],
      options: [.skipsHiddenFiles]
    )

    for item in contents {
      let target = destination.appendingPathComponent(item.lastPathComponent)
      let values = try item.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey])

      if values.isDirectory == true {
        if !fileManager.fileExists(atPath: target.path) {
          try fileManager.createDirectory(at: target, withIntermediateDirectories: true)
        }
        try relocateDirectoryContents(from: item, to: target, fileManager: fileManager)
        try? fileManager.removeItem(at: item)
        continue
      }

      if fileManager.fileExists(atPath: target.path) {
        let existingSize = (try? target.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        let incomingSize = values.fileSize ?? 0

        if existingSize < incomingSize {
          try fileManager.removeItem(at: target)
          try fileManager.moveItem(at: item, to: target)
        } else {
          try fileManager.removeItem(at: item)
        }
      } else {
        let parent = target.deletingLastPathComponent()
        if !fileManager.fileExists(atPath: parent.path) {
          try fileManager.createDirectory(at: parent, withIntermediateDirectories: true)
        }
        try fileManager.moveItem(at: item, to: target)
      }
    }
  }
}
