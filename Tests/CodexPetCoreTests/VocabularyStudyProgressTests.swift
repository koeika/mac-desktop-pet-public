import Foundation
#if canImport(XCTest)
import XCTest
#endif
@testable import CodexPetCore

final class VocabularyStudyProgressTests: XCTestCase {
    func testLegacyAggregateFlagsCannotInflateConfirmedProgress() throws {
        var entries: [ScopedDictionaryEntry] = []
        var stats: [String: WordStat] = [:]
        for index in 0..<720 {
            let word = entry("fixture-\(index)")
            entries.append(word)
            if index < 655 {
                stats[word.statKey] = WordStat(learned: index < 468, unknownCount: index < 468 ? 0 : 1,
                    seenCount: 2, lastAction: index < 468 ? .known : .unknown, updatedAt: now.addingTimeInterval(-86400))
            } else {
                stats[word.statKey] = try VocabularyReviewScheduler.next(nil,
                    action: index < 715 ? .known : .unknown, now: now)
            }
        }
        let result = VocabularyStudyProgress(entries: entries, stats: stats, now: now)
        XCTAssertEqual(result.studied, 65)
        XCTAssertEqual(result.familiar, 60)
        XCTAssertEqual(result.learning, 65)
        XCTAssertEqual(result.mastered, 0)
        XCTAssertEqual(result.legacyUnverified, 655)
    }
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 8 * 3600)!
        return calendar
    }
    private let now = Date(timeIntervalSince1970: 1_790_000_000)
    private func entry(_ term: String, dictionaryID: String = "d") -> ScopedDictionaryEntry {
        ScopedDictionaryEntry(dictionaryID: dictionaryID, dictionaryName: dictionaryID,
            entry: DictionaryEntry(term: term, meaning: "meaning"))
    }

    func testExposureSkipAndDuplicateDoNotInflateStudyProgress() throws {
        let entries = [entry("new"), entry("viewed"), entry("skipped"), entry("known"), entry("unknown"), entry("hard")]
        var progress = VocabularyProgress()
        progress.recordSeen(dictionaryID: "d", term: "viewed", at: now)
        for (term, action) in [("skipped", WordAction.skipped), ("known", .known), ("unknown", .unknown), ("hard", .hard)] {
            progress.stats[entry(term).statKey] = try VocabularyReviewScheduler.next(nil, action: action, now: now)
        }
        let result = VocabularyStudyProgress(entries: entries + [entry("known")], stats: progress.stats, now: now, calendar: calendar)
        XCTAssertEqual(result.total, 6)
        XCTAssertEqual(result.studied, 3)
        XCTAssertEqual(result.familiar, 1)
        XCTAssertEqual(result.learning, 3)
        XCTAssertEqual(result.seenOnly, 1)
        XCTAssertEqual(result.remaining, 3)
        XCTAssertEqual(result.fraction, 0)
        XCTAssertEqual(result.coverageFraction, 0.5)
        XCTAssertEqual(result.answeredToday, 3)
    }

    func testOnlyDatedFeedbackCountsAndLatestAnswerWins() throws {
        let real = try VocabularyReviewScheduler.next(nil, action: .unknown, now: now)
        var stale = real
        stale.learned = true
        stale.lastAction = .known
        var future = try VocabularyReviewScheduler.next(nil, action: .known, now: now.addingTimeInterval(86400))
        future.lastFeedbackAt = now
        var skipOnly = real
        skipOnly.review!.events[0].action = .skipped
        skipOnly.learned = false
        skipOnly.lastAction = .skipped
        skipOnly.unknownCount = 0
        let entries = [entry("stale"), entry("future"), entry("skip-event")]
        let stats = [entries[0].statKey: stale, entries[1].statKey: future, entries[2].statKey: skipOnly]
        let bytes = try JSONFileStore.encoder.encode(VocabularyProgress(stats: stats))
        let result = VocabularyStudyProgress(entries: entries, stats: stats, now: now, calendar: calendar)
        XCTAssertEqual(result.studied, 1)
        XCTAssertEqual(result.familiar, 0)
        XCTAssertEqual(result.answeredToday, 1)
        let unchanged = try JSONFileStore.encoder.encode(VocabularyProgress(stats: stats))
        XCTAssertEqual(unchanged, bytes)
        let repeated = try VocabularyReviewScheduler.next(real, action: .known, now: now.addingTimeInterval(60))
        let after = VocabularyStudyProgress(entries: [entry("stale")], stats: [entry("stale").statKey: repeated], now: now.addingTimeInterval(60))
        XCTAssertEqual(after.studied, 1)
        XCTAssertEqual(after.familiar, 1)
        XCTAssertEqual(after.fraction, 0)
        XCTAssertEqual(after.coverageFraction, 1)
    }

    func testDailyCountsAreDistinctLocalCalendarFeedbackNotExposures() throws {
        let yesterday = calendar.date(byAdding: .day, value: -1, to: now)!
        var old = try VocabularyReviewScheduler.next(nil, action: .unknown, now: yesterday)
        old = try VocabularyReviewScheduler.next(old, action: .known, now: now.addingTimeInterval(-30))
        old = try VocabularyReviewScheduler.next(old, action: .unknown, now: now)
        let fresh = try VocabularyReviewScheduler.next(nil, action: .known, now: now)
        let stats = [entry("old").statKey: old, entry("fresh").statKey: fresh]
        let entries = [entry("old"), entry("fresh")]
        let today = VocabularyStudyProgress(entries: entries, stats: stats, now: now, calendar: calendar)
        XCTAssertEqual(today.answeredToday, 2)
        XCTAssertEqual(today.newLearnedToday, 1)
        XCTAssertEqual(today.reviewedToday, 1)
        let tomorrow = VocabularyStudyProgress(entries: entries, stats: stats,
            now: calendar.date(byAdding: .day, value: 1, to: now)!, calendar: calendar)
        XCTAssertEqual(tomorrow.answeredToday, 0)
        XCTAssertEqual(tomorrow.studied, 2)
        XCTAssertEqual(VocabularyStudyProgress().fraction, 0)
    }

    func testDictionaryIsolationLegacyTotalsAndDueBoundary() throws {
        let known = WordStat(learned: true, lastAction: .known, updatedAt: now.addingTimeInterval(-86400))
        let scheduled = try VocabularyReviewScheduler.next(nil, action: .unknown, now: now)
        let entries = [entry("legacy"), entry("scheduled"), entry("scheduled", dictionaryID: "other")]
        let stats = [entry("legacy").statKey: known, entry("scheduled").statKey: scheduled]
        let initial = VocabularyStudyProgress(entries: entries, stats: stats, now: now, calendar: calendar)
        XCTAssertEqual(initial.studied, 1)
        XCTAssertEqual(initial.legacyUnverified, 1)
        XCTAssertEqual(initial.answeredToday, 1)
        XCTAssertEqual(initial.due, 0)
        XCTAssertEqual(initial.nextReview, scheduled.review!.card.due)
        let due = VocabularyStudyProgress(entries: entries, stats: stats, now: scheduled.review!.card.due, calendar: calendar)
        XCTAssertEqual(due.due, 1)
        XCTAssertEqual(due.total, 3)
    }

    func testPendingFeedbackMatchesQueueAfterNewQuotaIsExhausted() throws {
        let entries = [entry("introduced"), entry("skipped")]
        var viewed = WordStat(seenCount: 1)
        viewed.lastSeenAt = now.addingTimeInterval(-601)
        let skipped = try VocabularyReviewScheduler.next(nil, action: .skipped, now: now.addingTimeInterval(-172800))
        var stats = [entries[0].statKey: viewed, entries[1].statKey: skipped]
        let introduced = Set([entries[0].statKey])
        let progress = VocabularyStudyProgress(entries: entries, stats: stats, now: now, introducedKeys: introduced)
        XCTAssertEqual(progress.pendingFeedback, 2)
        XCTAssertEqual(progress.studied, 0)
        XCTAssertEqual(progress.due, 0)
        let picked = VocabularyReviewScheduler.pick(from: entries, stats: stats, capturedAt: [:], now: now,
            newIntroducedToday: 3, newLimit: 3, introducedKeys: introduced)
        XCTAssertTrue(picked != nil)
        stats[entries[0].statKey]!.lastSeenAt = now
        stats[entries[1].statKey]!.postponedUntil = now.addingTimeInterval(86400)
        XCTAssertEqual(VocabularyStudyProgress(entries: entries, stats: stats, now: now, introducedKeys: introduced).pendingFeedback, 0)
        XCTAssertNil(VocabularyReviewScheduler.pick(from: entries, stats: stats, capturedAt: [:], now: now,
            newIntroducedToday: 3, newLimit: 3, introducedKeys: introduced))
    }

    func testLegacyFeedbackIsNotReclassifiedAsFirstLearning() throws {
        let legacy = WordStat(learned: true, seenCount: 4, lastAction: .known, updatedAt: now.addingTimeInterval(-864000))
        let reviewed = try VocabularyReviewScheduler.next(legacy, action: .known, now: now)
        let decoded = try JSONFileStore.decoder.decode(WordStat.self, from: JSONFileStore.encoder.encode(reviewed))
        XCTAssertEqual(decoded.firstReviewWasNew, false)
        let progress = VocabularyStudyProgress(entries: [entry("legacy")], stats: [entry("legacy").statKey: decoded], now: now, calendar: calendar)
        XCTAssertEqual(progress.answeredToday, 1)
        XCTAssertEqual(progress.newLearnedToday, 0)
        XCTAssertEqual(progress.reviewedToday, 1)
        var ambiguous = reviewed
        ambiguous.firstReviewWasNew = nil
        let unknown = VocabularyStudyProgress(entries: [entry("legacy")], stats: [entry("legacy").statKey: ambiguous], now: now, calendar: calendar)
        XCTAssertEqual(unknown.newLearnedToday, 0)
        XCTAssertEqual(unknown.unclassifiedToday, 1)
        XCTAssertEqual(ambiguous.merged(with: reviewed).firstReviewWasNew, false)
    }

    func testSyncProvenanceFollowsEarliestEvidence() throws {
        let fresh = try VocabularyReviewScheduler.next(nil, action: .known, now: now)
        let legacy = WordStat(learned: true, lastAction: .known, updatedAt: now.addingTimeInterval(-864000))
        let merged = fresh.merged(with: legacy)
        XCTAssertEqual(merged, legacy.merged(with: fresh))
        let result = VocabularyStudyProgress(entries: [entry("word")], stats: [entry("word").statKey: merged], now: now, calendar: calendar)
        XCTAssertEqual(result.newLearnedToday, 0)
        XCTAssertEqual(result.reviewedToday, 1)
        var earlier = try VocabularyReviewScheduler.next(nil, action: .known, now: now.addingTimeInterval(-86400))
        earlier.firstReviewWasNew = nil
        let combined = earlier.merged(with: fresh)
        XCTAssertEqual(combined.firstReviewWasNew, nil)
        let decoded = try JSONFileStore.decoder.decode(WordStat.self, from: JSONFileStore.encoder.encode(combined))
        let history = VocabularyStudyProgress(entries: [entry("word")], stats: [entry("word").statKey: decoded], now: now, calendar: calendar)
        XCTAssertEqual(history.newLearnedToday, 0)
        XCTAssertEqual(history.reviewedToday, 1)
        let laterLegacy = WordStat(learned: true, lastAction: .known, updatedAt: now.addingTimeInterval(10))
        let withLegacy = fresh.merged(with: laterLegacy)
        let readback = try JSONFileStore.decoder.decode(WordStat.self, from: JSONFileStore.encoder.encode(withLegacy))
        XCTAssertEqual(readback.merged(with: fresh).firstReviewWasNew, false)
        XCTAssertEqual(earlier.merged(with: fresh).merged(with: laterLegacy).firstReviewWasNew,
            earlier.merged(with: fresh.merged(with: laterLegacy)).firstReviewWasNew)
    }
}
