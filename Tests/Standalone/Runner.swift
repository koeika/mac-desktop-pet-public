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
        try progress.testExposureSkipAndDuplicateDoNotInflateStudyProgress()
        try progress.testDailyCountsAreDistinctLocalCalendarFeedbackNotExposures()
        try progress.testDictionaryIsolationLegacyTotalsAndDueBoundary()
        try progress.testPendingFeedbackMatchesQueueAfterNewQuotaIsExhausted()
        try progress.testLegacyFeedbackIsNotReclassifiedAsFirstLearning()
        try progress.testSyncProvenanceFollowsEarliestEvidence()
        try await CaptureHTTPTests().testAuthenticatedCapturePersistsAndRejectsInvalidWrites()
        print("core-regression: 12 cases passed (FSRS, sync, capture, queue, migration, study progress, real HTTP)")
    }
}
