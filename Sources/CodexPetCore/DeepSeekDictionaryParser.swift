import Foundation

public enum DeepSeekDictionaryParserError: LocalizedError {
    case missingAPIKey
    case emptySourceText
    case invalidResponse
    case httpError(Int, String)

    public var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "请先在配置中心保存 DeepSeek API key。"
        case .emptySourceText:
            return "当前 PDF 没有可发送给 DeepSeek 的可选择文本。扫描版 PDF 仍需要 OCR。"
        case .invalidResponse:
            return "DeepSeek 返回内容无法解析为词典 JSON。"
        case .httpError(let status, let body):
            return "DeepSeek 解析 PDF 返回 HTTP \(status)：\(body.prefix(240))"
        }
    }
}

public enum DeepSeekDictionaryParser {
    public static func buildRequestBody(
        sourceText: String,
        fileName: String,
        dictionaryName: String,
        model: String
    ) throws -> Data {
        let text = sourceText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            throw DeepSeekDictionaryParserError.emptySourceText
        }

        let body: [String: Any] = [
            "model": model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? ExampleProvider.deepSeek.defaultModel : model,
            "response_format": ["type": "json_object"],
            "messages": [
                [
                    "role": "system",
                    "content": """
                    You are a strict dictionary table extractor. Return JSON only with this exact shape:
                    {"dictionaryName":"...","entries":[{"term":"...","reading":"...","phonetic":"...","meaning":"...","example":"...","hint":"...","tags":["..."]}]}.

                    Rules:
                    - Extract only real vocabulary entries from the source text.
                    - For Japanese dictionaries, term is the word column, reading is kana/romaji pronunciation, meaning is the Chinese definition.
                    - [形], [名], [名・形], [慣用], etc. are part-of-speech markers. Keep them in meaning; never put them in reading or phonetic.
                    - Do not use row numbers, page numbers, headers, footers, or source artifacts as terms.
                    - If columns are interleaved or text order is broken, reconstruct entries by meaning and context.
                    - Use empty strings for missing reading, phonetic, example, or hint.
                    - Preserve examples only if they appear in the source text; do not invent examples.
                    """
                ],
                [
                    "role": "user",
                    "content": """
                    File: \(fileName)
                    Preferred dictionaryName: \(dictionaryName)

                    Extract vocabulary entries from this PDF text:
                    \(sourceTextForPrompt(text))
                    """
                ]
            ]
        ]

        return try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
    }

    public static func parseDictionary(
        sourceText: String,
        fileName: String,
        dictionaryName: String,
        apiKey: String,
        model: String,
        baseURL: String
    ) async throws -> DictionaryImportDraft {
        guard !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw DeepSeekDictionaryParserError.missingAPIKey
        }
        let text = sourceText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else {
            throw DeepSeekDictionaryParserError.emptySourceText
        }

        let chunks = chunkSourceText(text)
        var combinedEntries: [DictionaryImportDraftEntry] = []
        var seenTerms = Set<String>()
        var resolvedName = dictionaryName

        for (index, chunk) in chunks.enumerated() {
            let draft = try await parseChunk(
                sourceText: chunk,
                fileName: chunks.count == 1 ? fileName : "\(fileName) part \(index + 1)/\(chunks.count)",
                dictionaryName: resolvedName,
                apiKey: apiKey,
                model: model,
                baseURL: baseURL
            )
            if index == 0, !draft.dictionaryName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                resolvedName = draft.dictionaryName
            }
            for entry in draft.entries {
                let key = entry.term.lowercased()
                guard !key.isEmpty, !seenTerms.contains(key) else { continue }
                seenTerms.insert(key)
                combinedEntries.append(entry)
            }
        }

        guard !combinedEntries.isEmpty else {
            throw DeepSeekDictionaryParserError.invalidResponse
        }

        return DictionaryImportDraft(
            dictionaryName: resolvedName,
            entries: combinedEntries,
            rejectedLines: [],
            sourceFileName: fileName,
            sourceText: sourceText
        )
    }

    public static func parseResponse(
        _ data: Data,
        fileName: String,
        fallbackDictionaryName: String,
        sourceText: String
    ) throws -> DictionaryImportDraft {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = object["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let content = message["content"] as? String,
              let contentData = content.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(AIDictionaryEnvelope.self, from: contentData) else {
            throw DeepSeekDictionaryParserError.invalidResponse
        }

        let entries = decoded.entries.compactMap { entry -> DictionaryImportDraftEntry? in
            let term = entry.term.trimmingCharacters(in: .whitespacesAndNewlines)
            let meaning = entry.meaning.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !term.isEmpty, !meaning.isEmpty else { return nil }
            return DictionaryImportDraftEntry(
                term: term,
                reading: normalizedOptional(entry.reading),
                phonetic: normalizedOptional(entry.phonetic),
                meaning: meaning,
                example: normalizedOptional(entry.example),
                hint: normalizedOptional(entry.hint),
                tags: entry.tags.isEmpty ? ["pdf", "deepseek"] : Array(Set(entry.tags + ["pdf", "deepseek"])).sorted(),
                context: "",
                confidence: 0.92,
                needsReview: false
            )
        }

        guard !entries.isEmpty else {
            throw DeepSeekDictionaryParserError.invalidResponse
        }

        return DictionaryImportDraft(
            dictionaryName: normalizedOptional(decoded.dictionaryName) ?? fallbackDictionaryName,
            entries: entries,
            rejectedLines: [],
            sourceFileName: fileName,
            sourceText: sourceText
        )
    }

    private static func parseChunk(
        sourceText: String,
        fileName: String,
        dictionaryName: String,
        apiKey: String,
        model: String,
        baseURL: String
    ) async throws -> DictionaryImportDraft {
        let body = try buildRequestBody(
            sourceText: sourceText,
            fileName: fileName,
            dictionaryName: dictionaryName,
            model: model
        )
        let root = baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        var request = URLRequest(url: URL(string: "\(root)/chat/completions")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body

        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw DeepSeekDictionaryParserError.httpError(http.statusCode, body)
        }
        return try parseResponse(data, fileName: fileName, fallbackDictionaryName: dictionaryName, sourceText: sourceText)
    }

    private static func sourceTextForPrompt(_ text: String) -> String {
        String(text.prefix(28_000))
    }

    private static func normalizedOptional(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func chunkSourceText(_ text: String) -> [String] {
        let maxCharacters = 28_000
        guard text.count > maxCharacters else { return [text] }

        var chunks: [String] = []
        var current = ""
        for line in text.components(separatedBy: .newlines) {
            if current.count + line.count + 1 > maxCharacters, !current.isEmpty {
                chunks.append(current)
                current = ""
            }
            current += current.isEmpty ? line : "\n\(line)"
        }
        if !current.isEmpty {
            chunks.append(current)
        }
        return chunks
    }
}

private struct AIDictionaryEnvelope: Codable {
    var dictionaryName: String?
    var entries: [AIDictionaryEntry]
}

private struct AIDictionaryEntry: Codable {
    var term: String
    var reading: String?
    var phonetic: String?
    var meaning: String
    var example: String?
    var hint: String?
    var tags: [String]

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        term = try container.decodeIfPresent(String.self, forKey: .term) ?? ""
        reading = try container.decodeIfPresent(String.self, forKey: .reading)
        phonetic = try container.decodeIfPresent(String.self, forKey: .phonetic)
        meaning = try container.decodeIfPresent(String.self, forKey: .meaning) ?? ""
        example = try container.decodeIfPresent(String.self, forKey: .example)
        hint = try container.decodeIfPresent(String.self, forKey: .hint)
        tags = try container.decodeIfPresent([String].self, forKey: .tags) ?? []
    }
}
