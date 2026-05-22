import Foundation

public struct GeneratedDictionaryExample: Codable, Equatable {
    public var term: String
    public var example: String
    public var hint: String?

    public init(term: String, example: String, hint: String? = nil) {
        self.term = term
        self.example = example
        self.hint = hint
    }
}

public enum ExampleProvider: String, Codable, CaseIterable, Equatable, Identifiable {
    case openAI
    case deepSeek

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .openAI: return "OpenAI"
        case .deepSeek: return "DeepSeek"
        }
    }

    public var defaultModel: String {
        switch self {
        case .openAI: return "gpt-5.2"
        case .deepSeek: return "deepseek-chat"
        }
    }

    public var defaultBaseURL: String {
        switch self {
        case .openAI: return "https://api.openai.com"
        case .deepSeek: return "https://api.deepseek.com"
        }
    }
}

public enum ExampleGeneratorError: LocalizedError {
    case missingAPIKey
    case invalidResponse
    case httpError(Int, String)

    public var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "请先在配置中心保存当前供应商的 API key。"
        case .invalidResponse:
            return "模型返回内容无法解析为例句 JSON。"
        case .httpError(let status, let body):
            return "例句生成 API 返回 HTTP \(status)：\(body.prefix(240))"
        }
    }
}

public enum ExampleGenerator {
    public static func buildRequestBody(
        entries: [DictionaryImportDraftEntry],
        model: String,
        provider: ExampleProvider = .openAI
    ) throws -> Data {
        switch provider {
        case .openAI:
            return try buildOpenAIResponsesRequestBody(entries: entries, model: model)
        case .deepSeek:
            return try buildChatCompletionsRequestBody(entries: entries, model: model)
        }
    }

    public static func buildOpenAIResponsesRequestBody(
        entries: [DictionaryImportDraftEntry],
        model: String
    ) throws -> Data {
        let minimalEntries = entries.map { entry in
            [
                "term": entry.term,
                "reading": entry.reading ?? "",
                "phonetic": entry.phonetic ?? "",
                "meaning": entry.meaning,
                "context": String(entry.context.prefix(180))
            ]
        }

        let schema: [String: Any] = [
            "type": "object",
            "additionalProperties": false,
            "required": ["examples"],
            "properties": [
                "examples": [
                    "type": "array",
                    "items": [
                        "type": "object",
                        "additionalProperties": false,
                        "required": ["term", "example", "hint"],
                        "properties": [
                            "term": ["type": "string"],
                            "example": ["type": "string"],
                            "hint": ["type": "string"]
                        ]
                    ]
                ]
            ]
        ]

        let body: [String: Any] = [
            "model": model.isEmpty ? "gpt-5.2" : model,
            "instructions": "You generate concise, original dictionary example sentences. Return JSON only. Do not copy long source text.",
            "input": [
                [
                    "role": "user",
                    "content": [
                        [
                            "type": "input_text",
                            "text": "Generate one short example sentence and one brief study hint for each dictionary entry. Use the term naturally. Entries: \(jsonString(minimalEntries))"
                        ]
                    ]
                ]
            ],
            "text": [
                "format": [
                    "type": "json_schema",
                    "name": "dictionary_examples",
                    "strict": true,
                    "schema": schema
                ]
            ]
        ]

        return try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
    }

    public static func buildChatCompletionsRequestBody(
        entries: [DictionaryImportDraftEntry],
        model: String
    ) throws -> Data {
        let minimalEntries = entries.map { entry in
            [
                "term": entry.term,
                "reading": entry.reading ?? "",
                "phonetic": entry.phonetic ?? "",
                "meaning": entry.meaning,
                "context": String(entry.context.prefix(180))
            ]
        }
        let body: [String: Any] = [
            "model": model.isEmpty ? ExampleProvider.deepSeek.defaultModel : model,
            "response_format": ["type": "json_object"],
            "messages": [
                [
                    "role": "system",
                    "content": "You generate concise, original dictionary example sentences. Return only JSON with this shape: {\"examples\":[{\"term\":\"...\",\"example\":\"...\",\"hint\":\"...\"}]}. Do not copy long source text."
                ],
                [
                    "role": "user",
                    "content": "Generate one short example sentence and one brief study hint for each dictionary entry. Use the term naturally. Entries: \(jsonString(minimalEntries))"
                ]
            ]
        ]
        return try JSONSerialization.data(withJSONObject: body, options: [.sortedKeys])
    }

    public static func generateExamples(
        entries: [DictionaryImportDraftEntry],
        apiKey: String,
        model: String,
        provider: ExampleProvider,
        baseURL: String? = nil
    ) async throws -> [GeneratedDictionaryExample] {
        guard !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ExampleGeneratorError.missingAPIKey
        }
        let body = try buildRequestBody(entries: entries, model: model, provider: provider)
        var request = URLRequest(url: endpointURL(provider: provider, baseURL: baseURL))
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body

        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw ExampleGeneratorError.httpError(http.statusCode, body)
        }
        return try parseResponse(data, provider: provider)
    }

    public static func parseResponse(_ data: Data, provider: ExampleProvider = .openAI) throws -> [GeneratedDictionaryExample] {
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let outputText = extractOutputText(from: object, provider: provider),
              let jsonData = outputText.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(GeneratedExamplesEnvelope.self, from: jsonData) else {
            throw ExampleGeneratorError.invalidResponse
        }
        return decoded.examples
    }

    private static func endpointURL(provider: ExampleProvider, baseURL: String?) -> URL {
        let root = (baseURL?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? provider.defaultBaseURL)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        switch provider {
        case .openAI:
            return URL(string: "\(root)/v1/responses")!
        case .deepSeek:
            return URL(string: "\(root)/chat/completions")!
        }
    }

    private static func extractOutputText(from object: [String: Any], provider: ExampleProvider) -> String? {
        if provider == .deepSeek {
            let choices = object["choices"] as? [[String: Any]]
            let message = choices?.first?["message"] as? [String: Any]
            return message?["content"] as? String
        }
        if let outputText = object["output_text"] as? String {
            return outputText
        }
        guard let output = object["output"] as? [[String: Any]] else { return nil }
        for item in output {
            guard let content = item["content"] as? [[String: Any]] else { continue }
            for block in content {
                if let text = block["text"] as? String {
                    return text
                }
            }
        }
        return nil
    }

    private static func jsonString(_ value: Any) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]),
              let text = String(data: data, encoding: .utf8) else {
            return "[]"
        }
        return text
    }
}

private struct GeneratedExamplesEnvelope: Codable {
    var examples: [GeneratedDictionaryExample]
}

public typealias OpenAIExampleGenerator = ExampleGenerator

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
