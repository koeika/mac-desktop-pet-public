import AppKit
import CodexPetCore

extension AppDataStore {
    var personalVocabularyURL: URL { rootURL.appendingPathComponent("personal-vocabulary.json") }

    @discardableResult
    func captureWord(_ payload: CapturePayload) throws -> CapturedWord {
        var updated = personalVocabulary
        let word = try updated.capture(payload)
        try JSONFileStore.save(updated, to: personalVocabularyURL)
        objectWillChange.send()
        personalVocabulary = updated
        settings.enabledDictionaryIDs.insert(word.dictionaryID)
        saveSettings()
        return word
    }

    func deleteCapturedWord(_ word: CapturedWord) throws {
        var updated = personalVocabulary
        updated.words.removeAll { $0.id == word.id }
        try JSONFileStore.save(updated, to: personalVocabularyURL)
        objectWillChange.send()
        personalVocabulary = updated
    }

    func updateCapturedWord(id: String, payload: CapturePayload) throws {
        let value = try payload.validated()
        var updated = personalVocabulary
        guard let index = updated.words.firstIndex(where: { $0.id == id }) else {
            throw CaptureError.invalid("词条已被删除。")
        }
        guard updated.words[index].content.term == value.term,
              updated.words[index].content.language == value.language else {
            throw CaptureError.invalid("编辑时请保留单词与语言，避免丢失对应的复习记录。")
        }
        updated.words[index].content = value
        updated.words[index].updatedAt = Date()
        try JSONFileStore.save(updated, to: personalVocabularyURL)
        objectWillChange.send()
        personalVocabulary = updated
    }

    func handleVocabularyRequest(method: String, body: Data) throws -> Data {
        if method == "POST" {
            let word = try captureWord(JSONFileStore.decoder.decode(CapturePayload.self, from: body))
            return try JSONFileStore.encoder.encode(CaptureResponse(ok: true, word: word))
        }
        return try JSONFileStore.encoder.encode(NotebookResponse(ok: true, words: personalVocabulary.words))
    }

    func nextReviewWord(now: Date = Date(), automatic: Bool) -> ScopedDictionaryEntry? {
        resetVocabularyScheduleIfNeeded(now: now)
        let capturedAt = Dictionary(uniqueKeysWithValues: personalVocabulary.words.map { ($0.statKey, $0.createdAt) })
        return VocabularyReviewScheduler.pick(
            from: enabledEntries().filter { !$0.entry.meaning.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty },
            stats: vocabularyProgress.stats, capturedAt: capturedAt, now: now,
            newIntroducedToday: automatic ? settings.newVocabularyKeys.count : 0,
            newLimit: automatic ? settings.dailyNewVocabularyLimit : Int.max,
            reserveNewSlot: settings.vocabularyShownCount % 4 == 0,
            introducedKeys: Set(settings.newVocabularyKeys)
        )
    }

    func recordVocabularyPresentation(_ word: ScopedDictionaryEntry, automatic: Bool, now: Date = Date()) {
        if automatic {
            let stat = vocabularyProgress.stats[word.statKey]
            if stat?.review == nil && stat?.lastAction == nil && !settings.newVocabularyKeys.contains(word.statKey) {
                settings.newVocabularyKeys.append(word.statKey)
            }
            recordAutomaticVocabularyShown(now: now)
        }
        vocabularyProgress.recordSeen(dictionaryID: word.dictionaryID, term: word.entry.term, at: now)
        saveLearningProgress()
    }

    func reviewWord(_ word: ScopedDictionaryEntry, action: WordAction, now: Date = Date()) throws {
        var updated = vocabularyProgress
        updated.stats[word.statKey] = try VocabularyReviewScheduler.next(
            updated.stats[word.statKey], action: action, now: now, retention: settings.vocabularyRetention)
        // Persist before acknowledging feedback; preserve the legacy file before its first upgrade.
        let backup = rootURL.appendingPathComponent("learning-progress.pre-fsrs.json")
        if FileManager.default.fileExists(atPath: progressURL.path), !FileManager.default.fileExists(atPath: backup.path) {
            try FileManager.default.copyItem(at: progressURL, to: backup)
        }
        try JSONFileStore.save(updated, to: progressURL)
        vocabularyProgress = updated
        saveLearningProgress()
    }

    func reviewPreview(_ word: ScopedDictionaryEntry, action: WordAction, now: Date = Date()) -> String {
        guard let next = try? VocabularyReviewScheduler.next(vocabularyProgress.stats[word.statKey],
            action: action, now: now, retention: settings.vocabularyRetention) else { return "" }
        let due = VocabularyReviewScheduler.dueDate(next, now: now)
        let minutes = max(1, Int(ceil(due.timeIntervalSince(now) / 60)))
        return minutes < 60 ? "\(minutes) 分钟" : (minutes < 1440 ? "\(minutes / 60) 小时" : "\(minutes / 1440) 天")
    }

    var dueVocabularyCount: Int {
        let now = Date()
        return enabledEntries().filter {
            let stat = vocabularyProgress.stats[$0.statKey]
            return (stat?.review != nil || stat?.lastAction != nil)
                && VocabularyReviewScheduler.dueDate(stat, now: now) <= now
        }.count
    }
}

private struct CaptureResponse: Codable { var ok: Bool; var word: CapturedWord }
private struct NotebookResponse: Codable { var ok: Bool; var words: [CapturedWord] }
