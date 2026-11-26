import AppKit
import CodexPetCore

enum VocabularyCardRegression {
    @MainActor static func run() throws {
        let temporaryRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: temporaryRoot) }
        let assetStore = try AppDataStore(root: temporaryRoot)
        let pet = assetStore.pets.first { $0.id == "whisky-color" }!
        let entry = DictionaryEntry(term: "accommodate", phonetic: "US /əˈkɑːmədeɪt/ · UK /əˈkɒmədeɪt/",
            meaning: "v. 提供空间或设施以适应某事物；包含；容纳\nv. 适应；调整",
            example: "The room can accommodate 30 people.", exampleTranslation: "这个房间可以容纳 30 人。",
            hint: "在提供空间的语境中，accommodate 表示为人或事物提供足够的空间。")
        let original = try JSONFileStore.encoder.encode(entry)
        let text = VocabularyCardTypography.content(entry: entry, revealed: true, theme: .comic)
        precondition(text.string.contains("US /") && text.string.contains("UK /"))
        precondition(text.string.range(of: entry.term)!.lowerBound < text.string.range(of: "US /")!.lowerBound)
        precondition(text.string.contains(entry.example!) && text.string.contains(entry.exampleTranslation!))
        precondition(!text.string.contains("[释义]") && !text.string.contains("[例句]"))
        let exampleRange = (text.string as NSString).range(of: entry.example!)
        let targetRange = (entry.example! as NSString).range(of: entry.term)
        let color = text.attribute(.foregroundColor, at: exampleRange.location + targetRange.location, effectiveRange: nil) as! NSColor
        precondition(color != AppVisualTheme.comic.inkNSColor)
        text.enumerateAttribute(.paragraphStyle, in: NSRange(location: 0, length: text.length)) { value, _, _ in
            precondition((value as? NSParagraphStyle)?.alignment == .left)
        }
        let question = VocabularyCardTypography.content(entry: entry, revealed: false, theme: .comic).string
        precondition(question.contains(entry.term) && question.contains("US /") && !question.contains("提供空间"))
        let accentUnknown = DictionaryEntry(term: "race", phonetic: "/reɪs/", meaning: "赛跑")
        precondition(VocabularyCardTypography.pronunciation(accentUnknown) == "/reɪs/")
        let japanese = DictionaryEntry(term: "小さい", reading: "ちいさい", meaning: "小；微小")
        precondition(VocabularyCardTypography.pronunciation(japanese) == "读音  ちいさい")
        precondition(VocabularyCardTypography.highlightedRanges(term: "race", example: "The race ended. Tracer raced home. The horse is racing.").count == 3)
        precondition(VocabularyCardTypography.highlightedRanges(term: "percent/per cent", example: "Ten percent means ten per cent.").count == 2)
        precondition(VocabularyCardTypography.highlightedRanges(term: "science fiction/sci-fi", example: "She enjoys sci-fi.").count == 1)
        let compound = VocabularyCardTypography.content(entry: DictionaryEntry(term: "record", meaning: "[n./v.] 记录"), revealed: true, theme: .comic)
        precondition(compound.string.contains("n./v.\t记录") && !compound.string.contains("[n./v.]"))
        let mainFrame = NSRect(x: 0, y: 0, width: 1400, height: 900)
        let secondary = NSRect(x: -800, y: 0, width: 800, height: 600)
        let placement = PetWindowPlacement.frame(savedOrigin: NSPoint(x: -500, y: 10), screens: [mainFrame, secondary], main: mainFrame)
        precondition(secondary.contains(placement) && placement.height < 600)
        let partiallyOutside = PetWindowPlacement.frame(savedOrigin: NSPoint(x: -500, y: -10), screens: [mainFrame, secondary], main: mainFrame)
        precondition(secondary.contains(partiallyOutside))

        for size in [NSSize(width: 460, height: 700), NSSize(width: 420, height: 500)] {
            for theme in AppVisualTheme.allCases {
                let view = PetContentView(frame: NSRect(origin: .zero, size: size))
                view.setPetRenderer(assetStore.spriteRenderer(for: pet), fallbackImage: assetStore.previewImage(for: pet))
                view.applyTheme(theme)
                view.showVocabularyCard(kicker: "排版预览", entry: entry, revealed: false, footer: "今日 1 / 10",
                    known: "2 天", unknown: "10 分钟", hard: "15 分钟")
                let before = view.bubbleLayoutSnapshot
                precondition(!view.vocabularyTypographySnapshot.contextVisible)
                view.showVocabularyCard(kicker: "排版预览", entry: entry, revealed: true, footer: "今日 1 / 10",
                    known: "2 天", unknown: "10 分钟", hard: "15 分钟")
                let after = view.bubbleLayoutSnapshot
                let typography = view.vocabularyTypographySnapshot
                precondition(before.bubble.height <= 250 && after.bubble.height > before.bubble.height, "Recall must fit visible content, then expand on reveal")
                precondition(before.bubble.width == after.bubble.width && before.bubble.minY == after.bubble.minY, "Expansion keeps the same width and pet anchor")
                precondition(typography.contextVisible && typography.context.minY > 0)
                precondition(after.bubble.maxY <= view.bounds.maxY && typography.viewport.height > 0)
                precondition(after.controls.count == 4)
                precondition(typography.footer.contains("10 分钟") && typography.footer.contains("2 天"))
                precondition(after.controls.allSatisfy { $0.minX >= 24 && $0.maxX <= after.bubble.width - 24 && $0.minY >= 24 })
                precondition(typography.viewport.minX == 24 && typography.viewport.width == after.bubble.width - 48)
                var updated = entry
                updated.exampleTranslation = String(repeating: "更长的译文仍然完整保留。", count: 10)
                view.showVocabularyCard(kicker: "排版预览", entry: updated, revealed: true, footer: "今日 1 / 10",
                    known: "2 天", unknown: "10 分钟", hard: "15 分钟")
                precondition(view.bubbleLayoutSnapshot.bubble == after.bubble, "Same-state translation updates preserve the reading surface")
                precondition(view.vocabularyTypographySnapshot.document.height > view.vocabularyTypographySnapshot.viewport.height)
                func scrollView(in parent: NSView) -> NSScrollView? {
                    if let scroll = parent as? NSScrollView { return scroll }
                    return parent.subviews.compactMap { scrollView(in: $0) }.first
                }
                let scroll = scrollView(in: view)!
                scroll.contentView.scroll(to: NSPoint(x: 0, y: 40))
                let previousOffset = view.vocabularyTypographySnapshot.scrollOffset
                view.showVocabularyCard(kicker: "排版预览", entry: updated, revealed: true, footer: "今日 1 / 10",
                    known: "2 天", unknown: "10 分钟", hard: "15 分钟")
                precondition(view.vocabularyTypographySnapshot.scrollOffset == previousOffset, "Same-word refresh must preserve the reading position")
                view.applyTheme(theme == .comic ? .storybook : .comic)
                view.layoutSubtreeIfNeeded()
                precondition(view.vocabularyTypographySnapshot.scrollOffset == previousOffset)
                view.applyTheme(theme)
                if let directory = ProcessInfo.processInfo.environment["WHISKYCLING_REGRESSION_ARTIFACT_DIR"] {
                    let window = NSWindow(contentRect: view.frame, styleMask: [.borderless], backing: .buffered, defer: false)
                    window.contentView = view
                    view.showMessage(kicker: "", title: "", body: "", showActions: false, animated: false)
                    view.showVocabularyCard(kicker: "排版预览", entry: entry, revealed: true, footer: "今日 1 / 10",
                        known: "2 天", unknown: "10 分钟", hard: "15 分钟")
                    view.layoutSubtreeIfNeeded()
                    let image = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
                    view.cacheDisplay(in: view.bounds, to: image)
                    try image.representation(using: .png, properties: [:])!.write(to:
                        URL(fileURLWithPath: directory).appendingPathComponent("word-layout-\(theme.rawValue)-\(Int(size.height)).png"))
                    withExtendedLifetime(window) {}
                }
            }
        }
        let after = try JSONFileStore.encoder.encode(entry)
        precondition(original == after, "Typography cannot mutate saved vocabulary")
        if let directory = ProcessInfo.processInfo.environment["WHISKYCLING_WORD_CARD_FIXTURE_DIR"] {
            let root = URL(fileURLWithPath: directory)
            guard !FileManager.default.fileExists(atPath: root.path) else { throw CocoaError(.fileWriteFileExists) }
            let store = try AppDataStore(root: root)
            let pack = DictionaryPack(id: "word-layout-fixture", name: "我的生词", entries: [entry])
            try JSONFileStore.save(pack, to: store.dictionariesURL.appendingPathComponent("word-layout-fixture.json"))
            store.settings.enabledDictionaryIDs = [pack.id]
            store.settings.vocabularyRecallMode = true
            store.settings.walkingPaused = true
            store.settings.serverPort = 4792
            store.settings.visualTheme = .storybook
            store.saveSettings()
        }
        print("word-card-regression: structured typography, US/UK and Japanese reading, highlight, compact recall and anchored reveal expansion, same-state scroll preservation and two themes passed")
    }
}
