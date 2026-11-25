import Foundation
import CodexPetCore

struct VocabularyLookupRequest: Decodable {
    var word: CapturePayload
    var allowAI: Bool = false
}

struct VocabularyLookupResponse: Encodable {
    var ok = true
    var word: CapturePayload
    var source: String
    var saved: Bool
    var warning: String?
}

extension AppDataStore {
    @MainActor func lookupVocabulary(_ data: Data, enrichment: ((CapturePayload, String) async throws -> CapturePayload)? = nil) async throws -> Data {
        let request = try JSONFileStore.decoder.decode(VocabularyLookupRequest.self, from: data)
        var word = try request.word.validated()
        if word.example?.trimmingCharacters(in: .whitespacesAndNewlines).caseInsensitiveCompare(word.term) == .orderedSame {
            word.example = nil
        }
        let saved = personalVocabulary.words.first {
            $0.content.language == word.language && $0.content.term.caseInsensitiveCompare(word.term) == .orderedSame
        }
        var source = "none"
        var warning: String?
        if let existing = saved {
            let context = word.example
            let url = word.sourceURL
            let title = word.sourceTitle
            word = existing.content
            if let context, context != word.example { word.example = context; word.exampleTranslation = nil }
            word.sourceURL = url ?? word.sourceURL
            word.sourceTitle = title ?? word.sourceTitle
            source = "notebook"
        } else if let entry = dictionaries.flatMap(\.entries).first(where: {
            $0.term.caseInsensitiveCompare(word.term) == .orderedSame &&
            (word.language == "ja" ? $0.term.range(of: "[ぁ-んァ-ン一-龯]", options: .regularExpression) != nil : $0.term.range(of: "[A-Za-z]", options: .regularExpression) != nil)
        }) {
            word.meaning = entry.meaning
            word.phoneticUK = entry.phonetic ?? entry.reading
            if word.example == nil || word.example == entry.example {
                word.example = entry.example
                word.exampleTranslation = entry.exampleTranslation
            }
            word.hint = entry.hint
            source = "dictionary"
        }
        if request.allowAI && (word.meaning.isEmpty || word.phoneticUK == nil || (word.language == "en" && word.phoneticUS == nil) || word.example == nil || word.exampleTranslation == nil) {
            do {
                if let enrichment {
                    word = try await enrichment(word, word.example ?? "")
                } else {
                    word = try await enrichCapturedWord(word, copiedText: word.example ?? "")
                }
                source = "deepseek"
            } catch {
                warning = "自动补全暂不可用：\(error.localizedDescription) 可先收藏单词，稍后重试。"
            }
        }
        return try JSONFileStore.encoder.encode(VocabularyLookupResponse(word: word, source: source, saved: saved != nil, warning: warning))
    }

    @MainActor func translatedExample(for entry: DictionaryEntry) async throws -> String? {
        guard let example = entry.example, !example.isEmpty else { return nil }
        var word = CapturePayload(term: entry.term, language: entry.term.range(of: "[ぁ-んァ-ン]", options: .regularExpression) == nil ? "en" : "ja", meaning: entry.meaning)
        word.example = example
        let result = try await enrichCapturedWord(word, copiedText: example)
        return result.exampleTranslation
    }
}
