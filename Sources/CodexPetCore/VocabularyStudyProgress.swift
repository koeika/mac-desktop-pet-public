import Foundation

/// Only dated feedback events establish study coverage. Legacy aggregates are
/// retained separately, without treating an old flag as confirmed learning.
public struct VocabularyStudyProgress: Equatable {
    public var total = 0
    public var studied = 0
    public var familiar = 0
    public var mastered = 0
    public var seenOnly = 0
    public var due = 0
    public var pendingFeedback = 0
    public var legacyUnverified = 0
    public var legacyDue = 0
    public var answeredToday = 0
    public var newLearnedToday = 0
    public var reviewedToday = 0
    public var unclassifiedToday: Int { answeredToday - newLearnedToday - reviewedToday }
    public var nextReview: Date?
    public var learning: Int { studied - mastered }
    public var remaining: Int { total - studied }
    public var fraction: Double { total == 0 ? 0 : Double(mastered) / Double(total) }
    public var coverageFraction: Double { total == 0 ? 0 : Double(studied) / Double(total) }

    public init(entries: [ScopedDictionaryEntry] = [], stats: [String: WordStat] = [:],
                now: Date = Date(), calendar: Calendar = .current, introducedKeys: Set<String> = [], retention: Double = 0.9) {
        let today = calendar.startOfDay(for: now)
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) ?? now
        var keys = Set<String>()
        for entry in entries where keys.insert(entry.statKey).inserted {
            total += 1
            guard let stat = stats[entry.statKey] else {
                if introducedKeys.contains(entry.statKey) { pendingFeedback += 1 }
                continue
            }
            let memory = VocabularyMemoryAssessment(stat: stat, now: now, retention: retention)
            let events = memory.events
            let hasLegacyFeedback = stat.review != nil || stat.learned || stat.unknownCount > 0
                || [.known, .unknown, .hard].contains(stat.lastAction)
            guard !events.isEmpty else {
                if hasLegacyFeedback {
                    legacyUnverified += 1
                    if (stat.review != nil || stat.lastAction != nil || introducedKeys.contains(entry.statKey)),
                       VocabularyReviewScheduler.dueDate(stat, now: now) <= now { legacyDue += 1 }
                    continue
                }
                if stat.seenCount > 0 { seenOnly += 1 }
                if (introducedKeys.contains(entry.statKey) || stat.lastAction != nil),
                   (stat.postponedUntil ?? .distantPast) <= now,
                   (stat.lastSeenAt.map { now.timeIntervalSince($0) >= 600 } ?? true) {
                    pendingFeedback += 1
                }
                continue
            }
            studied += 1
            let latest = events.max { a, b in a.at == b.at ? a.id < b.id : a.at < b.at }
            if latest?.action == .known { familiar += 1 }
            if memory.isStable { mastered += 1 }
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
            }
        }
    }
}
