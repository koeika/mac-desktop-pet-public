import Foundation

public struct DictionaryEntry: Codable, Hashable, Equatable {
    public var term: String
    public var reading: String?
    public var phonetic: String?
    public var meaning: String
    public var example: String?
    public var hint: String?
    public var tags: [String]

    public init(
        term: String,
        reading: String? = nil,
        phonetic: String? = nil,
        meaning: String,
        example: String? = nil,
        hint: String? = nil,
        tags: [String] = []
    ) {
        self.term = term
        self.reading = reading
        self.phonetic = phonetic
        self.meaning = meaning
        self.example = example
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
}

public struct WordStat: Codable, Equatable {
    public var learned: Bool
    public var unknownCount: Int
    public var skippedCount: Int
    public var seenCount: Int
    public var lastAction: WordAction?
    public var updatedAt: Date

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
        let latest = updatedAt >= other.updatedAt ? self : other
        return WordStat(
            learned: learned || other.learned,
            unknownCount: max(unknownCount, other.unknownCount),
            skippedCount: max(skippedCount, other.skippedCount),
            seenCount: max(seenCount, other.seenCount),
            lastAction: latest.lastAction,
            updatedAt: max(updatedAt, other.updatedAt)
        )
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
        stat.seenCount += 1
        stat.lastAction = action
        stat.updatedAt = date

        switch action {
        case .known:
            stat.learned = true
        case .unknown:
            stat.learned = false
            stat.unknownCount += 1
        case .skipped:
            stat.skippedCount += 1
        }

        stats[key] = stat
    }

    public mutating func recordSeen(dictionaryID: String, term: String, at date: Date = Date()) {
        let key = WordStat.key(dictionaryID: dictionaryID, term: term)
        var stat = stats[key] ?? WordStat()
        stat.seenCount += 1
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
