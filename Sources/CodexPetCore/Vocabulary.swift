import Foundation

public struct DictionaryEntry: Codable, Hashable, Equatable {
    public var term: String
    public var reading: String?
    public var phonetic: String?
    public var meaning: String
    public var example: String?
    public var exampleTranslation: String?
    public var hint: String?
    public var tags: [String]

    public init(
        term: String,
        reading: String? = nil,
        phonetic: String? = nil,
        meaning: String,
        example: String? = nil,
        exampleTranslation: String? = nil,
        hint: String? = nil,
        tags: [String] = []
    ) {
        self.term = term
        self.reading = reading
        self.phonetic = phonetic
        self.meaning = meaning
        self.example = example
        self.exampleTranslation = exampleTranslation
        self.hint = hint
        self.tags = tags
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        term = try container.decode(String.self, forKey: .term)
        reading = try container.decodeIfPresent(String.self, forKey: .reading)
        phonetic = try container.decodeIfPresent(String.self, forKey: .phonetic)
        meaning = try container.decode(String.self, forKey: .meaning)
        example = try container.decodeIfPresent(String.self, forKey: .example)
        exampleTranslation = try container.decodeIfPresent(String.self, forKey: .exampleTranslation)
        hint = try container.decodeIfPresent(String.self, forKey: .hint)
        tags = try container.decodeIfPresent([String].self, forKey: .tags) ?? []
    }
}

public struct DictionaryPack: Codable, Identifiable, Equatable {
    public var id: String
    public var name: String
    public var description: String?
    public var entries: [DictionaryEntry]

    public init(
        id: String,
        name: String,
        description: String? = nil,
        entries: [DictionaryEntry]
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.entries = entries
    }
}

public struct ScopedDictionaryEntry: Equatable {
    public var dictionaryID: String
    public var dictionaryName: String
    public var entry: DictionaryEntry

    public init(dictionaryID: String, dictionaryName: String, entry: DictionaryEntry) {
        self.dictionaryID = dictionaryID
        self.dictionaryName = dictionaryName
        self.entry = entry
    }

    public var statKey: String {
        WordStat.key(dictionaryID: dictionaryID, term: entry.term)
    }
}

public enum WordAction: String, Codable, Equatable {
    case known
    case unknown
    case skipped
    case hard
}

public struct WordStat: Codable, Equatable {
    public var learned: Bool
    public var unknownCount: Int
    public var skippedCount: Int
    public var seenCount: Int
    public var lastAction: WordAction?
    public var updatedAt: Date
    public var lastFeedbackAt: Date?
    public var lastSeenAt: Date?
    public var postponedUntil: Date?
    public var legacyDueAt: Date?
    public var review: ScheduledReview?
    public var firstReviewWasNew: Bool?

    public init(
        learned: Bool = false,
        unknownCount: Int = 0,
        skippedCount: Int = 0,
        seenCount: Int = 0,
        lastAction: WordAction? = nil,
        updatedAt: Date = Date()
    ) {
        self.learned = learned
        self.unknownCount = unknownCount
        self.skippedCount = skippedCount
        self.seenCount = seenCount
        self.lastAction = lastAction
        self.updatedAt = updatedAt
    }

    public static func key(dictionaryID: String, term: String) -> String {
        "\(dictionaryID)::\(term.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())"
    }

    public func merged(with other: WordStat) -> WordStat {
        let lhsDate = lastFeedbackAt ?? updatedAt
        let rhsDate = other.lastFeedbackAt ?? other.updatedAt
        let lhsTie = (review?.events.last?.id ?? "") + (lastAction?.rawValue ?? "")
        let rhsTie = (other.review?.events.last?.id ?? "") + (other.lastAction?.rawValue ?? "")
        let latest = lhsDate == rhsDate ? (lhsTie >= rhsTie ? self : other) : (lhsDate > rhsDate ? self : other)
        var result = WordStat(
            learned: latest.learned,
            unknownCount: max(unknownCount, other.unknownCount),
            skippedCount: max(skippedCount, other.skippedCount),
            seenCount: max(seenCount, other.seenCount),
            lastAction: latest.lastAction,
            updatedAt: max(updatedAt, other.updatedAt)
        )
        result.lastFeedbackAt = latest.lastFeedbackAt
        result.lastSeenAt = [lastSeenAt, other.lastSeenAt].compactMap { $0 }.max()
        result.postponedUntil = latest.postponedUntil
        result.legacyDueAt = latest.legacyDueAt
        result.review = ScheduledReview.merge(review, other.review)
        // Provenance belongs to the earliest review. Preserve legacy evidence
        // conservatively so a later sync cannot turn a reviewed word into new.
        let copies = [self, other]
        let hasLegacyFeedback = copies.contains {
            ($0.review?.events.isEmpty ?? true) && ($0.learned || $0.unknownCount > 0
                || [.known, .unknown, .hard].contains($0.lastAction))
        }
        if hasLegacyFeedback || copies.contains(where: { $0.firstReviewWasNew == false }) {
            result.firstReviewWasNew = false
        } else if let first = result.review?.events.first {
            let earliest = copies.filter { $0.review?.events.contains(where: { $0.id == first.id }) == true }
            result.firstReviewWasNew = earliest.contains(where: { $0.firstReviewWasNew == true }) ? true : nil
        }
        return result
    }
}

public struct VocabularyProgress: Codable, Equatable {
    public var stats: [String: WordStat]

    public init(stats: [String: WordStat] = [:]) {
        self.stats = stats
    }

    public mutating func mark(dictionaryID: String, term: String, action: WordAction, at date: Date = Date()) {
        let key = WordStat.key(dictionaryID: dictionaryID, term: term)
        var stat = stats[key] ?? WordStat()
        stat.lastAction = action
        stat.updatedAt = date
        stat.lastFeedbackAt = date

        switch action {
        case .known:
            stat.learned = true
        case .unknown:
            stat.learned = false
            stat.unknownCount += 1
        case .skipped:
            stat.skippedCount += 1
        case .hard:
            stat.learned = false
        }

        stats[key] = stat
    }

    public mutating func recordSeen(dictionaryID: String, term: String, at date: Date = Date()) {
        let key = WordStat.key(dictionaryID: dictionaryID, term: term)
        var stat = stats[key] ?? WordStat()
        if stat.lastFeedbackAt == nil, stat.lastAction != nil {
            stat.lastFeedbackAt = stat.updatedAt
        }
        stat.seenCount += 1
        stat.lastSeenAt = date
        stat.updatedAt = date
        stats[key] = stat
    }
}

public enum LearningSync {
    public static func merge(local: [String: WordStat], remote: [String: WordStat]) -> [String: WordStat] {
        var merged = local
        for (key, remoteStat) in remote {
            if let localStat = merged[key] {
                merged[key] = localStat.merged(with: remoteStat)
            } else {
                merged[key] = remoteStat
            }
        }
        return merged
    }
}

public enum VocabularyPicker {
    public static func scopedEntries(from packs: [DictionaryPack], enabledIDs: Set<String>) -> [ScopedDictionaryEntry] {
        packs
            .filter { enabledIDs.contains($0.id) }
            .flatMap { pack in
                pack.entries.map {
                    ScopedDictionaryEntry(dictionaryID: pack.id, dictionaryName: pack.name, entry: $0)
                }
            }
    }

    public static func weight(for stat: WordStat?) -> Double {
        guard let stat else { return 1.0 }
        var weight = 1.0
        if stat.learned {
            weight *= 0.18
        }
        if stat.unknownCount > 0 && !stat.learned {
            weight *= 1.8 + Double(min(stat.unknownCount, 5)) * 0.45
        }
        if stat.skippedCount > 0 {
            weight *= max(0.12, 0.72 - Double(stat.skippedCount) * 0.14)
        }
        if stat.seenCount > 4 {
            weight *= 0.76
        }
        return max(0.05, weight)
    }

    public static func pick(
        from entries: [ScopedDictionaryEntry],
        stats: [String: WordStat],
        random: Double = Double.random(in: 0..<1)
    ) -> ScopedDictionaryEntry? {
        guard !entries.isEmpty else { return nil }
        let weighted = entries.map { entry in
            (entry, weight(for: stats[entry.statKey]))
        }
        let total = weighted.reduce(0) { $0 + $1.1 }
        var cursor = min(max(random, 0), 0.999_999) * total
        for item in weighted {
            cursor -= item.1
            if cursor <= 0 {
                return item.0
            }
        }
        return weighted.last?.0
    }
}
