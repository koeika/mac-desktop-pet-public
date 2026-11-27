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
            DictionaryEntry(term: "seen", meaning: "仅展示")
        ])
        try JSONFileStore.save(pack, to: store.dictionariesURL.appendingPathComponent("\(pack.id).json"))
        store.dictionaries.append(pack)
        let word = try store.captureWord(CapturePayload(term: "review", meaning: "复习"))
        store.settings.enabledDictionaryIDs = [pack.id, word.dictionaryID]
        store.saveSettings()
        let due = ScopedDictionaryEntry(dictionaryID: pack.id, dictionaryName: pack.name, entry: pack.entries[0])
        let seen = ScopedDictionaryEntry(dictionaryID: pack.id, dictionaryName: pack.name, entry: pack.entries[2])
        let personal = ScopedDictionaryEntry(dictionaryID: word.dictionaryID, dictionaryName: "我的生词", entry: word.entry)
        try store.reviewWord(due, action: .unknown, now: now.addingTimeInterval(-3600))
        try store.reviewWord(personal, action: .unknown, now: now.addingTimeInterval(-86400))
        try store.reviewWord(personal, action: .known, now: now)
        store.recordVocabularyPresentation(seen, automatic: false, now: now)
        let diskBefore = try Data(contentsOf: store.progressURL)
        let notebookBefore = try Data(contentsOf: store.personalVocabularyURL)
        let index = VocabularyLibraryIndex()
        await index.reload(store: store, now: now)
        precondition(index.studyProgress.total == 4 && index.studyProgress.studied == 2)
        precondition(index.studyProgress.due == 1 && index.studyProgress.reviewedToday == 1)
        let summary = index.dictionaries.first { $0.id == pack.id }!
        precondition(summary.studyProgress.studied == 1 && summary.studyProgress.total == 3)
        precondition(summary.studyProgress.familiar == 0 && summary.studyProgress.learning == 1)
        precondition(summary.studyProgress.seenOnly == 1)
        precondition(store.nextReviewWord(now: now, automatic: false)?.statKey == due.statKey)
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
        print("learning-plan-regression: feedback vs exposure, dictionary progress, enabled-source queue, toggle/restart readback, index refresh and byte-identical history/notebook preserved")
    }
}
