import AppKit
import CodexPetCore
import SwiftUI

// The release binary can run this isolated check on Macs with Command Line Tools but no XCTest.
enum NotebookRegression {
    @MainActor static func runEnrichment() async throws {
        try await LibraryBrowserRegression.run()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try AppDataStore(root: root)
        let legacyPace = try JSONFileStore.decoder.decode(AppSettings.self, from: Data("{\"dailyVocabularyLimit\":50,\"dailyNewVocabularyLimit\":20}".utf8))
        precondition(!legacyPace.dailyVocabularyUnlimited && !legacyPace.dailyNewVocabularyUnlimited)
        precondition(legacyPace.dailyVocabularyLimit == 50 && legacyPace.dailyNewVocabularyLimit == 20)
        store.settings.dailyVocabularyLimit = 500
        store.settings.dailyNewVocabularyLimit = 100
        store.settings.dailyVocabularyUnlimited = true
        store.settings.dailyNewVocabularyUnlimited = true
        store.settings.vocabularyMinimumIntervalMinutes = 7
        store.settings.lastAutomaticVocabularyDate = Date(timeIntervalSince1970: 1_800_000_000)
        store.saveSettings()
        let pace = try AppDataStore(root: root)
        precondition(pace.settings.dailyVocabularyLimit == 500 && pace.settings.dailyNewVocabularyLimit == 100)
        precondition(pace.settings.dailyVocabularyUnlimited && pace.settings.dailyNewVocabularyUnlimited)
        precondition(pace.settings.vocabularyMinimumIntervalMinutes == 7 && pace.settings.lastAutomaticVocabularyDate == store.settings.lastAutomaticVocabularyDate)
        store.settings = AppSettings()
        store.saveSettings()
        store.settings.deepSeekModel = "deepseek-chat"
        store.saveSettings()
        let migrated = try AppDataStore(root: root)
        precondition(migrated.settings.deepSeekModel == "deepseek-flash")
        let persisted = try JSONFileStore.decoder.decode(AppSettings.self, from: Data(contentsOf: migrated.settingsURL))
        precondition(persisted.deepSeekModel == "deepseek-flash")
        precondition(DeepSeekConfiguration.resolvedModel("deepseek-chat", baseURL: "https://proxy.example") == "deepseek-chat")
        precondition(DeepSeekConfiguration.resolvedModel("custom-model", baseURL: "https://api.deepseek.com") == "custom-model")
        for (code, text) in [(401, "鉴权"), (402, "余额"), (404, "模型"), (429, "频繁"), (503, "暂时不可用")] {
            let message = DeepSeekServiceError.httpStatus(code).localizedDescription
            precondition(message.contains(String(code)) && message.contains(text))
        }
        let request = try JSONSerialization.data(withJSONObject: ["word": ["term": "coherent", "language": "en", "example": "A coherent explanation helps."], "allowAI": true])
        let countBefore = migrated.personalVocabulary.words.count
        var attempts = 0
        let failed = try await migrated.lookupVocabulary(request, enrichment: { _, _ in
            attempts += 1
            throw DeepSeekServiceError.httpStatus(402)
        })
        let fallback = try JSONSerialization.jsonObject(with: failed) as! [String: Any]
        precondition(fallback["ok"] as? Bool == true && fallback["source"] as? String == "dictionary")
        precondition((fallback["warning"] as? String)?.contains("HTTP 402") == true)
        let local = fallback["word"] as! [String: Any]
        precondition(!(local["meaning"] as! String).isEmpty && local["example"] as? String == "A coherent explanation helps.")
        precondition(attempts == 1 && migrated.personalVocabulary.words.count == countBefore)
        let successful = try await migrated.lookupVocabulary(request, enrichment: { word, context in
            var value = word
            precondition(context == "A coherent explanation helps.")
            value.phoneticUS = "/koʊˈhɪrənt/"
            value.phoneticUK = "/kəʊˈhɪərənt/"
            value.exampleTranslation = "连贯的解释很有帮助。"
            return value
        })
        let enriched = try JSONSerialization.jsonObject(with: successful) as! [String: Any]
        precondition(enriched["source"] as? String == "deepseek" && enriched["warning"] == nil)
        let fields = enriched["word"] as! [String: Any]
        precondition(fields["phoneticUS"] != nil && fields["exampleTranslation"] != nil)
        let noAI = try JSONSerialization.data(withJSONObject: ["word": ["term": "coherent"], "allowAI": false])
        _ = try await migrated.lookupVocabulary(noAI, enrichment: { _, _ in preconditionFailure("AI must be opt-in") })
        let unknown = try JSONSerialization.data(withJSONObject: ["word": ["term": "unlisted-fixture-token"], "allowAI": true])
        let missing = try await migrated.lookupVocabulary(unknown, enrichment: { _, _ in throw DeepSeekServiceError.httpStatus(401) })
        let unknownResult = try JSONSerialization.jsonObject(with: missing) as! [String: Any]
        precondition(unknownResult["ok"] as? Bool == true && (unknownResult["warning"] as? String)?.contains("HTTP 401") == true)
        precondition(migrated.personalVocabulary.words.count == countBefore)
        print("enrichment-regression: model migration, custom endpoint preservation, HTTP diagnostics, local fallback, opt-in and successful bilingual enrichment passed (fixture transport; no live key)")
    }

    @MainActor static func run() async throws {
        try await LearningPlanRegression.run()
        precondition(AppBrand.displayName == "PetPetKnows")
        try SettingsRedesignRegression.run()
        try await PetVisibilityRegression.run()
        try VocabularyCardRegression.run()
        try CompanionProgressRegression.run()
        try CompanionVisualRegression.run()
        try CompanionConfigurationRegression.run()
        try CompanionReadabilityRegression.run()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try AppDataStore(root: root)
        precondition(store.settings.visualTheme == .comic)
        let oldSettings = try JSONFileStore.decoder.decode(AppSettings.self, from: Data("{}".utf8))
        precondition(oldSettings.visualTheme == .comic, "Old settings must keep the existing theme")
        let unknownTheme = try JSONFileStore.decoder.decode(AppSettings.self, from: Data("{\"visualTheme\":\"future-theme\",\"movementSpeedMultiplier\":0.7}".utf8))
        precondition(unknownTheme.visualTheme == .comic && unknownTheme.movementSpeedMultiplier == 0.7)
        let originalPets = store.pets
        let originalDictionaries = store.dictionaries
        let originalProgress = store.vocabularyProgress
        let originalNotebook = try JSONFileStore.encoder.encode(store.personalVocabulary)
        let originalToken = store.captureToken
        let originalSettings = try JSONFileStore.encoder.encode(store.settings)
        var themeEvents = 0
        let themeObserver = NotificationCenter.default.addObserver(forName: .companionThemeDidChange, object: store, queue: nil) { _ in themeEvents += 1 }
        defer { NotificationCenter.default.removeObserver(themeObserver) }
        try store.selectVisualTheme(.storybook)
        precondition(themeEvents == 1)
        let themedRestart = try AppDataStore(root: root)
        precondition(themedRestart.settings.visualTheme == .storybook, "Theme selection must survive restart")
        try store.selectVisualTheme(.storybook)
        precondition(themeEvents == 1, "Selecting the same theme must not emit duplicate updates")
        try store.selectVisualTheme(.comic)
        precondition(themeEvents == 2)
        let revertedSettings = try JSONFileStore.encoder.encode(store.settings)
        precondition(revertedSettings == originalSettings)
        precondition(store.pets == originalPets && store.dictionaries == originalDictionaries && store.vocabularyProgress == originalProgress)
        let revertedNotebook = try JSONFileStore.encoder.encode(store.personalVocabulary)
        precondition(revertedNotebook == originalNotebook)
        precondition(store.captureToken == originalToken)
        let failureStore = try AppDataStore(root: root.appendingPathComponent("theme-save-failure"))
        if FileManager.default.fileExists(atPath: failureStore.settingsURL.path) { try FileManager.default.removeItem(at: failureStore.settingsURL) }
        try FileManager.default.createDirectory(at: failureStore.settingsURL, withIntermediateDirectories: false)
        var didFail = false
        do { try failureStore.selectVisualTheme(.storybook) } catch { didFail = true }
        precondition(didFail && failureStore.settings.visualTheme == .comic, "A failed save must not change the effective theme")
        precondition(AppResourceLocator.file(named: "Themes/storybook-duo", extension: "png") != nil)
        precondition(Set(store.pets.map(\.id)) == Set(AppDataStore.companionIDs))
        precondition(store.enabledPets().count == 2)
        for pet in store.pets {
            let renderer = store.spriteRenderer(for: pet)!
            for action in CodexPetAction.allCases {
                precondition(renderer.frame(for: action, frameIndex: 0) != nil)
                precondition(renderer.frame(for: action, frameIndex: pet.actionFrameCount - 1) != nil)
            }
            let first = renderer.frame(for: .runningRight, frameIndex: 0)!.tiffRepresentation!
            let next = renderer.frame(for: .runningRight, frameIndex: 1)!.tiffRepresentation!
            precondition(first != next, "Walking must contain distinct animation frames")
        }
        try store.selectCompanionStyle(ink: false)
        precondition(Set(store.enabledPets().map(\.id)) == ["whisky", "cling"])
        let original = store.pets.first { $0.id == "whisky" }!
        store.setPetWeight(original, weight: 3.5)
        let afterRestart = try AppDataStore(root: root)
        precondition(afterRestart.pets.count == 6 && afterRestart.pets.first { $0.id == "whisky" }!.weight == 3.5)
        afterRestart.deletePet(afterRestart.pets.first { $0.id == "cling-ink" }!)
        let afterDelete = try AppDataStore(root: root)
        precondition(afterDelete.pets.count == 5, "Deleted bundled pets must stay deleted")
        try afterDelete.selectCompanionStyle(ink: true)
        precondition(afterDelete.pets.count == 6 && afterDelete.enabledPets().count == 2)
        let aliasRoot = root.appendingPathComponent("alias-migration")
        let aliasStore = try AppDataStore(root: aliasRoot)
        let whiskyIndex = aliasStore.pets.firstIndex { $0.id == "whisky" }!
        aliasStore.pets[whiskyIndex].id = "whisky-2"
        aliasStore.pets[whiskyIndex].isEnabled = false
        aliasStore.pets[whiskyIndex].weight = 4.2
        aliasStore.savePets()
        let aliasRestored = try AppDataStore(root: aliasRoot)
        try aliasRestored.selectCompanionStyle(ink: false)
        precondition(aliasRestored.pets.count == 6)
        precondition(aliasRestored.enabledPets().contains { $0.id == "whisky-2" && $0.weight == 4.2 })
        try aliasRestored.selectCompanionStyle(ink: true)
        precondition(!aliasRestored.enabledPets().contains { $0.id == "whisky-2" })
        var contextBook = PersonalVocabulary()
        var firstContext = CapturePayload(term: "context", meaning: "语境")
        firstContext.example = "First sentence."
        firstContext.exampleTranslation = "第一句。"
        try contextBook.capture(firstContext)
        firstContext.example = "Second sentence."
        firstContext.exampleTranslation = nil
        let refreshedContext = try contextBook.capture(firstContext)
        precondition(refreshedContext.content.exampleTranslation == nil, "A new sentence must never reuse the old sentence's translation")
        precondition(refreshedContext.contexts[0].translation == "第一句。")
        try aliasRestored.selectCompanionStyle(.color)
        precondition(aliasRestored.enabledPets().allSatisfy { $0.id.hasSuffix("-color") })
        let word = try store.captureWord(CapturePayload(term: "inherently", meaning: "adv. 本质上"))
        let scoped = ScopedDictionaryEntry(dictionaryID: word.dictionaryID, dictionaryName: "我的生词本", entry: word.entry)
        let now = Date(timeIntervalSince1970: floor(Date().timeIntervalSince1970))
        store.recordVocabularyPresentation(scoped, automatic: false, now: now)
        try store.reviewWord(scoped, action: .known, now: now)
        var duplicate = CapturePayload(term: "inherently")
        duplicate.example = "The system is inherently flawed."
        try store.captureWord(duplicate)
        let restored = try AppDataStore(root: root)
        precondition(restored.personalVocabulary.words.count == 1)
        precondition(restored.personalVocabulary.words[0].contexts.count == 2)
        precondition(restored.personalVocabulary.words[0].content.meaning == "adv. 本质上")
        var edited = restored.personalVocabulary.words[0].content
        edited.example = nil
        try restored.updateCapturedWord(id: word.id, payload: edited)
        let editedStore = try AppDataStore(root: root)
        precondition(editedStore.personalVocabulary.words[0].content.example == nil)
        precondition(restored.vocabularyProgress.stats[word.statKey]?.review == store.vocabularyProgress.stats[word.statKey]?.review)
        let previous = restored.vocabularyProgress.stats[word.statKey]!.review
        try restored.reviewWord(scoped, action: .skipped, now: now)
        precondition(restored.vocabularyProgress.stats[word.statKey]?.review == previous)
        let view = PetContentView(frame: NSRect(x: 0, y: 0, width: 420, height: 500))
        let inkPet = afterDelete.pets.first { $0.id == "whisky-ink" }!
        view.setPetRenderer(afterDelete.spriteRenderer(for: inkPet), fallbackImage: afterDelete.previewImage(for: inkPet))
        let window = NSWindow(contentRect: view.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = view
        defer { withExtendedLifetime(window) {} }
        let spy = NotebookFeedbackSpy()
        view.delegate = spy
        view.layoutSubtreeIfNeeded()
        func mouse(_ type: NSEvent.EventType, at point: NSPoint, modifiers: NSEvent.ModifierFlags = []) -> NSEvent {
            NSEvent.mouseEvent(with: type, location: point, modifierFlags: modifiers, timestamp: 0,
                windowNumber: window.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1)!
        }
        let petPoint = NSPoint(x: 210, y: 89)
        let rightMenu = view.menu(for: mouse(.rightMouseDown, at: petPoint))!
        precondition(rightMenu.items.map(\.title) == ["单词", "配置中心…", "", "暂停走动"] && spy.requestedWords == 0, "Opening the menu must not request a word")
        rightMenu.performActionForItem(at: 1)
        precondition(spy.settingsRequests == 1 && spy.requestedWords == 0)
        rightMenu.performActionForItem(at: 3)
        precondition(spy.petWalkingPaused && view.menu(for: mouse(.rightMouseDown, at: petPoint))!.items[3].title == "继续走动")
        rightMenu.performActionForItem(at: 0)
        precondition(spy.requestedWords == 1 && spy.petClicks == 0, "Choosing the word menu item requests exactly once")
        let controlMenu = view.menu(for: mouse(.leftMouseDown, at: petPoint, modifiers: .control))!
        precondition(spy.requestedWords == 1, "Control-click offers the same menu, without automatic study")
        controlMenu.performActionForItem(at: 0)
        let beforeControlDrag = window.frame.origin
        view.mouseDragged(with: mouse(.leftMouseDragged, at: NSPoint(x: petPoint.x + 12, y: petPoint.y), modifiers: .control))
        view.mouseUp(with: mouse(.leftMouseUp, at: petPoint, modifiers: .control))
        precondition(spy.requestedWords == 2 && spy.petClicks == 0 && window.frame.origin == beforeControlDrag)
        view.mouseDown(with: mouse(.leftMouseDown, at: petPoint))
        view.mouseUp(with: mouse(.leftMouseUp, at: petPoint))
        precondition(spy.requestedWords == 2 && spy.petClicks == 1, "Ordinary left click keeps pet interaction")
        view.mouseDown(with: mouse(.leftMouseDown, at: petPoint))
        let beforeDrag = window.frame.origin
        view.mouseDragged(with: mouse(.leftMouseDragged, at: NSPoint(x: petPoint.x + 12, y: petPoint.y)))
        view.mouseUp(with: mouse(.leftMouseUp, at: petPoint))
        precondition(spy.requestedWords == 2 && spy.petClicks == 1, "Dragging must not request words or trigger click feedback")
        precondition(window.frame.origin != beforeDrag, "Left dragging must still move the pet window")
        precondition(view.menu(for: mouse(.rightMouseDown, at: NSPoint(x: 2, y: 2))) == nil)
        precondition(spy.requestedWords == 2, "Only pet bounds own the shortcut")
        view.showMessage(kicker: "我的生词本", title: "inherently", body: "/ɪnˈhɪərəntli/", showActions: true, footer: "今日 1/10", animated: false)
        view.configureVocabularyControls(revealed: false, known: "1天", unknown: "10分钟", hard: "15分钟")
        func buttons(_ parent: NSView) -> [NSButton] {
            parent.subviews.flatMap { ($0 as? NSButton).map { [$0] } ?? buttons($0) }
        }
        let controls = buttons(view)
        let reveal = controls.first { $0.title == "查看释义" }!
        let unknown = controls.first { $0.title == "不认识" }!
        precondition(unknown.isHidden && !reveal.isHidden)
        reveal.performClick(nil)
        precondition(spy.revealed == 1 && spy.unknown == 0)
        view.configureVocabularyControls(revealed: true, known: "1天", unknown: "10分钟", hard: "15分钟")
        view.showMessage(kicker: "我的生词本", title: "inherently",
            body: "UK /ɪnˈhɪərəntli/\n\n[释义]\nadv. 本质上；固有地\n\n[例句]\nThe system is inherently flawed.\n该系统本质上存在缺陷。", showActions: true, footer: "今日 1/10", animated: false)
        view.configureVocabularyControls(revealed: true, known: "1天", unknown: "10分钟", hard: "15分钟")
        view.layoutSubtreeIfNeeded()
        if let directory = ProcessInfo.processInfo.environment["WHISKYCLING_REGRESSION_ARTIFACT_DIR"],
           let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
            view.cacheDisplay(in: view.bounds, to: bitmap)
            let output = URL(fileURLWithPath: directory).appendingPathComponent("recall-bubble.png")
            try bitmap.representation(using: .png, properties: [:])?.write(to: output)
            let actions = SettingsActions(uploadPhotos: {}, importPetPackage: {}, randomPreview: {},
                importDictionary: {}, openCSVTemplate: {}, openJSONTemplate: {}, showImportFormat: {},
                sendTestProgress: {}, chooseSyncFolder: {}, watchLogFile: {})
            for (tab, name) in [(SettingsTab.pets, "ink-pets"), (.dictionary, "ink-vocabulary"), (.progress, "ink-progress")] {
                let hosting = NSHostingView(rootView: SettingsCenterView(store: afterDelete, actions: actions, initialTab: tab))
                hosting.frame = NSRect(x: 0, y: 0, width: 1120, height: 800)
                let previewWindow = NSWindow(contentRect: hosting.frame, styleMask: [.borderless], backing: .buffered, defer: false)
                previewWindow.contentView = hosting
                hosting.layoutSubtreeIfNeeded()
                hosting.displayIfNeeded()
                guard let image = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else { preconditionFailure("Settings screenshot failed") }
                hosting.cacheDisplay(in: hosting.bounds, to: image)
                try image.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: directory).appendingPathComponent("\(name).png"))
            }
        }
        precondition(!unknown.isHidden && reveal.isHidden)
        unknown.performClick(nil)
        precondition(spy.unknown == 1)
        let answer = "读音：これ\n这个\nこれは なんですか。\n这是什么？"
        view.showVocabularyCard(kicker: "日语", title: "これ", prompt: "读音：これ", answer: answer,
            revealed: false, footer: "今日 1/10", known: "1天", unknown: "10分钟", hard: "15分钟")
        let before = view.bubbleLayoutSnapshot
        if let directory = ProcessInfo.processInfo.environment["WHISKYCLING_REGRESSION_ARTIFACT_DIR"],
           let image = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
            view.cacheDisplay(in: view.bounds, to: image)
            try image.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: directory).appendingPathComponent("learning-question.png"))
        }
        precondition(before.controls.count == 2)
        precondition(abs((before.controls[0].midX + before.controls[1].midX) / 2 - before.bubble.width / 2) < 0.5)
        precondition(reveal.acceptsFirstMouse(for: nil))
        window.displayIfNeeded()
        view.showVocabularyCard(kicker: "日语", title: "これ", prompt: "读音：これ", answer: answer,
            revealed: true, footer: "今日 1/10", known: "1天", unknown: "10分钟", hard: "15分钟")
        precondition(before.bubble.minY == view.bubbleLayoutSnapshot.bubble.minY && before.bubble.width == view.bubbleLayoutSnapshot.bubble.width)
        precondition(view.bubbleLayoutSnapshot.bubble.height >= before.bubble.height, "Revealing may expand the single existing card")
        precondition(view.bubbleLayoutSnapshot.controls.allSatisfy { $0.minX >= 24 && $0.maxX <= before.bubble.width - 24 && $0.minY >= 36 })
        let comicLayout = view.bubbleLayoutSnapshot
        view.applyTheme(.storybook)
        precondition(view.visualTheme == .storybook && view.isBubbleVisible)
        precondition(view.bubbleLayoutSnapshot.bubble == comicLayout.bubble && view.bubbleLayoutSnapshot.controls == comicLayout.controls,
                     "Theme switching must not resize or move the active vocabulary card")
        precondition(knownButtonColor(view) == AppVisualTheme.storybook.accentNSColor.cgColor)
        unknown.performClick(nil)
        precondition(spy.unknown == 2, "Review controls must still work after switching themes")
        view.applyTheme(.comic)
        precondition(view.visualTheme == .comic && view.bubbleLayoutSnapshot.bubble == comicLayout.bubble)
        if let directory = ProcessInfo.processInfo.environment["WHISKYCLING_REGRESSION_ARTIFACT_DIR"] {
            let actions = SettingsActions(uploadPhotos: {}, importPetPackage: {}, randomPreview: {}, importDictionary: {}, openCSVTemplate: {}, openJSONTemplate: {}, showImportFormat: {}, sendTestProgress: {}, chooseSyncFolder: {}, watchLogFile: {})
            for theme in AppVisualTheme.allCases {
                try afterDelete.selectVisualTheme(theme)
                for (tab, name) in [(SettingsTab.pets, "pets"), (.dictionary, "dictionary"), (.progress, "progress")] {
                    let hosting = NSHostingView(rootView: SettingsCenterView(store: afterDelete, actions: actions, initialTab: tab))
                    hosting.frame = NSRect(x: 0, y: 0, width: 1120, height: 800)
                    let preview = NSWindow(contentRect: hosting.frame, styleMask: [.borderless], backing: .buffered, defer: false)
                    preview.contentView = hosting
                    hosting.layoutSubtreeIfNeeded()
                    hosting.displayIfNeeded()
                    let bitmap = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds)!
                    hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
                    try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: directory).appendingPathComponent("theme-\(theme.rawValue)-\(name).png"))
                    withExtendedLifetime(preview) {}
                }
                let fixture = PetContentView(frame: view.frame)
                fixture.applyTheme(theme)
                fixture.setPetRenderer(afterDelete.spriteRenderer(for: inkPet), fallbackImage: afterDelete.previewImage(for: inkPet))
                fixture.showVocabularyCard(kicker: "日语", title: "これ", prompt: "读音：これ", answer: answer,
                    revealed: true, footer: "今日 1/10", known: "1天", unknown: "10分钟", hard: "15分钟")
                fixture.layoutSubtreeIfNeeded()
                let bitmap = fixture.bitmapImageRepForCachingDisplay(in: fixture.bounds)!
                fixture.cacheDisplay(in: fixture.bounds, to: bitmap)
                try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: directory).appendingPathComponent("theme-\(theme.rawValue)-bubble.png"))
            }
        }
        if let directory = ProcessInfo.processInfo.environment["WHISKYCLING_REGRESSION_ARTIFACT_DIR"],
           let image = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
            let fixture = PetContentView(frame: view.frame)
            fixture.setPetRenderer(afterDelete.spriteRenderer(for: inkPet), fallbackImage: afterDelete.previewImage(for: inkPet))
            fixture.showVocabularyCard(kicker: "日语", title: "これ", prompt: "读音：これ", answer: answer,
                revealed: true, footer: "今日 1/10", known: "1天", unknown: "10分钟", hard: "15分钟")
            fixture.layoutSubtreeIfNeeded()
            fixture.cacheDisplay(in: fixture.bounds, to: image)
            try image.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: directory).appendingPathComponent("learning-answer.png"))
        }
        view.hideBubble(animated: false)
        precondition(!view.isBubbleVisible)
        if let directory = ProcessInfo.processInfo.environment["WHISKYCLING_PET_CLICK_FIXTURE_DIR"] {
            let fixtureRoot = URL(fileURLWithPath: directory)
            guard !FileManager.default.fileExists(atPath: fixtureRoot.path) else { throw CocoaError(.fileWriteFileExists) }
            let fixture = try AppDataStore(root: fixtureRoot)
            let pack = DictionaryPack(id: "pet-click-fixture", name: "交互验收", entries: [
                DictionaryEntry(term: "accommodate", phonetic: "/əˈkɒmədeɪt/", meaning: "v. 容纳；适应",
                    example: "The room can accommodate ten people.", exampleTranslation: "这个房间可以容纳十个人。"),
                DictionaryEntry(term: "coherent", phonetic: "/koʊˈhɪrənt/", meaning: "adj. 连贯的；一致的",
                    example: "A coherent plan helps.", exampleTranslation: "连贯的计划很有帮助。")
            ])
            try JSONFileStore.save(pack, to: fixture.dictionariesURL.appendingPathComponent("pet-click-fixture.json"))
            fixture.settings.enabledDictionaryIDs = [pack.id]
            fixture.settings.walkingPaused = true
            fixture.settings.serverPort = 4793
            fixture.settings.dailyVocabularyLimit = 1
            fixture.settings.dailyNewVocabularyLimit = 0
            fixture.settings.vocabularyShownCountDate = VocabularyDisplayScheduler.todayKey(for: Date())
            fixture.settings.vocabularyShownCount = 1
            fixture.settings.vocabularyStudyStartMinute = 0
            fixture.settings.vocabularyStudyEndMinute = 1
            fixture.saveSettings()
        }
        print("pet-click-regression: right/Control-click offer a word menu without automatic study, selection requests once, left-click and drag preserved, outside-pet menu rejected")
        print("notebook-regression: theme migration, persistence, failed-save rollback, data isolation, stable native theme switching, bundled pets, nine actions, FSRS and native recall passed")
    }

    private static func knownButtonColor(_ view: NSView) -> CGColor? {
        if let button = view as? NSButton, button.title == "认识啦" { return button.layer?.backgroundColor }
        return view.subviews.compactMap { knownButtonColor($0) }.first
    }
}

private final class NotebookFeedbackSpy: PetContentViewDelegate {
    var revealed = 0
    var unknown = 0
    var requestedWords = 0
    var petClicks = 0
    var settingsRequests = 0
    var petWalkingPaused = false
    func markKnown() {}
    func markUnknown() { unknown += 1 }
    func markHard() {}
    func revealVocabularyAnswer() { revealed += 1 }
    func skipWord() {}
    func requestVocabularyNow() { requestedWords += 1 }
    func openSettings() { settingsRequests += 1 }
    func togglePetWalking() { petWalkingPaused.toggle() }
    func petClicked() { petClicks += 1 }
}
