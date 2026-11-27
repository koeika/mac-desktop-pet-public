import Foundation
import CodexPetCore

extension AppDataStore {
    /// Never run automatically: this discards only exposure metadata after a backup.
    func cleanUnmarkedLearningProgress() throws -> Int {
        let lock = try LearningProgressLock(root: rootURL)
        defer { withExtendedLifetime(lock) {} }
        guard syncFileURL == nil else {
            throw NSError(domain: "LearningProgressCleanup", code: 1,
                userInfo: [NSLocalizedDescriptionKey: "请先停用学习文件同步，再清理无标记记录，避免旧展示记录重新同步回来。"])
        }
        guard FileManager.default.fileExists(atPath: progressURL.path) else { return 0 }
        let source = try Data(contentsOf: progressURL)
        let current = try JSONFileStore.decoder.decode(VocabularyProgress.self, from: source)
        let cleaned = current.removingUnmarkedLegacyRecords()
        let removed = current.stats.count - cleaned.stats.count
        guard removed > 0 else { return 0 }
        let backup = rootURL.appendingPathComponent("learning-progress.before-unmarked-cleanup-\(UUID().uuidString).json")
        try FileManager.default.copyItem(at: progressURL, to: backup)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: backup.path)
        guard try Data(contentsOf: progressURL) == source else {
            throw NSError(domain: "LearningProgressCleanup", code: 2,
                userInfo: [NSLocalizedDescriptionKey: "学习记录在维护期间发生变化，已取消清理。"])
        }
        try JSONFileStore.save(cleaned, to: progressURL)
        vocabularyProgress = cleaned
        objectWillChange.send()
        return removed
    }
}
