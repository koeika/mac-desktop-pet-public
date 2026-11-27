import AppKit
import CodexPetCore
import SwiftUI

enum LearningPlanRegression {
    @MainActor static func run() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try AppDataStore(root: root)
        let now = Date(timeIntervalSince1970: floor(Date().timeIntervalSince1970))
        let pack = DictionaryPack(id: "plan-fixture", name: "学习计划验证", entries: [
            DictionaryEntry(term: "due", meaning: "到期"), DictionaryEntry(term: "new", meaning: "新词"),
            DictionaryEntry(term: "seen", meaning: "仅展示"), DictionaryEntry(term: "legacy", meaning: "旧记录")
        ])
        try JSONFileStore.save(pack, to: store.dictionariesURL.appendingPathComponent("\(pack.id).json"))
        store.dictionaries.append(pack)
        let word = try store.captureWord(CapturePayload(term: "review", meaning: "复习"))
        store.settings.enabledDictionaryIDs = [pack.id, word.dictionaryID]
        store.saveSettings()
        let due = ScopedDictionaryEntry(dictionaryID: pack.id, dictionaryName: pack.name, entry: pack.entries[0])
        let seen = ScopedDictionaryEntry(dictionaryID: pack.id, dictionaryName: pack.name, entry: pack.entries[2])
        let personal = ScopedDictionaryEntry(dictionaryID: word.dictionaryID, dictionaryName: "我的生词", entry: word.entry)
        let legacyKey = WordStat.key(dictionaryID: pack.id, term: "legacy")
        store.vocabularyProgress.stats[legacyKey] = WordStat(learned: true, seenCount: 3,
            lastAction: .known, updatedAt: now.addingTimeInterval(-864000))
        try store.reviewWord(due, action: .unknown, now: now.addingTimeInterval(-3600))
        try store.reviewWord(personal, action: .unknown, now: now.addingTimeInterval(-86400))
        try store.reviewWord(personal, action: .known, now: now)
        store.recordVocabularyPresentation(seen, automatic: false, now: now)
        let diskBefore = try Data(contentsOf: store.progressURL)
        let notebookBefore = try Data(contentsOf: store.personalVocabularyURL)
        let index = VocabularyLibraryIndex()
        await index.reload(store: store, now: now)
        precondition(index.studyProgress.total == 5 && index.studyProgress.studied == 2)
        precondition(index.studyProgress.due == 1 && index.studyProgress.reviewedToday == 1)
        precondition(index.studyProgress.legacyUnverified == 1 && index.studyProgress.legacyDue == 1)
        let summary = index.dictionaries.first { $0.id == pack.id }!
        precondition(summary.studyProgress.studied == 1 && summary.studyProgress.total == 4)
        precondition(summary.studyProgress.legacyUnverified == 1)
        precondition(summary.studyProgress.familiar == 0 && summary.studyProgress.learning == 1)
        precondition(summary.studyProgress.seenOnly == 1)
        precondition(store.nextReviewWord(now: now, automatic: false)?.statKey == legacyKey,
            "Excluding unverified progress must not silently discard the oldest scheduled legacy word")
        let withoutLegacy = VocabularyReviewScheduler.pick(from: store.enabledEntries().filter { $0.statKey != legacyKey },
            stats: store.vocabularyProgress.stats, capturedAt: [:], now: now, newIntroducedToday: 0, newLimit: 3)
        precondition(withoutLegacy?.statKey == due.statKey)
        store.toggleDictionary(pack.id, isEnabled: false)
        await index.reload(store: store, now: now)
        precondition(index.studyProgress.total == 1 && index.studyProgress.due == 0)
        precondition(index.dictionaries.first { $0.id == pack.id }!.studyProgress.studied == 1)
        let restarted = try AppDataStore(root: root)
        precondition(!restarted.settings.enabledDictionaryIDs.contains(pack.id))
        await index.reload(store: restarted, now: now)
        precondition(index.studyProgress.studied == 1 && index.studyProgress.reviewedToday == 1)
        let historyAfter = try Data(contentsOf: restarted.progressURL)
        let notebookAfter = try Data(contentsOf: restarted.personalVocabularyURL)
        precondition(historyAfter == diskBefore && notebookAfter == notebookBefore)
        restarted.toggleDictionary(pack.id, isEnabled: true)
        await index.reload(store: restarted, now: now)
        let studiedBefore = index.studyProgress.studied
        try restarted.reviewWord(seen, action: .hard, now: now)
        await index.reload(store: restarted, now: now)
        precondition(index.studyProgress.studied == studiedBefore + 1)
        let readback = try AppDataStore(root: root)
        precondition(readback.vocabularyProgress.stats[seen.statKey]?.lastAction == .hard)
        precondition(readback.vocabularyProgress.stats[due.statKey]?.review == store.vocabularyProgress.stats[due.statKey]?.review)
        precondition(readback.vocabularyProgress.stats[legacyKey]?.learned == true)
        precondition(readback.vocabularyProgress.stats[legacyKey]?.review == nil)
        let markedBefore = readback.vocabularyProgress
        let dictionaryBefore = try Data(contentsOf: readback.dictionariesURL.appendingPathComponent("\(pack.id).json"))
        let notebookBeforeCleanup = try Data(contentsOf: readback.personalVocabularyURL)
        readback.vocabularyProgress.stats["plan-fixture::unmarked"] = WordStat(seenCount: 4)
        try JSONFileStore.save(readback.vocabularyProgress, to: readback.progressURL)
        let removed = try readback.cleanUnmarkedLearningProgress()
        precondition(removed == 1)
        let afterCleanup = try AppDataStore(root: root)
        precondition(afterCleanup.vocabularyProgress == markedBefore)
        let dictionaryAfter = try Data(contentsOf: afterCleanup.dictionariesURL.appendingPathComponent("\(pack.id).json"))
        let notebookAfterCleanup = try Data(contentsOf: afterCleanup.personalVocabularyURL)
        precondition(dictionaryAfter == dictionaryBefore && notebookAfterCleanup == notebookBeforeCleanup)
        let repeatedRemoval = try afterCleanup.cleanUnmarkedLearningProgress()
        precondition(repeatedRemoval == 0)
        let backups = try FileManager.default.contentsOfDirectory(atPath: root.path)
            .filter { $0.hasPrefix("learning-progress.before-unmarked-cleanup-") }
        precondition(backups.count == 1)
        afterCleanup.settings.syncFilePath = root.appendingPathComponent("sync-fixture.json").path
        var refusedSync = false
        do { _ = try afterCleanup.cleanUnmarkedLearningProgress() } catch { refusedSync = true }
        precondition(refusedSync)
        print("learning-plan-regression: verified feedback vs exposure/legacy, dictionary progress, enabled-source queue, toggle/restart readback, index refresh and byte-identical history/notebook preserved")
        print("progress-cleanup-regression: backup, one unmarked record removed, marked/legacy/word files preserved, restart/idempotence and active-sync refusal passed")
    }
}
