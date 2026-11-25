import AppKit
import CodexPetCore

// The release binary can run this isolated check on Macs with Command Line Tools but no XCTest.
enum NotebookRegression {
    @MainActor static func run() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try AppDataStore(root: root)
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
        let window = NSWindow(contentRect: view.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = view
        let spy = NotebookFeedbackSpy()
        view.delegate = spy
        view.showMessage(kicker: "我的生词本", title: "inherently", body: "/ɪnˈhɪərəntli/", showActions: true, footer: "今日 1/10")
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
            body: "UK /ɪnˈhɪərəntli/\n\n[释义]\nadv. 本质上；固有地\n\n[例句]\nThe system is inherently flawed.\n该系统本质上存在缺陷。", showActions: true, footer: "今日 1/10")
        view.configureVocabularyControls(revealed: true, known: "1天", unknown: "10分钟", hard: "15分钟")
        view.layoutSubtreeIfNeeded()
        if let directory = ProcessInfo.processInfo.environment["WHISKYCLING_REGRESSION_ARTIFACT_DIR"],
           let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
            view.cacheDisplay(in: view.bounds, to: bitmap)
            let output = URL(fileURLWithPath: directory).appendingPathComponent("recall-bubble.png")
            try bitmap.representation(using: .png, properties: [:])?.write(to: output)
        }
        precondition(!unknown.isHidden && reveal.isHidden)
        unknown.performClick(nil)
        precondition(spy.unknown == 1)
        view.hideBubble(animated: false)
        precondition(!view.isBubbleVisible)
        print("notebook-regression: persistence, dedup, FSRS restart, skip and native recall buttons passed")
    }
}

private final class NotebookFeedbackSpy: PetContentViewDelegate {
    var revealed = 0
    var unknown = 0
    func markKnown() {}
    func markUnknown() { unknown += 1 }
    func markHard() {}
    func revealVocabularyAnswer() { revealed += 1 }
    func skipWord() {}
    func requestVocabularyNow() {}
    func openSettings() {}
    func petClicked() {}
}
