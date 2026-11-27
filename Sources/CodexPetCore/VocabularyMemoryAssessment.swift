import Foundation

public struct VocabularyMemoryAssessment {
    public let events: [ReviewEvent]
    public let recallProbability: Double?
    public let spacedSuccesses: Int
    public let isStable: Bool

    public init(stat: WordStat?, now: Date = Date(), retention: Double = 0.9) {
        var seen = Set<String>()
        events = (stat?.review?.events ?? []).filter {
            [.known, .unknown, .hard].contains($0.action) && $0.at <= now && seen.insert($0.id).inserted
        }.sorted { $0.at == $1.at ? $0.id < $1.id : $0.at < $1.at }
        var successes: [ReviewEvent] = []
        var preceding: ReviewEvent?
        for event in events {
            if event.action != .known {
                successes.removeAll()
            } else if let last = successes.last {
                if event.at.timeIntervalSince(last.at) >= 86400,
                   event.at >= (preceding?.result.card.due ?? last.result.card.due) {
                    successes.append(event)
                }
            } else if preceding == nil || event.at >= preceding!.result.card.due {
                successes.append(event)
            }
            preceding = event
        }
        spacedSuccesses = successes.count
        let target = min(0.95, max(0.8, retention))
        if let card = events.last?.result.card, card.stability.isFinite, card.stability > 0 {
            let probability = VocabularyReviewScheduler.engine(retention: target).getRetrievability(card: card, now: now).number
            recallProbability = probability.isFinite ? min(1, max(0, probability)) : nil
        } else { recallProbability = nil }
        let span: TimeInterval
        if let first = successes.first, let last = successes.last { span = last.at.timeIntervalSince(first.at) }
        else { span = 0 }
        let lastFeedback = stat?.lastFeedbackAt ?? stat?.updatedAt ?? .distantPast
        let contradictoryFeedback = stat?.lastAction != nil && stat?.lastAction != .known
            && lastFeedback >= (events.last?.at ?? .distantFuture)
        isStable = successes.count >= 3 && span >= 7 * 86400
            && !contradictoryFeedback
            && events.last?.action == .known && events.last?.result.card.state == .review
            && (events.last?.result.card.stability ?? 0) >= 7
            && (successes.last?.result.card.stability ?? 0) >= 7
            && (events.last?.result.card.due ?? .distantPast) > now
            && (stat?.postponedUntil ?? .distantPast) <= now
            && (recallProbability ?? 0) >= target
    }
}

extension VocabularyProgress {
    /// Explicit opt-in cleanup; a shown card is not a learning response.
    public func removingUnmarkedLegacyRecords() -> VocabularyProgress {
        VocabularyProgress(stats: stats.filter { _, stat in
            stat.review != nil || stat.lastAction != nil || stat.learned || stat.unknownCount > 0
                || stat.skippedCount > 0 || stat.lastFeedbackAt != nil || stat.legacyDueAt != nil
                || stat.postponedUntil != nil
        })
    }
}
