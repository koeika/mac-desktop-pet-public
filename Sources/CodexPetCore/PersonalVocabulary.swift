import Foundation

public struct CapturePayload: Codable, Equatable {
    public var term: String
    public var language: String = "en"
    public var phoneticUS: String?
    public var phoneticUK: String?
    public var meaning: String = ""
    public var example: String?
    public var exampleTranslation: String?
    public var hint: String?
    public var sourceURL: String?
    public var sourceTitle: String?

    public init(term: String, language: String = "en", meaning: String = "") {
        self.term = term; self.language = language; self.meaning = meaning
    }

    enum CodingKeys: String, CodingKey {
        case term, language, phoneticUS, phoneticUK, meaning, example, exampleTranslation, hint, sourceURL, sourceTitle
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        term = try c.decode(String.self, forKey: .term)
        language = try c.decodeIfPresent(String.self, forKey: .language) ?? "en"
        meaning = try c.decodeIfPresent(String.self, forKey: .meaning) ?? ""
        phoneticUS = try c.decodeIfPresent(String.self, forKey: .phoneticUS)
        phoneticUK = try c.decodeIfPresent(String.self, forKey: .phoneticUK)
        example = try c.decodeIfPresent(String.self, forKey: .example)
        exampleTranslation = try c.decodeIfPresent(String.self, forKey: .exampleTranslation)
        hint = try c.decodeIfPresent(String.self, forKey: .hint)
        sourceURL = try c.decodeIfPresent(String.self, forKey: .sourceURL)
        sourceTitle = try c.decodeIfPresent(String.self, forKey: .sourceTitle)
    }

    public func validated() throws -> CapturePayload {
        var value = self
        value.term = term.trimmingCharacters(in: .whitespacesAndNewlines).precomposedStringWithCanonicalMapping
        value.language = language.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        value.meaning = meaning.trimmingCharacters(in: .whitespacesAndNewlines)
        func optional(_ text: String?) -> String? {
            guard let clean = text?.trimmingCharacters(in: .whitespacesAndNewlines), !clean.isEmpty else { return nil }
            return clean
        }
        value.phoneticUS = optional(phoneticUS)
        value.phoneticUK = optional(phoneticUK)
        value.example = optional(example)
        value.exampleTranslation = optional(exampleTranslation)
        value.hint = optional(hint)
        value.sourceURL = optional(sourceURL)
        value.sourceTitle = optional(sourceTitle)
        guard !value.term.isEmpty, value.term.count <= 120,
              value.term.rangeOfCharacter(from: .controlCharacters) == nil,
              ["en", "ja", "other"].contains(value.language) else {
            throw CaptureError.invalid("请输入有效单词或短语（最多 120 字），语言请选择 en、ja 或 other。")
        }
        let fields = [meaning, phoneticUS, phoneticUK, example, exampleTranslation, hint, sourceURL, sourceTitle]
        guard fields.allSatisfy({ ($0?.count ?? 0) <= 8000 }) else {
            throw CaptureError.invalid("单个词条字段最多 8000 字。")
        }
        if let raw = value.sourceURL {
            guard let url = URL(string: raw), ["http", "https"].contains(url.scheme?.lowercased() ?? ""), url.host != nil else {
                throw CaptureError.invalid("来源网址必须是 http 或 https 链接。")
            }
        }
        return value
    }
}

public enum CaptureError: LocalizedError {
    case invalid(String)
    public var errorDescription: String? { if case .invalid(let message) = self { return message }; return nil }
}

public struct VocabularyContext: Codable, Equatable {
    public var example: String?
    public var translation: String?
    public var url: String?
    public var title: String?
}

public struct CapturedWord: Codable, Equatable, Identifiable {
    public var id: String
    public var content: CapturePayload
    public var createdAt: Date
    public var updatedAt: Date
    public var contexts: [VocabularyContext]
    public var dictionaryID: String { "personal-\(content.language)" }
    public var statKey: String { WordStat.key(dictionaryID: dictionaryID, term: content.term) }
    public var entry: DictionaryEntry {
        let phonetics = [content.phoneticUK.map { "UK \($0)" }, content.phoneticUS.map { "US \($0)" }].compactMap { $0 }.joined(separator: " · ")
        let example = [content.example, content.exampleTranslation].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: "\n")
        return DictionaryEntry(term: content.term, phonetic: phonetics.isEmpty ? nil : phonetics,
            meaning: content.meaning, example: example.isEmpty ? nil : example, hint: content.hint, tags: ["收藏", content.language])
    }
}

public struct PersonalVocabulary: Codable, Equatable {
    public var words: [CapturedWord] = []
    public init() {}

    @discardableResult
    public mutating func capture(_ payload: CapturePayload, now: Date = Date()) throws -> CapturedWord {
        let content = try payload.validated()
        let context = VocabularyContext(example: content.example, translation: content.exampleTranslation,
            url: content.sourceURL, title: content.sourceTitle)
        if let index = words.firstIndex(where: {
            $0.content.language == content.language && $0.content.term.lowercased() == content.term.lowercased()
        }) {
            var word = words[index]
            word.updatedAt = now
            if !word.contexts.contains(context) { word.contexts.append(context) }
            // A lookup with empty fields must never erase an existing definition.
            if !content.meaning.isEmpty { word.content.meaning = content.meaning }
            if let value = content.phoneticUS, !value.isEmpty { word.content.phoneticUS = value }
            if let value = content.phoneticUK, !value.isEmpty { word.content.phoneticUK = value }
            if let value = content.example, !value.isEmpty { word.content.example = value }
            if let value = content.exampleTranslation, !value.isEmpty { word.content.exampleTranslation = value }
            if let value = content.hint, !value.isEmpty { word.content.hint = value }
            if let value = content.sourceURL, !value.isEmpty { word.content.sourceURL = value }
            if let value = content.sourceTitle, !value.isEmpty { word.content.sourceTitle = value }
            words[index] = word
            return word
        }
        let word = CapturedWord(id: UUID().uuidString, content: content, createdAt: now, updatedAt: now, contexts: [context])
        words.append(word)
        return word
    }

    public var packs: [DictionaryPack] {
        Dictionary(grouping: words, by: \.dictionaryID).map { id, words in
            let name = id == "personal-ja" ? "我的生词本 · 日语" : (id == "personal-en" ? "我的生词本 · 英语" : "我的生词本 · 其他")
            return DictionaryPack(id: id, name: name, entries: words.map(\.entry))
        }.sorted { $0.id < $1.id }
    }
}
