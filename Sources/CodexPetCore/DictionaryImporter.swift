import Foundation

public enum DictionaryImportError: Error, LocalizedError {
    case unsupportedFormat(String)
    case missingRequiredColumns
    case invalidJSON

    public var errorDescription: String? {
        switch self {
        case .unsupportedFormat(let format):
            return "Unsupported dictionary format: \(format)"
        case .missingRequiredColumns:
            return "Dictionary CSV needs at least term and meaning columns."
        case .invalidJSON:
            return "Dictionary JSON could not be decoded."
        }
    }
}

public enum DictionaryImporter {
    public static func importPacks(data: Data, fileName: String) throws -> [DictionaryPack] {
        let ext = URL(fileURLWithPath: fileName).pathExtension.lowercased()
        switch ext {
        case "json":
            return try importJSON(data: data, fileName: fileName)
        case "csv":
            return try importCSV(data: data, fileName: fileName)
        default:
            throw DictionaryImportError.unsupportedFormat(ext)
        }
    }

    public static func importJSON(data: Data, fileName: String) throws -> [DictionaryPack] {
        let decoder = JSONDecoder()
        if let pack = try? decoder.decode(DictionaryPack.self, from: data) {
            return [pack]
        }
        if let packs = try? decoder.decode([DictionaryPack].self, from: data) {
            return packs
        }
        if let entries = try? decoder.decode([DictionaryEntry].self, from: data) {
            return [DictionaryPack(
                id: slug(fileNameWithoutExtension(fileName)),
                name: fileNameWithoutExtension(fileName),
                entries: entries
            )]
        }
        throw DictionaryImportError.invalidJSON
    }

    public static func importCSV(data: Data, fileName: String) throws -> [DictionaryPack] {
        guard let text = String(data: data, encoding: .utf8) else {
            throw DictionaryImportError.unsupportedFormat("csv")
        }
        let rows = parseCSV(text)
        guard let header = rows.first?.map({ normalizeHeader($0) }) else {
            throw DictionaryImportError.missingRequiredColumns
        }
        guard let termIndex = header.firstIndex(of: "term"),
              let meaningIndex = header.firstIndex(of: "meaning") else {
            throw DictionaryImportError.missingRequiredColumns
        }

        let dictionaryNameIndex = header.firstIndex(of: "dictionaryname")
        var grouped: [String: [DictionaryEntry]] = [:]
        for row in rows.dropFirst() where row.count > max(termIndex, meaningIndex) {
            let term = cell(row, termIndex)
            let meaning = cell(row, meaningIndex)
            guard !term.isEmpty, !meaning.isEmpty else { continue }
            let name = dictionaryNameIndex.map { cell(row, $0) }.flatMap { $0.isEmpty ? nil : $0 }
                ?? fileNameWithoutExtension(fileName)
            grouped[name, default: []].append(DictionaryEntry(
                term: term,
                reading: header.firstIndex(of: "reading").map { cell(row, $0) }.nilIfBlank,
                phonetic: header.firstIndex(of: "phonetic").map { cell(row, $0) }.nilIfBlank,
                meaning: meaning,
                example: header.firstIndex(of: "example").map { cell(row, $0) }.nilIfBlank,
                hint: header.firstIndex(of: "hint").map { cell(row, $0) }.nilIfBlank,
                tags: header.firstIndex(of: "tags").map { cell(row, $0).split(separator: "|").map(String.init) } ?? []
            ))
        }

        return grouped
            .sorted { $0.key < $1.key }
            .map { name, entries in
                DictionaryPack(id: slug(name), name: name, entries: entries)
            }
    }

    public static func parseCSV(_ text: String) -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var insideQuotes = false
        var index = text.startIndex

        while index < text.endIndex {
            let char = text[index]
            if char == "\"" {
                let next = text.index(after: index)
                if insideQuotes, next < text.endIndex, text[next] == "\"" {
                    field.append("\"")
                    index = next
                } else {
                    insideQuotes.toggle()
                }
            } else if char == "," && !insideQuotes {
                row.append(field.trimmingCharacters(in: .whitespacesAndNewlines))
                field = ""
            } else if (char == "\n" || char == "\r") && !insideQuotes {
                if char == "\r" {
                    let next = text.index(after: index)
                    if next < text.endIndex, text[next] == "\n" {
                        index = next
                    }
                }
                row.append(field.trimmingCharacters(in: .whitespacesAndNewlines))
                if row.contains(where: { !$0.isEmpty }) {
                    rows.append(row)
                }
                row = []
                field = ""
            } else {
                field.append(char)
            }
            index = text.index(after: index)
        }

        row.append(field.trimmingCharacters(in: .whitespacesAndNewlines))
        if row.contains(where: { !$0.isEmpty }) {
            rows.append(row)
        }
        return rows
    }

    private static func cell(_ row: [String], _ index: Int) -> String {
        guard row.indices.contains(index) else { return "" }
        return row[index].trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func normalizeHeader(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "_", with: "")
    }

    private static func fileNameWithoutExtension(_ fileName: String) -> String {
        URL(fileURLWithPath: fileName).deletingPathExtension().lastPathComponent
    }

    public static func slug(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let folded = value.folding(options: [.diacriticInsensitive, .widthInsensitive], locale: .current)
        let scalars = folded.unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" }
        let slug = String(scalars).lowercased()
            .split(separator: "-")
            .joined(separator: "-")
        return slug.isEmpty ? UUID().uuidString : slug
    }
}

private extension Optional where Wrapped == String {
    var nilIfBlank: String? {
        guard let value = self?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else {
            return nil
        }
        return value
    }
}

