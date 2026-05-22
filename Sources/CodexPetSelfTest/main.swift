import CodexPetCore
import CoreGraphics
import Foundation

@main
struct CodexPetSelfTest {
    static func main() throws {
        try testCSVImport()
        try testJSONImport()
        testVocabularyWeights()
        testWeightedPetChoice()
        testLearningMerge()
        testProgressState()
        testPetActionMapping()
        testRemotePetURLResolver()
        try testPackageInspection()
        try testPackageZipExtraction()
        try testPDFDictionaryDraftParsing()
        try testOpenAIExamplePayloadAndParsing()
        try testDeepSeekDictionaryParserPayloadAndParsing()
        testVocabularyDisplaySchedule()
        testRandomWanderEngine()
        print("codex-pet-selftest: all checks passed")
    }

    static func testCSVImport() throws {
        let csv = """
        dictionaryName,term,phonetic,meaning,example,hint,tags
        IELTS,coherent,/koʊˈhɪrənt/,"连贯的, 条理清楚的","A coherent essay works.","Use in writing.","writing|academic"
        IELTS,feasible,,可行的,The plan is feasible.,
        """
        let packs = try DictionaryImporter.importPacks(data: Data(csv.utf8), fileName: "ielts.csv")
        try expect(packs.count == 1, "CSV imports one pack")
        try expect(packs[0].name == "IELTS", "CSV dictionary name")
        try expect(packs[0].entries.count == 2, "CSV imports two entries")
        try expect(packs[0].entries[0].meaning == "连贯的, 条理清楚的", "CSV quoted comma")
        try expect(packs[0].entries[0].tags == ["writing", "academic"], "CSV tags")
    }

    static func testJSONImport() throws {
        let json = """
        [
          {"term":"わたし","reading":"watashi","meaning":"我"}
        ]
        """
        let packs = try DictionaryImporter.importPacks(data: Data(json.utf8), fileName: "japanese.json")
        try expect(packs.count == 1, "JSON entry array imports one pack")
        try expect(packs[0].id == "japanese", "JSON fallback id")
        try expect(packs[0].entries.first?.term == "わたし", "JSON entry term")
    }

    static func testVocabularyWeights() {
        precondition(VocabularyPicker.weight(for: WordStat(learned: true)) < VocabularyPicker.weight(for: nil))
        precondition(VocabularyPicker.weight(for: WordStat(unknownCount: 2)) > VocabularyPicker.weight(for: nil))
        precondition(VocabularyPicker.weight(for: WordStat(skippedCount: 3)) < VocabularyPicker.weight(for: nil))

        let entries = [
            ScopedDictionaryEntry(dictionaryID: "a", dictionaryName: "A", entry: DictionaryEntry(term: "a", meaning: "A")),
            ScopedDictionaryEntry(dictionaryID: "b", dictionaryName: "B", entry: DictionaryEntry(term: "b", meaning: "B"))
        ]
        let stats = [
            entries[0].statKey: WordStat(learned: true),
            entries[1].statKey: WordStat(unknownCount: 3)
        ]
        precondition(VocabularyPicker.pick(from: entries, stats: stats, random: 0.99)?.entry.term == "b")
    }

    static func testWeightedPetChoice() {
        precondition(WeightedChoice.pickIndex(weights: [0, 0, 0]) == nil)
        precondition(WeightedChoice.pickIndex(weights: [1, 3], random: 0.1) == 0)
        precondition(WeightedChoice.pickIndex(weights: [1, 3], random: 0.9) == 1)
    }

    static func testLearningMerge() {
        let old = Date(timeIntervalSince1970: 100)
        let new = Date(timeIntervalSince1970: 200)
        let key = WordStat.key(dictionaryID: "ielts", term: "coherent")
        let local = [
            key: WordStat(learned: true, unknownCount: 1, skippedCount: 0, seenCount: 2, lastAction: .known, updatedAt: old)
        ]
        let remote = [
            key: WordStat(learned: false, unknownCount: 3, skippedCount: 2, seenCount: 5, lastAction: .unknown, updatedAt: new)
        ]
        let merged = LearningSync.merge(local: local, remote: remote)
        precondition(merged[key]?.learned == true)
        precondition(merged[key]?.unknownCount == 3)
        precondition(merged[key]?.skippedCount == 2)
        precondition(merged[key]?.seenCount == 5)
        precondition(merged[key]?.lastAction == .unknown)
    }

    static func testProgressState() {
        let store = ProgressStateStore()
        _ = store.apply(ProgressEvent(source: "codex", stage: "read", message: "reading", progress: 10, threadId: "task-1"))
        _ = store.apply(ProgressEvent(source: "codex", stage: "build", message: "building", progress: 50, threadId: "task-1"))
        precondition(store.state.current?.stage == "build")
        precondition(store.state.events.count == 1)
        precondition(store.state.events.first?.progress == 50)
    }

    static func testPetActionMapping() {
        precondition(CodexPetAction.allCases.count == 9)
        precondition(CodexPetAction.idle.rowIndex == 0)
        precondition(CodexPetAction.review.rowIndex == 8)
        precondition(CodexPetAction.normalized("Running Right") == .runningRight)
        precondition(AgentStatus.failed.petAction == .failed)
        precondition(AgentStatus.done.petAction == .waving)
    }

    static func testRemotePetURLResolver() {
        let dashed = try! CodexPetPackageInstaller.remoteReference(for: "https://codex-pets.net/#/pets/mangnei")
        precondition(dashed.id == "mangnei")
        precondition(dashed.metadataURL?.absoluteString == "https://codex-pets.net/api/pets/mangnei")
        precondition(dashed.fallbackZipURL?.absoluteString == "https://codex-pets.net/api/pets/mangnei/download")

        let gallery = try! CodexPetPackageInstaller.remoteReference(for: "https://codexpets.net/gallery/poro")
        precondition(gallery.id == "poro")
        precondition(gallery.fallbackZipURL?.absoluteString == "https://codexpets.net/api/gallery-pets/poro/download")

        let zip = try! CodexPetPackageInstaller.remoteReference(for: "https://example.com/pets/cat.zip")
        precondition(zip.directZipURL?.lastPathComponent == "cat.zip")
    }

    static func testPackageInspection() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("codex-pet-selftest-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let manifest = """
        {
          "id": "poro",
          "displayName": "Poro",
          "description": "Test pet",
          "spritesheetPath": "spritesheet.png",
          "framesPerAction": 8
        }
        """
        try Data(manifest.utf8).write(to: root.appendingPathComponent("pet.json"))
        try Data([0x89, 0x50, 0x4E, 0x47]).write(to: root.appendingPathComponent("spritesheet.png"))

        let inspection = try CodexPetPackageInstaller.inspectPackage(at: root)
        try expect(inspection.manifest.id == "poro", "package id")
        try expect(inspection.manifest.resolvedDisplayName == "Poro", "package display name")
        try expect(inspection.spriteFileName == "spritesheet.png", "package sprite")
        try expect(inspection.framesPerAction == 8, "package frame count")
    }

    static func testPackageZipExtraction() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("codex-pet-zip-selftest-\(UUID().uuidString)", isDirectory: true)
        let package = root.appendingPathComponent("sample-pet", isDirectory: true)
        let output = root.appendingPathComponent("output", isDirectory: true)
        let zipURL = root.appendingPathComponent("sample-pet.zip")
        try FileManager.default.createDirectory(at: package, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let manifest = """
        {
          "id": "sample-pet",
          "displayName": "Sample Pet",
          "spritesheetPath": "spritesheet.webp"
        }
        """
        try Data(manifest.utf8).write(to: package.appendingPathComponent("pet.json"))
        try Data("fake-webp-for-package-shape".utf8).write(to: package.appendingPathComponent("spritesheet.webp"))
        try createZip(at: zipURL, from: package, workingDirectory: root)

        let extracted = try CodexPetPackageInstaller.extractZip(zipURL, to: output)
        let inspection = try CodexPetPackageInstaller.inspectPackage(at: extracted)
        try expect(inspection.manifest.id == "sample-pet", "zip package id")
        try expect(inspection.spriteFileName == "spritesheet.webp", "zip package sprite")
    }

    static func testPDFDictionaryDraftParsing() throws {
        let text = """
        词单：第八课@MOちゃん
        序号 发音 单词 释义
        1 ちいさい 小さい [形] 小；微少；轻微
        2 ならこうえん 奈良公園 [名] 奈良市街地東部にある公園。
        [形] 这是一行错位释义，不应被识别成词条
        忙しい [形] 忙，忙碌；急急忙忙
        べんり义 便利 [名・形] 便利，方便
        ならこうえん 奈良公園 [名] 奈良市街地東部にある公園。
        为生存和发展而进 生活，生维持度日的活动
        coherent /koʊˈhɪrənt/ 连贯的；条理清楚的
        feasible 可行的
        たべます （tabemasu） 吃
        25 まち 町 [名] 镇；城镇；町
        page 12
        MOJi 辞書
        """
        let draft = try PDFDictionaryImporter.draft(fromText: text, fileName: "ielts-sample.pdf")
        try expect(draft.dictionaryName == "ielts-sample", "PDF draft name")
        try expect(draft.entries.count >= 6, "PDF draft entry count")
        let coherent = draft.entries.first { $0.term == "coherent" }
        let japanese = draft.entries.first { $0.term == "たべます" }
        let small = draft.entries.first { $0.term == "小さい" }
        let town = draft.entries.first { $0.term == "町" }
        let busy = draft.entries.first { $0.term == "忙しい" }
        let convenient = draft.entries.first { $0.term == "便利" }
        try expect(coherent?.phonetic == "koʊˈhɪrənt", "PDF draft phonetic")
        try expect(japanese?.reading == "tabemasu", "PDF draft Japanese reading")
        try expect(small?.reading == "ちいさい", "PDF table reading")
        try expect(small?.meaning.contains("微少") == true, "PDF table meaning")
        try expect(town?.reading == "まち", "PDF table later row")
        try expect(busy?.reading == nil, "PDF POS marker is not reading")
        try expect(busy?.meaning.contains("[形]") == true, "PDF POS marker kept in meaning")
        try expect(convenient?.reading == "べんり", "PDF repairs reading with header artifact")
        try expect(!draft.entries.contains { $0.term == "べんり义" || $0.term == "为生存和发展而进" }, "PDF skips reading/header artifacts and long Chinese fragments")
        try expect(!draft.entries.contains { $0.term == "序号" || $0.term == "发音" || $0.term == "单词" || $0.term == "释义" || $0.term == "[形]" }, "PDF draft skips table headers and POS-only terms")
        try expect(!draft.entries.contains { $0.term.lowercased() == "page" }, "PDF draft skips page noise")
        try expect(draft.pack.entries.count >= 6, "PDF draft pack entries")
    }

    static func testOpenAIExamplePayloadAndParsing() throws {
        let longContext = String(repeating: "context-", count: 80)
        let entries = [
            DictionaryImportDraftEntry(
                term: "coherent",
                phonetic: "koʊˈhɪrənt",
                meaning: "连贯的",
                context: longContext,
                confidence: 0.9,
                needsReview: false
            )
        ]
        let body = try OpenAIExampleGenerator.buildRequestBody(entries: entries, model: "gpt-5.2")
        let bodyText = String(data: body, encoding: .utf8) ?? ""
        try expect(bodyText.contains("coherent"), "OpenAI payload contains term")
        try expect(bodyText.contains("连贯的"), "OpenAI payload contains meaning")
        try expect(!bodyText.contains(longContext), "OpenAI payload trims long context")

        let deepSeekBody = try ExampleGenerator.buildRequestBody(entries: entries, model: "deepseek-chat", provider: .deepSeek)
        let deepSeekText = String(data: deepSeekBody, encoding: .utf8) ?? ""
        try expect(deepSeekText.contains("deepseek-chat"), "DeepSeek payload model")
        try expect(deepSeekText.contains("json_object"), "DeepSeek payload JSON mode")
        try expect(!deepSeekText.contains(longContext), "DeepSeek payload trims long context")

        let response = """
        {
          "output_text": "{\\"examples\\":[{\\"term\\":\\"coherent\\",\\"example\\":\\"Her argument was coherent and easy to follow.\\",\\"hint\\":\\"Use it for clear logic.\\"}]}"
        }
        """
        let examples = try OpenAIExampleGenerator.parseResponse(Data(response.utf8))
        try expect(examples.count == 1, "OpenAI response example count")
        try expect(examples[0].term == "coherent", "OpenAI response term")
        try expect(examples[0].example.contains("coherent"), "OpenAI response example")

        let deepSeekResponse = """
        {
          "choices": [
            {
              "message": {
                "content": "{\\"examples\\":[{\\"term\\":\\"coherent\\",\\"example\\":\\"A coherent paragraph has a clear order.\\",\\"hint\\":\\"Use it for clear structure.\\"}]}"
              }
            }
          ]
        }
        """
        let deepSeekExamples = try ExampleGenerator.parseResponse(Data(deepSeekResponse.utf8), provider: .deepSeek)
        try expect(deepSeekExamples.count == 1, "DeepSeek response example count")
        try expect(deepSeekExamples[0].term == "coherent", "DeepSeek response term")
    }

    static func testDeepSeekDictionaryParserPayloadAndParsing() throws {
        let source = """
        序号 发音 单词 释义
        1 ちいさい 小さい [形] 小；微少；轻微
        2 べんり 便利 [名・形] 便利，方便
        """
        let body = try DeepSeekDictionaryParser.buildRequestBody(
            sourceText: source,
            fileName: "moji.pdf",
            dictionaryName: "moji",
            model: "deepseek-chat"
        )
        let bodyText = String(data: body, encoding: .utf8) ?? ""
        try expect(bodyText.contains("json_object"), "DeepSeek parser JSON mode")
        try expect(bodyText.contains("[形]"), "DeepSeek parser source text")
        try expect(bodyText.contains("never put them in reading"), "DeepSeek parser POS instruction")

        let response = """
        {
          "choices": [
            {
              "message": {
                "content": "{\\"dictionaryName\\":\\"moji\\",\\"entries\\":[{\\"term\\":\\"小さい\\",\\"reading\\":\\"ちいさい\\",\\"phonetic\\":\\"\\",\\"meaning\\":\\"[形] 小；微少；轻微\\",\\"example\\":\\"\\",\\"hint\\":\\"\\",\\"tags\\":[\\"第八课\\"]},{\\"term\\":\\"便利\\",\\"reading\\":\\"べんり\\",\\"meaning\\":\\"[名・形] 便利，方便\\"}]}"
              }
            }
          ]
        }
        """
        let draft = try DeepSeekDictionaryParser.parseResponse(
            Data(response.utf8),
            fileName: "moji.pdf",
            fallbackDictionaryName: "fallback",
            sourceText: source
        )
        try expect(draft.dictionaryName == "moji", "DeepSeek parser dictionary name")
        try expect(draft.entries.count == 2, "DeepSeek parser entry count")
        try expect(draft.entries[0].term == "小さい", "DeepSeek parser term")
        try expect(draft.entries[0].reading == "ちいさい", "DeepSeek parser reading")
        try expect(draft.entries[0].meaning.contains("[形]"), "DeepSeek parser POS in meaning")
        try expect(draft.entries[1].reading == "べんり", "DeepSeek parser second reading")
    }

    static func testRandomWanderEngine() {
        var engine = PetBehaviorEngine(origin: CGPoint(x: 100, y: 100))
        let bounds = CGRect(x: 0, y: 0, width: 900, height: 700)
        let size = CGSize(width: 120, height: 120)
        var randomValues = [0.9, 0.0, 0.7, 0.5]
        var previous = engine.origin
        var deltas: [CGPoint] = []
        var idleFrames = 0

        for _ in 0..<170 {
            let state = engine.tick(deltaTime: 0.08, bounds: bounds, petSize: size) {
                if randomValues.isEmpty { return 0.9 }
                return randomValues.removeFirst()
            }
            let delta = CGPoint(x: state.origin.x - previous.x, y: state.origin.y - previous.y)
            if abs(delta.x) > 0.001 || abs(delta.y) > 0.001 {
                deltas.append(delta)
            } else {
                idleFrames += 1
            }
            previous = state.origin
        }

        precondition(deltas.count > 8)
        precondition(idleFrames > 20)
        let first = deltas[0]
        let hasDifferentDelta = deltas.dropFirst().contains {
            abs($0.x - first.x) > 0.01 || abs($0.y - first.y) > 0.01
        }
        precondition(hasDifferentDelta)
    }

    static func testVocabularyDisplaySchedule() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let dayOne = calendar.date(from: DateComponents(year: 2026, month: 5, day: 22, hour: 9))!
        let dayTwo = dayOne.addingTimeInterval(86_400)
        let start = dayOne.addingTimeInterval(3_600)

        var snapshot = VocabularyDisplayScheduleSnapshot(dailyLimit: 3, windowHours: 6)
        precondition(VocabularyDisplayScheduler.canShowAutomaticVocabulary(snapshot, now: dayOne, calendar: calendar))

        snapshot = VocabularyDisplayScheduler.recordAutomaticVocabularyShown(snapshot, now: start, calendar: calendar)
        precondition(snapshot.windowStartDate == start)
        precondition(snapshot.shownCount == 1)
        precondition(VocabularyDisplayScheduler.canShowAutomaticVocabulary(snapshot, now: start.addingTimeInterval(60), calendar: calendar))

        snapshot = VocabularyDisplayScheduler.recordAutomaticVocabularyShown(snapshot, now: start.addingTimeInterval(120), calendar: calendar)
        snapshot = VocabularyDisplayScheduler.recordAutomaticVocabularyShown(snapshot, now: start.addingTimeInterval(240), calendar: calendar)
        precondition(snapshot.shownCount == 3)
        precondition(!VocabularyDisplayScheduler.canShowAutomaticVocabulary(snapshot, now: start.addingTimeInterval(300), calendar: calendar))

        var expired = VocabularyDisplayScheduleSnapshot(dailyLimit: 10, windowHours: 6, windowStartDate: start, shownCountDate: VocabularyDisplayScheduler.todayKey(for: start, calendar: calendar), shownCount: 1)
        precondition(!VocabularyDisplayScheduler.canShowAutomaticVocabulary(expired, now: start.addingTimeInterval(6 * 3600 + 1), calendar: calendar))

        expired = VocabularyDisplayScheduler.resetIfNeeded(expired, now: dayTwo, calendar: calendar)
        precondition(expired.shownCount == 0)
        precondition(expired.windowStartDate == nil)
        precondition(VocabularyDisplayScheduler.normalizedDailyLimit(100) == 50)
        precondition(VocabularyDisplayScheduler.normalizedDailyLimit(0) == 1)
    }

    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        if !condition() {
            throw SelfTestError(message)
        }
    }

    static func createZip(at zipURL: URL, from directory: URL, workingDirectory: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        process.currentDirectoryURL = workingDirectory
        process.arguments = ["-qr", zipURL.path, directory.lastPathComponent]
        try process.run()
        process.waitUntilExit()
        try expect(process.terminationStatus == 0, "zip command succeeded")
    }
}

struct SelfTestError: LocalizedError {
    var message: String

    init(_ message: String) {
        self.message = message
    }

    var errorDescription: String? {
        message
    }
}
