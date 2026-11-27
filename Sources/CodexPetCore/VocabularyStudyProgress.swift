import Foundation

/// Feedback, not exposure, is the unit of study completion. Legacy aggregates
/// remain useful for totals, but cannot reconstruct a daily review history.
public struct VocabularyStudyProgress: Equatable {
    public var total = 0
    public var studied = 0
    public var familiar = 0
    public var seenOnly = 0
    public var due = 0
    public var pendingFeedback = 0
    public var answeredToday = 0
    public var newLearnedToday = 0
    public var reviewedToday = 0
    public var unclassifiedToday: Int { answeredToday - newLearnedToday - reviewedToday }
    public var nextReview: Date?
    public var learning: Int { studied - familiar }
    public var remaining: Int { total - studied }
    public var fraction: Double { total == 0 ? 0 : Double(studied) / Double(total) }

    public init(entries: [ScopedDictionaryEntry] = [], stats: [String: WordStat] = [:],
                now: Date = Date(), calendar: Calendar = .current, introducedKeys: Set<String> = []) {
        let today = calendar.startOfDay(for: now)
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) ?? now
        var keys = Set<String>()
        for entry in entries where keys.insert(entry.statKey).inserted {
            total += 1
            guard let stat = stats[entry.statKey] else {
                if introducedKeys.contains(entry.statKey) { pendingFeedback += 1 }
                continue
            }
            let events = stat.review?.events ?? []
            let hasFeedback = stat.review != nil || stat.learned || stat.unknownCount > 0
                || [.known, .unknown, .hard].contains(stat.lastAction)
            guard hasFeedback else {
                if stat.seenCount > 0 { seenOnly += 1 }
                if (introducedKeys.contains(entry.statKey) || stat.lastAction != nil),
                   (stat.postponedUntil ?? .distantPast) <= now,
                   (stat.lastSeenAt.map { now.timeIntervalSince($0) >= 600 } ?? true) {
                    pendingFeedback += 1
                }
                continue
            }
            studied += 1
            if stat.learned { familiar += 1 }
            let dueAt = VocabularyReviewScheduler.dueDate(stat, now: now)
            if dueAt <= now { due += 1 }
            else { nextReview = min(nextReview ?? dueAt, dueAt) }
            let todayEvents = events.filter { $0.at >= today && $0.at < tomorrow && $0.at <= now }
            if !todayEvents.isEmpty {
                answeredToday += 1
                if let first = events.map(\.at).min(), first >= today, stat.firstReviewWasNew == true {
                    newLearnedToday += 1
                } else if events.contains(where: { $0.at < today }) || stat.firstReviewWasNew == false {
                    reviewedToday += 1
                }
            } else if events.isEmpty, let feedback = stat.lastFeedbackAt,
                      feedback >= today, feedback < tomorrow, feedback <= now,
                      [.known, .unknown, .hard].contains(stat.lastAction) {
                answeredToday += 1
            }
        }
    }
}
