import AppKit
import Combine
import CodexPetCore

enum CompanionReadabilityRegression {
    @MainActor static func run() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try AppDataStore(root: root)
        precondition(store.isUsingAlternateDataDirectory)
        let sample = BuiltInDictionaries.packs[0]
        precondition(!store.settings.enabledDictionaryIDs.contains(sample.id))
        store.toggleDictionary(sample.id, isEnabled: true)
        let key = WordStat.key(dictionaryID: sample.id, term: sample.entries[0].term)
        store.vocabularyProgress.stats[key] = WordStat(learned: true, seenCount: 5, lastAction: .known)
        try JSONFileStore.save(store.vocabularyProgress, to: store.progressURL)
        let learningBefore = try Data(contentsOf: store.progressURL)
        let notebookBefore = try JSONFileStore.encoder.encode(store.personalVocabulary)
        _ = try store.deleteDictionary(sample.id)
        let reloaded = try AppDataStore(root: root)
        precondition(!reloaded.dictionaries.contains { $0.id == sample.id })
        precondition(!reloaded.settings.enabledDictionaryIDs.contains(sample.id))
        let learningAfter = try Data(contentsOf: reloaded.progressURL)
        precondition(learningAfter == learningBefore)
        try reloaded.restoreSampleDictionaries()
        let restored = try AppDataStore(root: root)
        precondition(restored.dictionaries.contains { $0.id == sample.id })
        precondition(!restored.settings.enabledDictionaryIDs.contains(sample.id))
        precondition(restored.vocabularyProgress.stats[key]?.learned == true)
        let collision = DictionaryPack(id: sample.id, name: "自定义同 ID 词表", entries: [
            DictionaryEntry(term: sample.entries[0].term, meaning: "自定义释义")
        ])
        try JSONFileStore.save(collision, to: restored.dictionariesURL.appendingPathComponent("\(sample.id).json"))
        try restored.restoreSampleDictionaries()
        let deduplicated = try AppDataStore(root: root)
        precondition(deduplicated.dictionaries.filter { $0.id == sample.id }.count == 1)
        precondition(deduplicated.dictionaries.first { $0.id == sample.id }?.entries[0].meaning == "自定义释义")
        let notebookAfter = try JSONFileStore.encoder.encode(restored.personalVocabulary)
        precondition(notebookBefore == notebookAfter)
        store.setMovementSpeedMultiplier(0.05)
        precondition(store.settings.movementSpeedMultiplier == 0.05)
        var notifications = 0
        let observer = store.objectWillChange.sink { notifications += 1 }
        store.setWalkingPaused(true)
        store.setWalkingPaused(false)
        precondition(notifications == 2, "Every pause state transition must invalidate configuration UI")
        withExtendedLifetime(observer) {}
        let paused = PetAnimationRenderer.desktopFrameIndex(action: .idle, sequenceIndex: 14, frameCount: 6)
        precondition(paused == 0)
        precondition(PetAnimationRenderer.desktopFrameIndex(action: .runningRight, sequenceIndex: 14, frameCount: 8) == 6)
        for theme in AppVisualTheme.allCases {
            let view = PetContentView(frame: NSRect(x: 0, y: 0, width: 460, height: 700))
            let window = NSWindow(contentRect: view.frame, styleMask: [.borderless], backing: .buffered, defer: false)
            window.contentView = view
            defer { window.contentView = nil }
            view.applyTheme(theme)
            let word = DictionaryEntry(term: "accommodate", phonetic: "US /əˈkɑːmədeɪt/ · UK /əˈkɒmədeɪt/", meaning: "v. 容纳；适应",
                example: "The room can accommodate 30 people.", exampleTranslation: "这个房间可以容纳 30 人。", hint: "在空间的语境中，表示提供足够的位置。")
            view.showVocabularyCard(kicker: "语境点击回归", entry: word, revealed: true, footer: "今日 1 / 10", known: "2 天", unknown: "10 分钟", hard: "15 分钟")
            view.layoutSubtreeIfNeeded()
            func textViews(_ parent: NSView) -> [NSTextView] {
                parent.subviews.flatMap { child in (child as? NSTextView).map { [$0] } ?? textViews(child) }
            }
            let context = textViews(view).first { $0.string.hasPrefix("语境说明") }!
            precondition(!context.isEditable && context.isRichText && context.isSelectable)
            let before = view.vocabularyTypographySnapshot
            let textBefore = NSAttributedString(attributedString: before.text)
            let contextBefore = NSAttributedString(attributedString: before.contextText)
            let frameBefore = view.bubbleLayoutSnapshot.bubble
            let origin = window.frame.origin
            let pet = view.visualLayoutSnapshot.pet
            let petEvent = NSEvent.mouseEvent(with: .leftMouseDown, location: NSPoint(x: pet.midX, y: pet.midY), modifierFlags: [], timestamp: 0,
                windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
            view.mouseDown(with: petEvent)
            view.mouseUp(with: petEvent)
            _ = window.makeFirstResponder(context)
            context.setSelectedRange(NSRange(location: 0, length: 4))
            let point = context.convert(NSPoint(x: 20, y: 10), to: nil)
            let down = NSEvent.mouseEvent(with: .leftMouseDown, location: point, modifierFlags: [], timestamp: 0,
                windowNumber: window.windowNumber, context: nil, eventNumber: 1, clickCount: 1, pressure: 1)!
            view.mouseDown(with: down)
            let dragged = NSEvent.mouseEvent(with: .leftMouseDragged, location: NSPoint(x: point.x + 15, y: point.y), modifierFlags: [], timestamp: 0,
                windowNumber: window.windowNumber, context: nil, eventNumber: 2, clickCount: 1, pressure: 1)!
            view.mouseDragged(with: dragged)
            view.mouseUp(with: down)
            view.layoutSubtreeIfNeeded()
            precondition(window.frame.origin == origin, "Bubble text interaction cannot drag the pet")
            precondition(view.bubbleLayoutSnapshot.bubble == frameBefore)
            precondition(view.vocabularyTypographySnapshot.text.isEqual(to: textBefore))
            precondition(view.vocabularyTypographySnapshot.contextText.isEqual(to: contextBefore))
        }
        print("readability-regression: removable/restorable disabled samples, unchanged history/notebook, 0.05x speed, idle frame rests, rich context selection and bubble-gesture isolation passed")
    }
}
