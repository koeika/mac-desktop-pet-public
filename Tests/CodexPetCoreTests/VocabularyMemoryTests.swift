import Foundation
#if canImport(XCTest)
import XCTest
#endif
@testable import CodexPetCore

final class VocabularyMemoryTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_790_000_000)

    func testOneClickAndRapidRepetitionNeverEstablishStableMemory() throws {
        var stat = try VocabularyReviewScheduler.next(nil, action: .known, now: start)
        XCTAssertFalse(VocabularyMemoryAssessment(stat: stat, now: start).isStable)
        for minute in 1...12 {
            stat = try VocabularyReviewScheduler.next(stat, action: .known, now: start.addingTimeInterval(Double(minute) * 60))
        }
        let memory = VocabularyMemoryAssessment(stat: stat, now: start.addingTimeInterval(12 * 60))
        XCTAssertFalse(memory.isStable)
        XCTAssertEqual(memory.spacedSuccesses, 1)
    }

    func testSpacedSuccessRequiresEvidenceAndDecaysOrResets() throws {
        var now = start
        var stat = try VocabularyReviewScheduler.next(nil, action: .known, now: now)
        for _ in 0..<8 {
            now = max(stat.review!.card.due, now.addingTimeInterval(86400))
            stat = try VocabularyReviewScheduler.next(stat, action: .known, now: now)
        }
        let memory = VocabularyMemoryAssessment(stat: stat, now: now)
        XCTAssertTrue(memory.isStable)
        XCTAssertGreaterThan(memory.spacedSuccesses, 2)
        let expired = VocabularyMemoryAssessment(stat: stat, now: stat.review!.card.due.addingTimeInterval(1))
        XCTAssertFalse(expired.isStable)
        XCTAssertLessThan(expired.recallProbability!, memory.recallProbability!)
        let again = try VocabularyReviewScheduler.next(stat, action: .unknown, now: stat.review!.card.due)
        XCTAssertFalse(VocabularyMemoryAssessment(stat: again, now: stat.review!.card.due).isStable)
        XCTAssertEqual(VocabularyMemoryAssessment(stat: again, now: stat.review!.card.due).spacedSuccesses, 0)
        let hard = try VocabularyReviewScheduler.next(stat, action: .hard, now: stat.review!.card.due)
        XCTAssertFalse(VocabularyMemoryAssessment(stat: hard, now: stat.review!.card.due).isStable)
        let skipped = try VocabularyReviewScheduler.next(stat, action: .skipped, now: now)
        XCTAssertFalse(VocabularyMemoryAssessment(stat: skipped, now: now).isStable)
        var aggregateFailure = WordStat(lastAction: .unknown, updatedAt: now.addingTimeInterval(1))
        aggregateFailure.lastFeedbackAt = now.addingTimeInterval(1)
        let merged = stat.merged(with: aggregateFailure)
        XCTAssertFalse(VocabularyMemoryAssessment(stat: merged, now: now.addingTimeInterval(1)).isStable)
    }

    func testCleanupRemovesOnlyUnmarkedMetadataAndIsIdempotent() throws {
        let marked = try VocabularyReviewScheduler.next(nil, action: .known, now: start)
        let legacy = WordStat(learned: true, lastAction: .known, updatedAt: start)
        let skipped = try VocabularyReviewScheduler.next(nil, action: .skipped, now: start)
        let progress = VocabularyProgress(stats: ["d::seen": WordStat(seenCount: 10), "d::empty": WordStat(),
            "d::marked": marked, "d::legacy": legacy, "d::skip": skipped, "d::unknown": WordStat(unknownCount: 1)])
        let cleaned = progress.removingUnmarkedLegacyRecords()
        XCTAssertEqual(cleaned.stats.count, 4)
        XCTAssertEqual(cleaned.stats["d::marked"], marked)
        XCTAssertEqual(cleaned.stats["d::legacy"], legacy)
        XCTAssertEqual(cleaned.stats["d::skip"], skipped)
        XCTAssertEqual(cleaned.removingUnmarkedLegacyRecords(), cleaned)
        XCTAssertEqual(progress.stats.count, 6)
    }

    func testPrematureAnswerAfterFailureDoesNotEarnSpacedCredit() throws {
        var stat = try VocabularyReviewScheduler.next(nil, action: .hard, now: start)
        stat = try VocabularyReviewScheduler.next(stat, action: .known, now: start.addingTimeInterval(60))
        XCTAssertEqual(VocabularyMemoryAssessment(stat: stat, now: start.addingTimeInterval(60)).spacedSuccesses, 0)
        var now = start.addingTimeInterval(60)
        for _ in 0..<2 {
            now = max(stat.review!.card.due, now.addingTimeInterval(86400))
            stat = try VocabularyReviewScheduler.next(stat, action: .known, now: now)
        }
        XCTAssertEqual(VocabularyMemoryAssessment(stat: stat, now: now).spacedSuccesses, 2)
        XCTAssertFalse(VocabularyMemoryAssessment(stat: stat, now: now).isStable)
    }

    func testExclusiveProgressLockRejectsConcurrentWriter() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let first = try LearningProgressLock(root: root)
        defer { withExtendedLifetime(first) {} }
        var rejected = false
        do { _ = try LearningProgressLock(root: root) } catch { rejected = true }
        XCTAssertTrue(rejected)
    }
}
