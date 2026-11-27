import Foundation

// Apple's Command Line Tools omit XCTest; run the same core cases with fatal assertions there.
#if !canImport(XCTest)
class XCTestCase {}
func XCTAssertEqual<T: Equatable>(_ a: T, _ b: T, file: StaticString = #file, line: UInt = #line) {
    precondition(a == b, "\(a) != \(b)", file: file, line: line)
}
func XCTAssertLessThan<T: Comparable>(_ a: T, _ b: T) { precondition(a < b) }
func XCTAssertGreaterThan<T: Comparable>(_ a: T, _ b: T) { precondition(a > b) }
func XCTAssertTrue(_ a: Bool) { precondition(a) }
func XCTAssertFalse(_ a: Bool) { precondition(!a) }
func XCTAssertNil(_ a: Any?) { precondition(a == nil) }
func XCTAssertThrowsError<T>(_ expression: @autoclosure () throws -> T) {
    do { _ = try expression() } catch { return }
    preconditionFailure("Expected an error")
}
#endif

@main struct CoreRegressionRunner {
    static func main() async throws {
        let tests = VocabularyReviewTests()
        try tests.testFeedbackChangesActualDueTimeAndSkipDoesNotTrain()
        try tests.testSyncKeepsLatestFailureAndUnionsReviewHistory()
        try tests.testCaptureRoundTripDedupAndContexts()
        try tests.testDuePriorityNewQuotaFreshnessAndCooldown()
        try tests.testLegacyStatDecodesWithoutFabricatedHistoryAndSeenIsNotFeedback()
        let progress = VocabularyStudyProgressTests()
        try progress.testLegacyAggregateFlagsCannotInflateConfirmedProgress()
        try progress.testOnlyDatedFeedbackCountsAndLatestAnswerWins()
        try progress.testExposureSkipAndDuplicateDoNotInflateStudyProgress()
        try progress.testDailyCountsAreDistinctLocalCalendarFeedbackNotExposures()
        try progress.testDictionaryIsolationLegacyTotalsAndDueBoundary()
        try progress.testPendingFeedbackMatchesQueueAfterNewQuotaIsExhausted()
        try progress.testLegacyFeedbackIsNotReclassifiedAsFirstLearning()
        try progress.testSyncProvenanceFollowsEarliestEvidence()
        let memory = VocabularyMemoryTests()
        try memory.testOneClickAndRapidRepetitionNeverEstablishStableMemory()
        try memory.testSpacedSuccessRequiresEvidenceAndDecaysOrResets()
        try memory.testCleanupRemovesOnlyUnmarkedMetadataAndIsIdempotent()
        try memory.testPrematureAnswerAfterFailureDoesNotEarnSpacedCredit()
        try memory.testExclusiveProgressLockRejectsConcurrentWriter()
        try await CaptureHTTPTests().testAuthenticatedCapturePersistsAndRejectsInvalidWrites()
        print("core-regression: 19 cases passed (FSRS, stable memory, cleanup, exclusive lock, sync, capture, queue, migration, real HTTP)")
    }
}
