import Foundation
import FSRS

public struct ReviewEvent: Codable, Equatable {
    public var id: String
    public var action: WordAction
    public var at: Date
    public var result: RecordLogItem
}

public struct ScheduledReview: Codable, Equatable {
    public var card: Card
    public var events: [ReviewEvent]

    public static func merge(_ lhs: ScheduledReview?, _ rhs: ScheduledReview?) -> ScheduledReview? {
        guard let lhs else { return rhs }
        guard let rhs else { return lhs }
        var byID: [String: ReviewEvent] = [:]
        for event in lhs.events + rhs.events { byID[event.id] = event }
        let events: [ReviewEvent] = byID.values.sorted {
            if $0.at == $1.at { return $0.id < $1.id }
            return $0.at < $1.at
        }
        return ScheduledReview(card: events.last?.result.card ?? lhs.card, events: events)
    }
}

public enum VocabularyReviewScheduler {
    public static func engine(retention: Double = 0.9) -> FSRS {
        FSRS(parameters: FSRSParameters(
            requestRetention: min(0.95, max(0.8, retention)),
            w: FSRSDefaults.defaultWv6,
            enableFuzz: false,
            learningSteps: ["10m"], relearningSteps: ["10m"]
        ))
    }

    public static func next(_ stat: WordStat?, action: WordAction, now: Date, retention: Double = 0.9) throws -> WordStat {
        var updated = stat ?? WordStat()
        if updated.review == nil, action != .skipped {
            updated.firstReviewWasNew = !(updated.learned || updated.unknownCount > 0
                || [.known, .unknown, .hard].contains(updated.lastAction))
        }
        if updated.review == nil, updated.learned, updated.legacyDueAt == nil {
            updated.legacyDueAt = dueDate(updated, now: now)
        }
        updated.lastAction = action
        updated.lastFeedbackAt = now
        updated.updatedAt = now
        if action == .skipped {
            updated.skippedCount += 1
            updated.postponedUntil = Calendar.current.date(byAdding: .day, value: 1, to: now)
            return updated
        }
        let rating: Rating = action == .unknown ? .again : (action == .hard ? .hard : .good)
        let card = updated.review?.card ?? FSRSDefaults().createEmptyCard(now: now)
        let result = try engine(retention: retention).next(card: card, now: now, grade: rating)
        var events = updated.review?.events ?? []
        events.append(ReviewEvent(id: UUID().uuidString, action: action, at: now, result: result))
        updated.review = ScheduledReview(card: result.card, events: events)
        updated.legacyDueAt = nil
        updated.postponedUntil = nil
        updated.learned = action == .known
        if action == .unknown { updated.unknownCount += 1 }
        return updated
    }

    // Old aggregate counters cannot reconstruct review history. Migrate lazily without inventing answers.
    public static func dueDate(_ stat: WordStat?, now: Date) -> Date {
        guard let stat else { return now }
        let due = stat.review?.card.due ?? stat.legacyDueAt ?? (stat.learned
            ? (stat.lastFeedbackAt ?? stat.updatedAt).addingTimeInterval(7 * 86400) : now)
        return max(due, stat.postponedUntil ?? .distantPast)
    }

    public static func pick(
        from entries: [ScopedDictionaryEntry], stats: [String: WordStat],
        capturedAt: [String: Date], now: Date, newIntroducedToday: Int, newLimit: Int,
        reserveNewSlot: Bool = false, introducedKeys: Set<String> = []
    ) -> ScopedDictionaryEntry? {
        let eligible = entries.filter { entry in
            guard let stat = stats[entry.statKey] else { return true }
            return (stat.postponedUntil ?? .distantPast) <= now
                && (stat.lastSeenAt.map { now.timeIntervalSince($0) >= 600 } ?? true)
        }
        let fresh = eligible.filter { entry in
            let stat = stats[entry.statKey]
            return stat?.review == nil && stat?.lastAction == nil && !introducedKeys.contains(entry.statKey)
        }.sorted {
            let a = capturedAt[$0.statKey] ?? .distantPast
            let b = capturedAt[$1.statKey] ?? .distantPast
            return a == b ? $0.statKey < $1.statKey : a > b
        }
        let due = eligible.filter {
            let stat = stats[$0.statKey]
            return (stat?.review != nil || stat?.lastAction != nil || introducedKeys.contains($0.statKey))
                && dueDate(stat, now: now) <= now
        }.sorted {
            let a = dueDate(stats[$0.statKey], now: now)
            let b = dueDate(stats[$1.statKey], now: now)
            return a == b ? $0.statKey < $1.statKey : a < b
        }
        if newIntroducedToday < newLimit, reserveNewSlot, let first = fresh.first { return first }
        if let first = due.first { return first }
        return newIntroducedToday < newLimit ? fresh.first : nil
    }
}
