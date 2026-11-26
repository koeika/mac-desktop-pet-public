import CodexPetCore
import Foundation

enum LibraryBrowserRegression {
    @MainActor static func run() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try AppDataStore(root: root)
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let fixtures: [[String: Any]] = (0..<10_000).map { i in
            let payload: [String: Any] = ["term": String(format: "fixture%05d", i), "language": i % 2 == 0 ? "en" : "ja",
                "meaning": "释义 \(i)", "phoneticUS": "/fixture/", "sourceTitle": "Source \(i)"]
                .merging(i % 4 == 0 ? ["sourceURL": "https://example.org/fixture"] : [:]) { _, new in new }
            return ["id": "fixture-\(i)", "content": payload, "createdAt": "2026-01-01T00:00:00Z",
                    "updatedAt": "2026-01-01T00:00:00Z", "contexts": []]
        }
        let words = try JSONFileStore.decoder.decode([CapturedWord].self, from: JSONSerialization.data(withJSONObject: fixtures))
        var stats: [String: WordStat] = [:]
        for (i, word) in words.enumerated() {
            var stat = WordStat(learned: i % 5 == 0, seenCount: 1,
                lastAction: i % 5 == 0 ? .known : i % 5 == 1 ? .unknown : nil, updatedAt: now)
            stat.legacyDueAt = now.addingTimeInterval(i % 5 == 1 ? -60 : 3600)
            stats[word.statKey] = stat
        }
        let before = try JSONFileStore.encoder.encode(words)
        let progressBefore = try JSONFileStore.encoder.encode(VocabularyProgress(stats: stats))
        let started = Date()
        let rows = words.map { NotebookRow(word: $0, stat: stats[$0.statKey], now: now) }
        precondition(rows.count == 10_000)
        precondition(NotebookQuery(state: "新收藏").apply(to: rows, now: now).count == 6000)
        precondition(NotebookQuery(state: "已掌握").apply(to: rows, now: now).count == 2000)
        precondition(NotebookQuery(state: "到期复习").apply(to: rows, now: now).count == 2000)
        precondition(NotebookQuery(language: "ja").apply(to: rows, now: now).count == 5000)
        precondition(NotebookQuery(source: "有网页来源").apply(to: rows, now: now).count == 2500)
        precondition(NotebookQuery(search: "FIXTURE09999").apply(to: rows, now: now).first?.word.content.term == "fixture09999")
        precondition(NotebookQuery(search: "Source 9999").apply(to: rows, now: now).count == 1)
        precondition(NotebookQuery(search: "/fixture/").apply(to: rows, now: now).count == 10_000)
        precondition(NotebookQuery(search: "nonexistent").apply(to: rows, now: now).isEmpty)
        precondition(NotebookQuery(state: "已掌握", language: "ja", source: "有网页来源").apply(to: rows, now: now).isEmpty)
        let sorted = NotebookQuery(sort: "单词 A-Z").apply(to: rows, now: now)
        precondition(sorted.first?.word.content.term == "fixture00000" && sorted.last?.word.content.term == "fixture09999")
        let second = LibraryPage(count: sorted.count, size: 20, requested: 2)
        precondition(sorted[second.range].first?.word.content.term == "fixture00020")
        let last = LibraryPage(count: 10_001, size: 100, requested: 999)
        precondition(last.number == 101 && last.range == 10_000..<10_001)
        precondition(LibraryPage(count: 0, size: 0, requested: -4).number == 1)
        precondition(LibraryPage(count: 21, size: 20, requested: 2).range.count == 1)
        precondition(LibraryPage(count: 20, size: 20, requested: 2).number == 1, "Deleting the last page must clamp to the previous page")
        var covered = Set<String>()
        for page in 1...500 {
            for row in sorted[LibraryPage(count: sorted.count, size: 20, requested: page).range] {
                precondition(covered.insert(row.id).inserted, "A row must appear once across pages")
            }
        }
        precondition(covered.count == words.count)
        let dictionaries = (0..<2000).map { i in
            DictionaryPack(id: "library-\(i)", name: String(format: "词典%04d", i), description: "分类：\(i % 2 == 0 ? "日语" : "IELTS")",
                entries: (0..<(i % 10 + 1)).map { DictionaryEntry(term: "term\($0)", meaning: "meaning") })
        }
        let summaries = AppDataStore.dictionarySummaries(packs: dictionaries, stats: [:], enabledIDs: ["library-0"])
        precondition(DictionaryLibraryQuery(category: "日语").apply(to: summaries).count == 1000)
        precondition(DictionaryLibraryQuery(enabled: "已启用").apply(to: summaries).map(\.id) == ["library-0"])
        precondition(DictionaryLibraryQuery(search: "词典1999").apply(to: summaries).count == 1)
        precondition(DictionaryLibraryQuery(source: "内置").apply(to: summaries).isEmpty)
        precondition(DictionaryLibraryQuery(sort: "词数最多").apply(to: summaries).first?.pack.entries.count == 10)
        let elapsed = Date().timeIntervalSince(started)
        let after = try JSONFileStore.encoder.encode(words)
        let progressAfter = try JSONFileStore.encoder.encode(VocabularyProgress(stats: stats))
        precondition(after == before && progressAfter == progressBefore)
        var payload = CapturePayload(term: "fixture-preservation", meaning: "保留释义")
        payload.example = "A fixture."
        payload.exampleTranslation = "示例。"
        let word = try store.captureWord(payload)
        try store.reviewWord(ScopedDictionaryEntry(dictionaryID: word.dictionaryID, dictionaryName: "个人", entry: word.entry), action: .unknown, now: now)
        let notebookDisk = try Data(contentsOf: store.personalVocabularyURL)
        let progressDisk = try Data(contentsOf: store.progressURL)
        let index = VocabularyLibraryIndex()
        await index.reload(store: store, now: now)
        precondition(index.words.count == 1 && index.dictionaries.count == store.dictionaries.count)
        precondition(index.words[0].word.contexts == word.contexts)
        let notebookAfter = try Data(contentsOf: store.personalVocabularyURL)
        let diskProgressAfter = try Data(contentsOf: store.progressURL)
        precondition(notebookAfter == notebookDisk && diskProgressAfter == progressDisk)
        let revision = store.libraryRevision
        try store.deleteCapturedWord(word)
        precondition(store.libraryRevision > revision)
        await index.reload(store: store, now: now)
        precondition(index.words.isEmpty && index.dueWords == 0)
        let reloaded = try AppDataStore(root: root)
        precondition(reloaded.vocabularyProgress.stats[word.statKey]?.lastAction == .unknown)
        let workStarted = AsyncStream<Void>.makeStream()
        let workerCancellation = AsyncStream<Bool>.makeStream()
        let cancellationGate = DispatchSemaphore(value: 0)
        let canceledQuery = Task {
            try await libraryBackground {
                workStarted.continuation.yield(())
                cancellationGate.wait()
                workerCancellation.continuation.yield(Task.isCancelled)
                try Task.checkCancellation()
                return NotebookQuery().apply(to: rows, now: now)
            }
        }
        for await _ in workStarted.stream { break }
        canceledQuery.cancel()
        cancellationGate.signal()
        for await observed in workerCancellation.stream {
            precondition(observed, "Cancellation must propagate into the detached worker, not only its caller")
            break
        }
        do {
            _ = try await canceledQuery.value
            preconditionFailure("Canceled background work must not publish a result")
        } catch is CancellationError {} catch { throw error }
        store.personalVocabulary.words = words
        let oldReady = AsyncStream<Void>.makeStream()
        let releaseOld = AsyncStream<Void>.makeStream()
        let obsoleteIndex = Task {
            await index.reload(store: store, now: now, beforePublishing: {
                oldReady.continuation.yield(())
                for await _ in releaseOld.stream { break }
            })
        }
        for await _ in oldReady.stream { break }
        store.personalVocabulary.words = []
        await index.reload(store: store, now: now)
        releaseOld.continuation.yield(())
        await obsoleteIndex.value
        precondition(index.words.isEmpty, "An obsolete index must not replace a newer data snapshot")
        if let directory = ProcessInfo.processInfo.environment["WHISKYCLING_LIBRARY_FIXTURE_DIR"] {
            let fixtureRoot = URL(fileURLWithPath: directory)
            guard !FileManager.default.fileExists(atPath: fixtureRoot.path) else {
                throw CocoaError(.fileWriteFileExists)
            }
            var notebook = PersonalVocabulary()
            notebook.words = Array(words.prefix(105))
            try JSONFileStore.save(notebook, to: fixtureRoot.appendingPathComponent("personal-vocabulary.json"))
            try JSONFileStore.save(VocabularyProgress(stats: stats), to: fixtureRoot.appendingPathComponent("learning-progress.json"))
            for pack in dictionaries.prefix(48) {
                try JSONFileStore.save(pack, to: fixtureRoot.appendingPathComponent("Dictionaries/\(pack.id).json"))
            }
            var settings = AppSettings()
            settings.serverPort = 4791
            settings.walkingPaused = true
            settings.visualTheme = .storybook
            settings.enabledDictionaryIDs = ["library-0", "personal-en", "personal-ja"]
            try JSONFileStore.save(settings, to: fixtureRoot.appendingPathComponent("settings.json"))
            print("library-regression: isolated UI fixture exported (105 words, 48 dictionaries; no personal data)")
        }
        print("library-regression: 10,000 words + 2,000 dictionaries; search/filter/sort, 500 pages without duplicates, empty/delete boundaries and storage preservation passed; workload \(String(format: "%.3f", elapsed))s (not a baseline comparison)")
    }
}
