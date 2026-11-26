import AppKit
import XCTest
import CodexPetCore
@testable import CodexPetApp

final class NotebookTests: XCTestCase {
    @MainActor func testStoreCaptureReviewAndRestartPreserveBoth() async throws {
        _ = NSApplication.shared
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try AppDataStore(root: root)
        let defaults = try JSONFileStore.decoder.decode(AppSettings.self, from: Data("{}".utf8))
        XCTAssertTrue(defaults.vocabularyRecallMode)
        XCTAssertEqual(defaults.dailyNewVocabularyLimit, 3)
        var payload = CapturePayload(term: "inherently", meaning: "adv. 本质上")
        payload.example = "The system is inherently flawed."
        let word = try store.captureWord(payload)
        let scoped = ScopedDictionaryEntry(dictionaryID: word.dictionaryID, dictionaryName: "我的生词本", entry: word.entry)
        let now = Date(timeIntervalSince1970: floor(Date().timeIntervalSince1970))
        store.recordVocabularyPresentation(scoped, automatic: false, now: now)
        try store.reviewWord(scoped, action: .known, now: now)
        let review = store.vocabularyProgress.stats[scoped.statKey]!.review
        payload.example = "A second context."
        try store.captureWord(payload)
        let restarted = try AppDataStore(root: root)
        XCTAssertEqual(restarted.personalVocabulary.words.count, 1)
        XCTAssertEqual(restarted.personalVocabulary.words.first?.contexts.count, 2)
        XCTAssertEqual(restarted.vocabularyProgress.stats[scoped.statKey]?.review, review)
        XCTAssertEqual(restarted.captureToken, store.captureToken)
        let attributes = try FileManager.default.attributesOfItem(atPath: root.appendingPathComponent("browser-pairing-token").path)
        XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o600)
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("learning-progress.pre-fsrs.json").path))
        try restarted.deleteCapturedWord(word)
        XCTAssertEqual(try AppDataStore(root: root).personalVocabulary.words.count, 0)
        XCTAssertNotNil(restarted.vocabularyProgress.stats[scoped.statKey]?.review)
    }

    @MainActor func testRecallControlsRevealAndFeedbackAreSeparate() async throws {
        _ = NSApplication.shared
        let view = PetContentView(frame: NSRect(x: 0, y: 0, width: 420, height: 500))
        let spy = FeedbackSpy()
        view.delegate = spy
        view.showMessage(kicker: "我的词本", title: "inherently", body: "/ɪnˈhɪərəntli/", showActions: true, footer: "今日 1/10")
        view.configureVocabularyControls(revealed: false, known: "1天", unknown: "10分钟", hard: "15分钟")
        func buttons(_ parent: NSView) -> [NSButton] {
            parent.subviews.flatMap { ($0 as? NSButton).map { [$0] } ?? buttons($0) }
        }
        let all = buttons(view)
        XCTAssertTrue(all.first { $0.title == "不认识" }!.isHidden)
        let reveal = all.first { $0.title == "查看释义" }!
        XCTAssertFalse(reveal.isHidden)
        reveal.performClick(nil)
        XCTAssertEqual(spy.reveals, 1)
        XCTAssertEqual(spy.unknowns, 0)
        view.configureVocabularyControls(revealed: true, known: "1天", unknown: "10分钟", hard: "15分钟")
        all.first { $0.title == "不认识" }!.performClick(nil)
        XCTAssertEqual(spy.unknowns, 1)
        view.hideBubble(animated: false)
        XCTAssertFalse(view.isBubbleVisible)
    }
}

private final class FeedbackSpy: PetContentViewDelegate {
    var reveals = 0
    var unknowns = 0
    var petWalkingPaused = false
    func markKnown() {}
    func markUnknown() { unknowns += 1 }
    func markHard() {}
    func revealVocabularyAnswer() { reveals += 1 }
    func skipWord() {}
    func requestVocabularyNow() {}
    func openSettings() {}
    func petClicked() {}
    func togglePetWalking() { petWalkingPaused.toggle() }
}
