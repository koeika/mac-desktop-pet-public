import AppKit
import CodexPetCore

enum CompanionVisualRegression {
    @MainActor static func run() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try AppDataStore(root: root)
        let original = try JSONFileStore.encoder.encode(store.dictionaries)
        let learning = try JSONFileStore.encoder.encode(store.vocabularyProgress)
        let pet = store.pets.first { $0.id == "cling-color" }!
        for theme in AppVisualTheme.allCases {
            for size in [NSSize(width: 460, height: 700), NSSize(width: 420, height: 500)] {
                let view = PetContentView(frame: NSRect(origin: .zero, size: size))
                let window = NSWindow(contentRect: view.frame, styleMask: [.borderless], backing: .buffered, defer: false)
                window.contentView = view
                defer { window.contentView = nil }
                view.setPetRenderer(store.spriteRenderer(for: pet), fallbackImage: store.previewImage(for: pet))
                view.applyTheme(theme)
                view.showMessage(kicker: "", title: "喵，陪你一会儿", body: "", showActions: false,
                    presentation: .compact, animated: false)
                let small = view.visualLayoutSnapshot
                precondition(small.pet.size == NSSize(width: 128, height: 128))
                precondition(small.titleFont == 15 && small.message.width <= 272 && small.message.height < 90)
                precondition(small.message.midX == small.pet.midX)
                precondition(small.message.minY + 8 - small.pet.maxY == 12, "visible feedback surface stays close to the pet")
                try capture(view, name: "feedback-\(theme.rawValue)-\(Int(size.height))")
                view.showMessage(kicker: "", title: String(repeating: "今天也一起慢慢学习吧", count: 5), body: "", showActions: false,
                    presentation: .compact, animated: false)
                precondition(view.visualLayoutSnapshot.message.width <= 272 && view.visualLayoutSnapshot.message.height <= 80)
                view.showProgressEvent(ProgressEvent(source: "codex", stage: "验证视觉与交互", message: "保留词库和学习记录", progress: 75, threadId: "visual"))
                view.showProgressEvent(ProgressEvent(source: "codex", stage: "完成词卡布局", message: "双主题、双语例句", progress: 100, status: .done, threadId: "words"))
                view.showProgressEvent(ProgressEvent(source: "codex", stage: "检查宠物动作", message: "原生精灵动画 6.25 fps", progress: 90, threadId: "pet"))
                let stacked = view.visualLayoutSnapshot
                precondition(stacked.progress.height == 216 && stacked.progress.width == 352)
                precondition(view.bounds.contains(stacked.progress) && stacked.progress.midX == stacked.pet.midX)
                precondition(view.isBubbleVisible && view.progressPriorityDeadline != nil)
                try capture(view, name: "notifications-\(theme.rawValue)-\(Int(size.height))")
                view.hideBubble(animated: false)
                precondition(!view.isBubbleVisible && view.progressPriorityDeadline == nil)
                view.showVocabularyCard(kicker: "我的生词", entry: sampleEntry, revealed: true, footer: "今日 1 / 10",
                    known: "2 天", unknown: "10 分钟", hard: "15 分钟")
                let card = view.bubbleLayoutSnapshot
                precondition(card.bubble.width == 384 && card.bubble.midX == view.visualLayoutSnapshot.pet.midX)
                precondition(view.vocabularyTypographySnapshot.text.string.contains("这个房间可以容纳 30 人。"))
                try capture(view, name: "vocabulary-\(theme.rawValue)-\(Int(size.height))")
                view.showVocabularyCard(kicker: "我的生词", entry: sampleEntry, revealed: false, footer: "今日 1 / 10",
                    known: "2 天", unknown: "10 分钟", hard: "15 分钟")
                precondition(view.bubbleLayoutSnapshot.bubble.height <= 250)
                try capture(view, name: "recall-compact-\(theme.rawValue)-\(Int(size.height))")
            }
        }
        let after = try JSONFileStore.encoder.encode(store.dictionaries)
        let learningAfter = try JSONFileStore.encoder.encode(store.vocabularyProgress)
        precondition(original == after && learning == learningAfter, "visual operations cannot alter dictionaries or learning records")
        if let directory = ProcessInfo.processInfo.environment["WHISKYCLING_VISUAL_FIXTURE_DIR"] {
            let fixtureRoot = URL(fileURLWithPath: directory)
            guard !FileManager.default.fileExists(atPath: fixtureRoot.path) else { throw CocoaError(.fileWriteFileExists) }
            let fixture = try AppDataStore(root: fixtureRoot)
            let pack = DictionaryPack(id: "visual-fixture", name: "我的生词", entries: [sampleEntry])
            try JSONFileStore.save(pack, to: fixture.dictionariesURL.appendingPathComponent("visual-fixture.json"))
            fixture.settings.enabledDictionaryIDs = [pack.id]
            fixture.settings.vocabularyRecallMode = true
            fixture.settings.walkingPaused = true
            fixture.settings.serverPort = 4794
            fixture.settings.vocabularyStudyStartMinute = 0
            fixture.settings.vocabularyStudyEndMinute = 1
            fixture.settings.visualTheme = .comic
            fixture.saveSettings()
        }
        print("companion-visual-regression: compact feedback, 128pt pet, 12pt surface gap, bounded notifications, 384pt dictionary layout, two themes and immutable learning data passed")
    }

    private static var sampleEntry: DictionaryEntry {
        DictionaryEntry(term: "accommodate", phonetic: "US /əˈkɑːmədeɪt/ · UK /əˈkɒmədeɪt/",
            meaning: "v. 提供空间或设施以适应某事物；包含；容纳\nv. 适应；调整",
            example: "The room can accommodate 30 people.", exampleTranslation: "这个房间可以容纳 30 人。",
            hint: "在提供空间的语境中，accommodate 表示为人或事物提供足够的空间。")
    }

    @MainActor private static func capture(_ view: NSView, name: String) throws {
        guard let directory = ProcessInfo.processInfo.environment["WHISKYCLING_REGRESSION_ARTIFACT_DIR"] else { return }
        view.layoutSubtreeIfNeeded()
        let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
        view.cacheDisplay(in: view.bounds, to: bitmap)
        try bitmap.representation(using: .png, properties: [:])!.write(to:
            URL(fileURLWithPath: directory).appendingPathComponent(name + ".png"))
    }
}
