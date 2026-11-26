import AppKit
import CodexPetCore

enum PetVisibilityRegression {
    @MainActor static func run() async throws {
        let legacy = try JSONFileStore.decoder.decode(AppSettings.self, from: Data("{}".utf8))
        precondition(!legacy.petOnlyWithVocabulary && !AppSettings().petOnlyWithVocabulary)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try AppDataStore(root: root)
        let word = try store.captureWord(CapturePayload(term: "tranquil", meaning: "adj. 安静的"))
        let scoped = ScopedDictionaryEntry(dictionaryID: word.dictionaryID, dictionaryName: "我的生词", entry: word.entry)
        try store.reviewWord(scoped, action: .known)
        let history = try Data(contentsOf: store.progressURL)
        let notebook = try Data(contentsOf: store.personalVocabularyURL)
        let dictionaries = try JSONFileStore.encoder.encode(store.dictionaries)
        let pets = try JSONFileStore.encoder.encode(store.pets)
        try store.setPetOnlyWithVocabulary(true)
        let quietRestart = try AppDataStore(root: root)
        precondition(quietRestart.settings.petOnlyWithVocabulary)

        let view = PetContentView(frame: NSRect(x: 0, y: 0, width: 460, height: 700))
        let window = NSPanel(contentRect: view.frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = view
        let visibility = PetVisibilityController(window: window, contentView: view, store: store)
        defer { window.orderOut(nil); window.contentView = nil }
        func waitUntilHidden(_ phase: String) async throws {
            let started = Date()
            let deadline = started.addingTimeInterval(3)
            while window.isVisible || view.isPetVisible {
                guard Date() < deadline else {
                    throw NSError(domain: "PetVisibilityRegression", code: 2,
                        userInfo: [NSLocalizedDescriptionKey: "\(phase): window=\(window.isVisible), pet=\(view.isPetVisible), bubble=\(view.isBubbleVisible), word=\(view.hasVisibleVocabularyCard)"])
                }
                try await Task.sleep(for: .milliseconds(20))
            }
            print("pet-visibility-timing: \(phase) hidden in \(Int(Date().timeIntervalSince(started) * 1000))ms")
        }
        guard !window.isVisible && !view.isPetVisible else {
            throw NSError(domain: "PetVisibilityRegression", code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Vocabulary-only startup must hide both window and pet"])
        }
        let point = NSPoint(x: view.visualLayoutSnapshot.pet.midX, y: view.visualLayoutSnapshot.pet.midY)
        precondition(view.hitTest(point) == nil, "A hidden pet must not intercept desktop clicks")
        let rightClick = NSEvent.mouseEvent(with: .rightMouseDown, location: point, modifierFlags: [], timestamp: 0,
            windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
        precondition(view.menu(for: rightClick) == nil)

        func showWord(revealed: Bool) {
            view.showVocabularyCard(kicker: "我的生词", entry: word.entry, revealed: revealed,
                footer: "今日 1 / 10", known: "2 天", unknown: "10 分钟", hard: "15 分钟")
        }
        showWord(revealed: false)
        precondition(window.isVisible && view.isPetVisible && view.hasVisibleVocabularyCard)
        showWord(revealed: true)
        precondition(window.isVisible && view.isPetVisible)
        view.hideBubble(animated: true)
        try await waitUntilHidden("word-fade")

        showWord(revealed: false)
        view.showProgressEvent(ProgressEvent(source: "codex", stage: "完成", message: "验证", progress: 100, status: .done))
        precondition(window.isVisible && !view.isPetVisible && !view.hasVisibleVocabularyCard)
        let progress = view.subviews.compactMap { $0 as? CompanionProgressStackView }.first!
        progress.expire(now: Date().addingTimeInterval(13))
        precondition(!window.isVisible && !view.isPetVisible, "Expired AI-only notifications must leave no blank window")
        showWord(revealed: true)
        view.hideBubble(animated: false)
        precondition(!window.isVisible && !view.isPetVisible)
        view.showMessage(kicker: "词典", title: "暂时没有待复习词", body: "稍后再试", showActions: false, autoHideAfter: 0.03, animated: false)
        precondition(window.isVisible && !view.isPetVisible)
        try await waitUntilHidden("message-timeout")

        try store.setPetOnlyWithVocabulary(false)
        precondition(window.isVisible && view.isPetVisible, "Disabling the preference restores the companion immediately")
        visibility.hide()
        view.showProgressEvent(ProgressEvent(source: "codex", stage: "运行", message: "手动隐藏保持有效"))
        precondition(!window.isVisible && visibility.isManuallyHidden)
        visibility.show()
        precondition(window.isVisible && !visibility.isManuallyHidden && view.isPetVisible)
        view.hideBubble(animated: false)
        precondition(window.isVisible && view.isPetVisible, "Default companion mode remains visible without a card")
        showWord(revealed: true)
        try store.setPetOnlyWithVocabulary(true)
        precondition(window.isVisible && view.isPetVisible)
        view.hideBubble(animated: false)
        precondition(!window.isVisible && !view.isPetVisible)
        try store.setPetOnlyWithVocabulary(false)

        let reloaded = try AppDataStore(root: root)
        precondition(!reloaded.settings.petOnlyWithVocabulary)
        let historyAfter = try Data(contentsOf: store.progressURL)
        let notebookAfter = try Data(contentsOf: store.personalVocabularyURL)
        let dictionariesAfter = try JSONFileStore.encoder.encode(store.dictionaries)
        let petsAfter = try JSONFileStore.encoder.encode(store.pets)
        precondition(history == historyAfter && notebook == notebookAfter && dictionaries == dictionariesAfter && pets == petsAfter)

        try FileManager.default.removeItem(at: store.settingsURL)
        try FileManager.default.createDirectory(at: store.settingsURL, withIntermediateDirectories: false)
        var failed = false
        do { try store.setPetOnlyWithVocabulary(true) } catch { failed = true }
        precondition(failed && !store.settings.petOnlyWithVocabulary && window.isVisible && view.isPetVisible)
        print("pet-visibility-regression: legacy default, persisted preference, hidden startup, word/reveal/fade, AI-only expiry, timeout, manual hide/show, live toggle, failed-save rollback and immutable learning data passed")
    }
}
