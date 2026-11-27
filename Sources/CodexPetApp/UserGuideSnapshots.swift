import AppKit
import SwiftUI
import CodexPetCore

enum UserGuideSnapshots {
    @MainActor static func run() async throws {
        NSApp.setActivationPolicy(.regular)
        guard let directory = ProcessInfo.processInfo.environment["WHISKYCLING_GUIDE_DIR"] else {
            throw CocoaError(.fileNoSuchFile)
        }
        let output = URL(fileURLWithPath: directory)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let retainedRoot = ProcessInfo.processInfo.environment["WHISKYCLING_GUIDE_FIXTURE_DIR"]
        let root = retainedRoot.map { URL(fileURLWithPath: $0) }
            ?? FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        guard !FileManager.default.fileExists(atPath: root.path) else { throw CocoaError(.fileWriteFileExists) }
        defer { if retainedRoot == nil { try? FileManager.default.removeItem(at: root) } }
        let store = try AppDataStore(root: root)
        for sample in BuiltInDictionaries.packs { _ = try store.deleteDictionary(sample.id) }
        let japanese = DictionaryPack(id: "guide-ja", name: "日语日常词", description: "分类：日语\n日常交流中的常用词与表达。", entries: [
            DictionaryEntry(term: "小さい", reading: "ちいさい", meaning: "[形] 小的", example: "小さい花が咲いています。", exampleTranslation: "小花正在盛开。"),
            DictionaryEntry(term: "静か", reading: "しずか", meaning: "[形动] 安静的"),
            DictionaryEntry(term: "便利", reading: "べんり", meaning: "[形动] 方便的")
        ])
        let work = DictionaryPack(id: "guide-work", name: "工作英语", description: "分类：英语\n在阅读与工作中积累的词汇。", entries: [
            DictionaryEntry(term: "allocate", phonetic: "/ˈæləkeɪt/", meaning: "v. 分配", example: "We allocate time to reading.", exampleTranslation: "我们分配时间来阅读。"),
            DictionaryEntry(term: "trace", phonetic: "/treɪs/", meaning: "v. 追踪；n. 痕迹")
        ])
        for pack in [japanese, work] {
            try JSONFileStore.save(pack, to: store.dictionariesURL.appendingPathComponent("\(pack.id).json"))
            store.dictionaries.append(pack)
        }
        var capture = CapturePayload(term: "accommodate", meaning: "v. 提供空间；容纳\nv. 适应；调整")
        capture.phoneticUS = "/əˈkɑːmədeɪt/"
        capture.phoneticUK = "/əˈkɒmədeɪt/"
        capture.example = "The room can accommodate 30 people."
        capture.exampleTranslation = "这个房间可以容纳 30 人。"
        capture.hint = "在提供空间的语境中，accommodate 表示为人或事物提供足够的位置。"
        capture.sourceURL = "https://example.org/reading"
        capture.sourceTitle = "阅读示例"
        for (term, meaning) in [("allocate", "v. 分配"), ("tranquil", "adj. 宁静的"), ("coherent", "adj. 连贯的"),
            ("structured", "adj. 有结构的"), ("observability", "n. 可观测性"), ("inherently", "adv. 本质上"),
            ("adapt", "v. 适应"), ("balance", "n. 平衡"), ("clarify", "v. 澄清"), ("discover", "v. 发现"),
            ("explore", "v. 探索"), ("focus", "n. 专注"), ("gather", "v. 收集"), ("habit", "n. 习惯"),
            ("improve", "v. 改进"), ("journey", "n. 旅程"), ("kindness", "n. 善意"), ("listen", "v. 倾听"),
            ("memory", "n. 记忆"), ("notice", "v. 注意到"), ("observe", "v. 观察"), ("practice", "n. 练习"),
            ("quiet", "adj. 安静的"), ("reflect", "v. 反思"), ("steady", "adj. 稳定的")] {
            _ = try store.captureWord(CapturePayload(term: term, meaning: meaning))
        }
        _ = try store.captureWord(capture)
        store.settings.enabledDictionaryIDs.formUnion([japanese.id, work.id])
        let studyTime = Date()
        for (pack, entry, action) in [(japanese, japanese.entries[0], WordAction.unknown), (work, work.entries[0], .known)] {
            try store.reviewWord(ScopedDictionaryEntry(dictionaryID: pack.id, dictionaryName: pack.name, entry: entry),
                action: action, now: studyTime.addingTimeInterval(-3600))
        }
        store.settings.walkingPaused = true
        store.settings.movementSpeedMultiplier = 0.1
        store.settings.serverPort = 4794
        store.saveSettings()
        try Data().write(to: root.appendingPathComponent("companion-welcome-seen"))
        try store.selectCompanionStyle(.color)
        let actions = SettingsActions(uploadPhotos: {}, importPetPackage: {}, randomPreview: {}, importDictionary: {},
            openCSVTemplate: {}, openJSONTemplate: {}, showImportFormat: {}, sendTestProgress: {}, chooseSyncFolder: {}, watchLogFile: {})
        for theme in AppVisualTheme.allCases {
            try store.selectVisualTheme(theme)
            try await captureView(SettingsCenterView(store: store, actions: actions),
                name: "guide-pets-\(theme.rawValue)", output: output)
        }
        try store.selectVisualTheme(.forest)
        try await captureView(SettingsCenterView(store: store, actions: actions, initialTab: .dictionary),
            name: "guide-notebook-forest", output: output)
        try await captureView(SettingsCenterView(store: store, actions: actions, initialTab: .appearance),
            name: "guide-themes-forest", output: output)
        if ProcessInfo.processInfo.environment["PETPETKNOWS_COMPACT_SNAPSHOTS"] == "1" {
            for tab in [SettingsTab.pets, .dictionary, .appearance] {
                try await captureView(SettingsCenterView(store: store, actions: actions, initialTab: tab),
                    name: "compact-forest-\(tab)", output: output, size: NSSize(width: 880, height: 620))
            }
        }
        try store.selectVisualTheme(.comic)
        for (page, name) in [("我的生词", "guide-notebook"), ("词典库", "guide-library"), ("学习计划", "guide-plan")] {
            try await captureView(SettingsCenterView(store: store, actions: actions, initialTab: .dictionary, initialLearningPage: page),
                name: name, output: output)
        }
        try await captureView(SettingsCenterView(store: store, actions: actions, initialTab: .progress), name: "guide-progress", output: output)
        try await captureView(SettingsCenterView(store: store, actions: actions, initialTab: .appearance), name: "guide-themes", output: output)
        if ProcessInfo.processInfo.environment["PETPETKNOWS_COMPACT_SNAPSHOTS"] == "1" {
            try await captureView(SettingsCenterView(store: store, actions: actions, initialTab: .plan),
                name: "compact-learning-plan", output: output, size: NSSize(width: 880, height: 620))
            try await captureView(SettingsCenterView(store: store, actions: actions, initialTab: .library),
                name: "compact-dictionary-library", output: output, size: NSSize(width: 880, height: 620))
            for tab in SettingsTab.allCases {
                try await captureView(SettingsCenterView(store: store, actions: actions, initialTab: tab),
                    name: "compact-\(tab)", output: output, size: NSSize(width: 880, height: 620))
            }
        }
        let word = DictionaryEntry(term: capture.term, phonetic: "US \(capture.phoneticUS!) · UK \(capture.phoneticUK!)",
            meaning: capture.meaning, example: capture.example, exampleTranslation: capture.exampleTranslation, hint: capture.hint)
        let pet = store.pets.first { $0.id == "whisky-color" }!
        for revealed in [false, true] {
            let view = PetContentView(frame: NSRect(x: 0, y: 0, width: 460, height: 700))
            let window = NSWindow(contentRect: view.frame, styleMask: [.borderless], backing: .buffered, defer: false)
            window.contentView = view
            defer { window.contentView = nil }
            view.setPetRenderer(store.spriteRenderer(for: pet), fallbackImage: store.previewImage(for: pet))
            view.showVocabularyCard(kicker: "我的生词本 · 英语", entry: word, revealed: revealed, footer: "今日 1 / 10",
                known: "2 天", unknown: "10 分钟", hard: "15 分钟")
            view.layoutSubtreeIfNeeded()
            let rect = NSRect(x: 24, y: 0, width: 412, height: view.bubbleLayoutSnapshot.bubble.maxY + 16)
            try save(view, rect: rect, to: output.appendingPathComponent(revealed ? "guide-answer.png" : "guide-recall.png"))
        }
        print("user-guide-snapshots: rendered configuration, theme gallery and word cards using generated data only")
    }

    @MainActor private static func captureView<V: View>(_ view: V, name: String, output: URL, size: NSSize = NSSize(width: 1120, height: 800)) async throws {
        let hosting = NSHostingView(rootView: view)
        hosting.frame = NSRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: hosting.frame, styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.contentView = hosting
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        defer { window.orderOut(nil); window.contentView = nil }
        // Allow the same asynchronous search/index tasks as the real configuration window to settle.
        try await Task.sleep(for: .seconds(1))
        hosting.layoutSubtreeIfNeeded()
        hosting.displayIfNeeded()
        try save(hosting, rect: hosting.bounds, to: output.appendingPathComponent(name + ".png"))
    }

    @MainActor private static func save(_ view: NSView, rect: NSRect, to url: URL) throws {
        guard let bitmap = view.bitmapImageRepForCachingDisplay(in: rect) else { throw CocoaError(.fileWriteUnknown) }
        view.cacheDisplay(in: rect, to: bitmap)
        guard let data = bitmap.representation(using: .png, properties: [:]), data.count > 1024 else { throw CocoaError(.fileWriteUnknown) }
        try data.write(to: url)
    }
}
