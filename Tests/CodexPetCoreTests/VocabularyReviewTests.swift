import Foundation
#if canImport(XCTest)
import XCTest
#endif
@testable import CodexPetCore

final class VocabularyReviewTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_790_000_000)

    func testFeedbackChangesActualDueTimeAndSkipDoesNotTrain() throws {
        let again = try VocabularyReviewScheduler.next(nil, action: .unknown, now: now)
        let good = try VocabularyReviewScheduler.next(nil, action: .known, now: now)
        XCTAssertLessThan(again.review!.card.due, good.review!.card.due)
        let later = try VocabularyReviewScheduler.next(good, action: .known, now: good.review!.card.due)
        XCTAssertGreaterThan(later.review!.card.stability, good.review!.card.stability)
        let skipped = try VocabularyReviewScheduler.next(later, action: .skipped, now: later.review!.card.due)
        XCTAssertEqual(skipped.review, later.review)
        XCTAssertTrue(skipped.learned)
        XCTAssertGreaterThan(skipped.postponedUntil!, later.review!.card.due)
        let forgotten = try VocabularyReviewScheduler.next(later, action: .unknown, now: later.review!.card.due)
        XCTAssertFalse(forgotten.learned)
        XCTAssertEqual(forgotten.review!.events.count, 3)
    }

    func testSyncKeepsLatestFailureAndUnionsReviewHistory() throws {
        let good = try VocabularyReviewScheduler.next(nil, action: .known, now: now)
        let again = try VocabularyReviewScheduler.next(good, action: .unknown, now: now.addingTimeInterval(86400))
        var viewed = good
        viewed.lastSeenAt = now.addingTimeInterval(172800)
        viewed.updatedAt = now.addingTimeInterval(172800)
        let merged = viewed.merged(with: again)
        XCTAssertFalse(merged.learned)
        XCTAssertEqual(merged.review?.events.count, 2)
        XCTAssertEqual(merged.review?.card, again.review?.card)
        XCTAssertEqual(merged, again.merged(with: viewed))
    }

    func testCaptureRoundTripDedupAndContexts() throws {
        var notebook = PersonalVocabulary()
        var input = CapturePayload(term: " inherently ", meaning: "adv. 本质上")
        input.example = "The system is inherently flawed."
        input.phoneticUK = "/ɪnˈhɪərəntli/"
        input.sourceURL = "https://example.org/article"
        let first = try notebook.capture(input, now: now)
        var duplicate = CapturePayload(term: "INHERENTLY")
        duplicate.example = "A different context."
        let second = try notebook.capture(duplicate, now: now.addingTimeInterval(100))
        XCTAssertEqual(first.id, second.id)
        XCTAssertEqual(first.createdAt, second.createdAt)
        XCTAssertEqual(second.content.meaning, input.meaning)
        XCTAssertEqual(second.contexts.count, 2)
        XCTAssertEqual(notebook.words.count, 1)
        let data = try JSONFileStore.encoder.encode(notebook)
        XCTAssertEqual(try JSONFileStore.decoder.decode(PersonalVocabulary.self, from: data), notebook)
        input.sourceURL = "javascript:alert(1)"
        XCTAssertThrowsError(try notebook.capture(input))
        XCTAssertThrowsError(try notebook.capture(CapturePayload(term: "")))
    }

    func testDuePriorityNewQuotaFreshnessAndCooldown() throws {
        let entries = ["old", "fresh", "forgotten"].map {
            ScopedDictionaryEntry(dictionaryID: "d", dictionaryName: "D", entry: DictionaryEntry(term: $0, meaning: "meaning"))
        }
        let stats = [entries[2].statKey: try VocabularyReviewScheduler.next(nil, action: .unknown, now: now.addingTimeInterval(-3600))]
        let captured = [entries[1].statKey: now]
        func pick(_ stats: [String: WordStat], newCount: Int = 0, reserve: Bool = false) -> String? {
            VocabularyReviewScheduler.pick(from: entries, stats: stats, capturedAt: captured, now: now,
                newIntroducedToday: newCount, newLimit: 3, reserveNewSlot: reserve)?.entry.term
        }
        XCTAssertEqual(pick(stats), "forgotten")
        XCTAssertEqual(pick(stats, reserve: true), "fresh")
        XCTAssertEqual(pick(stats, newCount: 3, reserve: true), "forgotten")
        var cooled = stats
        cooled[entries[2].statKey]!.lastSeenAt = now.addingTimeInterval(-10)
        XCTAssertEqual(pick(cooled), "fresh")
        XCTAssertNil(pick(cooled, newCount: 3))
        let continued = VocabularyReviewScheduler.pick(from: [entries[1]], stats: [:], capturedAt: captured,
            now: now, newIntroducedToday: 3, newLimit: 3, introducedKeys: [entries[1].statKey])
        XCTAssertEqual(continued?.entry.term, "fresh")
    }

    func testLegacyStatDecodesWithoutFabricatedHistoryAndSeenIsNotFeedback() throws {
        let legacy = #"{"learned":true,"unknownCount":0,"skippedCount":0,"seenCount":4,"lastAction":"known","updatedAt":"2026-05-01T10:00:00Z"}"#
        let stat = try JSONFileStore.decoder.decode(WordStat.self, from: Data(legacy.utf8))
        XCTAssertNil(stat.review)
        XCTAssertNil(stat.lastFeedbackAt)
        var legacyProgress = VocabularyProgress(stats: ["d::legacy": stat])
        let due = VocabularyReviewScheduler.dueDate(stat, now: now)
        legacyProgress.recordSeen(dictionaryID: "d", term: "legacy", at: now)
        XCTAssertEqual(VocabularyReviewScheduler.dueDate(legacyProgress.stats["d::legacy"], now: now), due)
        let deferred = try VocabularyReviewScheduler.next(stat, action: .skipped, now: now)
        XCTAssertEqual(VocabularyReviewScheduler.dueDate(deferred, now: now), deferred.postponedUntil)
        var progress = VocabularyProgress()
        progress.recordSeen(dictionaryID: "d", term: "word", at: now)
        progress.mark(dictionaryID: "d", term: "word", action: .unknown, at: now)
        XCTAssertEqual(progress.stats["d::word"]?.seenCount, 1)
    }
}
