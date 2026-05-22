import Foundation
import PDFKit

public struct DictionaryImportDraftEntry: Codable, Identifiable, Equatable {
    public var id: String
    public var term: String
    public var reading: String?
    public var phonetic: String?
    public var meaning: String
    public var example: String?
    public var hint: String?
    public var tags: [String]
    public var context: String
    public var confidence: Double
    public var needsReview: Bool

    public init(
        id: String = UUID().uuidString,
        term: String,
        reading: String? = nil,
        phonetic: String? = nil,
        meaning: String,
        example: String? = nil,
        hint: String? = nil,
        tags: [String] = [],
        context: String,
        confidence: Double,
        needsReview: Bool
    ) {
        self.id = id
        self.term = term
        self.reading = reading
        self.phonetic = phonetic
        self.meaning = meaning
        self.example = example
        self.hint = hint
        self.tags = tags
        self.context = context
        self.confidence = max(0, min(1, confidence))
        self.needsReview = needsReview
    }

    public var dictionaryEntry: DictionaryEntry {
        DictionaryEntry(
            term: term,
            reading: reading,
            phonetic: phonetic,
            meaning: meaning,
            example: example,
            hint: hint,
            tags: tags
        )
    }
}

public struct DictionaryImportDraft: Codable, Identifiable, Equatable {
    public var id: String
    public var dictionaryName: String
    public var entries: [DictionaryImportDraftEntry]
    public var rejectedLines: [String]
    public var sourceFileName: String
    public var sourceText: String?

    public init(
        id: String = UUID().uuidString,
        dictionaryName: String,
        entries: [DictionaryImportDraftEntry],
        rejectedLines: [String] = [],
        sourceFileName: String,
        sourceText: String? = nil
    ) {
        self.id = id
        self.dictionaryName = dictionaryName
        self.entries = entries
        self.rejectedLines = rejectedLines
        self.sourceFileName = sourceFileName
        self.sourceText = sourceText
    }

    public var pack: DictionaryPack {
        DictionaryPack(
            id: DictionaryImporter.slug(dictionaryName),
            name: dictionaryName,
            description: "从 PDF 半自动导入",
            entries: entries
                .filter { !$0.term.isEmpty && !$0.meaning.isEmpty }
                .map(\.dictionaryEntry)
        )
    }
}

public enum PDFDictionaryImportError: LocalizedError {
    case noSelectableText
    case noEntries

    public var errorDescription: String? {
        switch self {
        case .noSelectableText:
            return "这个 PDF 没有可选择文本。扫描版图片 PDF v1 暂不支持 OCR。"
        case .noEntries:
            return "没有从 PDF 文本中识别到可导入词条，请检查版式或改用 CSV/JSON。"
        }
    }
}

public enum PDFDictionaryImporter {
    public static func draft(fromPDF url: URL) throws -> DictionaryImportDraft {
        guard let document = PDFDocument(url: url) else {
            throw PDFDictionaryImportError.noSelectableText
        }

        var layoutPages: [String] = []
        var fallbackPages: [String] = []
        for index in 0..<document.pageCount {
            guard let page = document.page(at: index) else { continue }
            let layoutText = layoutLines(from: page).joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            if !layoutText.isEmpty {
                layoutPages.append(layoutText)
            }
            if let text = page.string?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty {
                fallbackPages.append(text)
            }
        }

        let text = layoutPages.isEmpty ? fallbackPages.joined(separator: "\n") : layoutPages.joined(separator: "\n")
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw PDFDictionaryImportError.noSelectableText
        }
        return try draft(fromText: text, fileName: url.lastPathComponent)
    }

    public static func draft(fromText text: String, fileName: String) throws -> DictionaryImportDraft {
        let dictionaryName = URL(fileURLWithPath: fileName).deletingPathExtension().lastPathComponent
        var entries: [DictionaryImportDraftEntry] = []
        var rejected: [String] = []
        var seenTerms = Set<String>()

        let lines = normalizedLines(from: text)

        for line in lines {
            if isLikelyNoise(line) {
                continue
            }
            guard let parsed = parseLine(line) else {
                if rejected.count < 80 {
                    rejected.append(line)
                }
                continue
            }
            let key = parsed.term.lowercased()
            guard !seenTerms.contains(key) else { continue }
            seenTerms.insert(key)
            entries.append(parsed)
        }

        guard !entries.isEmpty else {
            throw PDFDictionaryImportError.noEntries
        }

        return DictionaryImportDraft(
            dictionaryName: dictionaryName,
            entries: entries,
            rejectedLines: rejected,
            sourceFileName: fileName,
            sourceText: text
        )
    }

    private struct PositionedCharacter {
        var text: String
        var bounds: CGRect
    }

    private struct PositionedLine {
        var midY: CGFloat
        var characters: [PositionedCharacter]
    }

    private static func layoutLines(from page: PDFPage) -> [String] {
        guard let rawText = page.string, !rawText.isEmpty else { return [] }
        let nsText = rawText as NSString
        let count = min(page.numberOfCharacters, nsText.length)
        guard count > 0 else { return [] }

        var characters: [PositionedCharacter] = []
        characters.reserveCapacity(count)
        for index in 0..<count {
            let value = nsText.substring(with: NSRange(location: index, length: 1))
            guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
            let bounds = page.characterBounds(at: index)
            guard bounds.width > 0.1, bounds.height > 0.1, isFinite(bounds) else { continue }
            characters.append(PositionedCharacter(text: value, bounds: bounds))
        }
        guard !characters.isEmpty else { return [] }

        let medianHeight = median(characters.map(\.bounds.height))
        let yTolerance = max(3, medianHeight * 0.58)
        var positionedLines: [PositionedLine] = []

        for character in characters.sorted(by: { lhs, rhs in
            let yDelta = lhs.bounds.midY - rhs.bounds.midY
            if abs(yDelta) > yTolerance {
                return lhs.bounds.midY > rhs.bounds.midY
            }
            return lhs.bounds.minX < rhs.bounds.minX
        }) {
            if let index = positionedLines.indices.min(by: {
                abs(positionedLines[$0].midY - character.bounds.midY) < abs(positionedLines[$1].midY - character.bounds.midY)
            }), abs(positionedLines[index].midY - character.bounds.midY) <= yTolerance {
                let line = positionedLines[index]
                let count = CGFloat(line.characters.count)
                positionedLines[index].midY = ((line.midY * count) + character.bounds.midY) / (count + 1)
                positionedLines[index].characters.append(character)
            } else {
                positionedLines.append(PositionedLine(midY: character.bounds.midY, characters: [character]))
            }
        }

        return positionedLines
            .sorted { $0.midY > $1.midY }
            .map(renderLine)
            .map(cleanLine)
            .filter { !$0.isEmpty }
    }

    private static func renderLine(_ line: PositionedLine) -> String {
        let sortedCharacters = line.characters.sorted { $0.bounds.minX < $1.bounds.minX }
        let medianWidth = median(sortedCharacters.map(\.bounds.width))
        let spaceThreshold = max(2.5, medianWidth * 0.75)
        let columnThreshold = max(13, medianWidth * 3.8)
        var rendered = ""
        var previousMaxX: CGFloat?

        for character in sortedCharacters {
            if let previousMaxX {
                let gap = character.bounds.minX - previousMaxX
                if gap > columnThreshold {
                    rendered.append("\t")
                } else if gap > spaceThreshold, !rendered.hasSuffix(" "), !rendered.hasSuffix("\t") {
                    rendered.append(" ")
                }
            }
            rendered.append(character.text)
            previousMaxX = max(previousMaxX ?? character.bounds.maxX, character.bounds.maxX)
        }

        return rendered
    }

    private static func normalizedLines(from text: String) -> [String] {
        let cleaned = text
            .components(separatedBy: .newlines)
            .map(cleanLine)
            .filter { !$0.isEmpty }
            .filter { !isLikelyNoise($0) }

        var merged: [String] = []
        for line in cleaned {
            if shouldMergeWithPrevious(line), !merged.isEmpty {
                merged[merged.count - 1] += " " + line
            } else {
                merged.append(line)
            }
        }
        return merged
    }

    private static func shouldMergeWithPrevious(_ line: String) -> Bool {
        if startsNumberedEntry(line) { return false }
        if startsDictionaryEntry(line) { return false }
        return true
    }

    private static func startsNumberedEntry(_ line: String) -> Bool {
        matches(pattern: #"^\s*\d{1,4}[\s\.、\)、\)]+"#, in: line)
    }

    private static func startsDictionaryEntry(_ line: String) -> Bool {
        matches(
            pattern: #"^([A-Za-z][A-Za-z'\-]{1,42}|[\p{Han}\p{Hiragana}\p{Katakana}ー]{1,24})\s+.{1,}$"#,
            in: line
        )
    }

    private static func parseLine(_ line: String) -> DictionaryImportDraftEntry? {
        if let numbered = parseNumberedTableLine(line) {
            return numbered
        }
        return parseDictionaryLine(line, forceReview: false)
    }

    private static func parseNumberedTableLine(_ line: String) -> DictionaryImportDraftEntry? {
        guard let numbered = firstMatch(pattern: #"^\s*\d{1,4}[\s\.、\)、\)]*(.+)$"#, in: line),
              let remainder = numbered.first,
              !remainder.isEmpty else {
            return nil
        }

        let pieces = remainder.split(maxSplits: 2, whereSeparator: \.isWhitespace).map(String.init)
        if pieces.count == 3,
           looksLikeReadingToken(pieces[0], term: pieces[1]),
           isUsefulTerm(pieces[1]) {
            let meaning = normalizeMeaning(pieces[2])
            guard isUsefulMeaning(meaning) else { return nil }
            let confidence = min(0.98, confidenceScore(term: pieces[1], pronunciation: pieces[0], meaning: meaning) + 0.08)
            return DictionaryImportDraftEntry(
                term: pieces[1],
                reading: pieces[0],
                meaning: meaning,
                tags: ["pdf"],
                context: String(line.prefix(240)),
                confidence: confidence,
                needsReview: confidence < 0.72
            )
        }

        return parseDictionaryLine(remainder, forceReview: true)
    }

    private static func parseDictionaryLine(_ line: String, forceReview: Bool) -> DictionaryImportDraftEntry? {
        let pattern = #"^([A-Za-z][A-Za-z'\-]{1,42}|[\p{Han}\p{Hiragana}\p{Katakana}ー]{1,24})\s*(\[[^\]]+\]|/[^/]+/|（[^）]+）|\([^)]+\))?\s+(.{2,})$"#
        guard let match = firstMatch(pattern: pattern, in: line) else {
            return parseLooseLine(line)
        }
        var term = match[0]
        var meaningText = match.indices.contains(2) ? match[2] : ""
        var pronunciationText = match.indices.contains(1) ? match[1] : ""

        var repairedReading: String?
        if let repair = repairMisplacedReadingAndTerm(term: term, meaningText: meaningText) {
            term = repair.term
            repairedReading = repair.reading
            meaningText = repair.meaningText
        }

        if isPartOfSpeechMarker(pronunciationText) {
            meaningText = "\(pronunciationText) \(meaningText)"
            pronunciationText = ""
        } else if pronunciationText.isEmpty,
           let extracted = extractLeadingPronunciation(from: meaningText) {
            if isPartOfSpeechMarker(extracted.pronunciation) {
                meaningText = "\(extracted.pronunciation) \(extracted.remainder)"
            } else {
                pronunciationText = extracted.pronunciation
                meaningText = extracted.remainder
            }
        }
        var reading: String?
        var phonetic: String?
        if let repairedReading {
            reading = repairedReading
        } else if !pronunciationText.isEmpty {
            let pronunciation = pronunciationText.trimmingCharacters(in: CharacterSet(charactersIn: "[]/()（） "))
            if containsJapanese(term) {
                reading = pronunciation
            } else {
                phonetic = pronunciation
            }
        }
        let meaning = normalizeMeaning(meaningText)
        guard isUsefulTerm(term), isUsefulMeaning(meaning) else { return nil }

        let confidence = confidenceScore(term: term, pronunciation: phonetic ?? reading, meaning: meaning)
        return DictionaryImportDraftEntry(
            term: term,
            reading: reading.nilIfBlank,
            phonetic: phonetic.nilIfBlank,
            meaning: meaning,
            tags: ["pdf"],
            context: String(line.prefix(240)),
            confidence: confidence,
            needsReview: forceReview || confidence < 0.72
        )
    }

    private static func parseLooseLine(_ line: String) -> DictionaryImportDraftEntry? {
        let pieces = line.split(maxSplits: 1, whereSeparator: \.isWhitespace)
        guard pieces.count == 2 else { return nil }
        var term = String(pieces[0])
        var meaningText = String(pieces[1])
        var reading: String?
        var phonetic: String?
        if let repair = repairMisplacedReadingAndTerm(term: term, meaningText: meaningText) {
            term = repair.term
            reading = repair.reading
            meaningText = repair.meaningText
        } else if let extracted = extractLeadingPronunciation(from: meaningText), !isPartOfSpeechMarker(extracted.pronunciation) {
            let pronunciation = extracted.pronunciation.trimmingCharacters(in: CharacterSet(charactersIn: "[]/()（） "))
            if containsJapanese(term) {
                reading = pronunciation
            } else {
                phonetic = pronunciation
            }
            meaningText = extracted.remainder
        }
        let meaning = normalizeMeaning(meaningText)
        guard isUsefulTerm(term), isUsefulMeaning(meaning) else { return nil }
        let confidence = max(0.42, confidenceScore(term: term, pronunciation: phonetic ?? reading, meaning: meaning) - 0.18)
        return DictionaryImportDraftEntry(
            term: term,
            reading: reading.nilIfBlank,
            phonetic: phonetic.nilIfBlank,
            meaning: meaning,
            tags: ["pdf"],
            context: String(line.prefix(240)),
            confidence: confidence,
            needsReview: true
        )
    }

    private static func extractLeadingPronunciation(from value: String) -> (pronunciation: String, remainder: String)? {
        let pattern = #"^\s*(\[[^\]]+\]|/[^/]+/|（[^）]+）|\([^)]+\))\s*(.+)$"#
        guard let match = firstMatch(pattern: pattern, in: value), match.count >= 2 else {
            return nil
        }
        return (match[0], match[1])
    }

    private static func repairMisplacedReadingAndTerm(
        term rawTerm: String,
        meaningText: String
    ) -> (term: String, reading: String, meaningText: String)? {
        let readingCandidate = stripHeaderArtifacts(from: rawTerm)
        guard readingCandidate != rawTerm || containsJapanese(readingCandidate) else { return nil }
        guard let leading = leadingTokenAndRemainder(meaningText) else { return nil }
        guard isUsefulTerm(leading.token),
              looksLikeReadingToken(readingCandidate, term: leading.token) else {
            return nil
        }
        return (leading.token, readingCandidate, leading.remainder)
    }

    private static func leadingTokenAndRemainder(_ text: String) -> (token: String, remainder: String)? {
        let pieces = text.split(maxSplits: 1, whereSeparator: \.isWhitespace).map(String.init)
        guard pieces.count == 2 else { return nil }
        return (pieces[0], pieces[1])
    }

    private static func firstMatch(pattern: String, in line: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let nsRange = NSRange(line.startIndex..<line.endIndex, in: line)
        guard let match = regex.firstMatch(in: line, range: nsRange), match.numberOfRanges >= 2 else {
            return nil
        }
        var values: [String] = []
        for index in 1..<match.numberOfRanges {
            let range = match.range(at: index)
            if range.location == NSNotFound {
                values.append("")
            } else if let swiftRange = Range(range, in: line) {
                values.append(String(line[swiftRange]).trimmingCharacters(in: .whitespacesAndNewlines))
            }
        }
        return values
    }

    private static func matches(pattern: String, in line: String) -> Bool {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return false }
        let nsRange = NSRange(line.startIndex..<line.endIndex, in: line)
        return regex.firstMatch(in: line, range: nsRange) != nil
    }

    private static func median(_ values: [CGFloat]) -> CGFloat {
        let sorted = values.filter(\.isFinite).sorted()
        guard !sorted.isEmpty else { return 0 }
        let middle = sorted.count / 2
        if sorted.count.isMultiple(of: 2) {
            return (sorted[middle - 1] + sorted[middle]) / 2
        }
        return sorted[middle]
    }

    private static func isFinite(_ rect: CGRect) -> Bool {
        rect.origin.x.isFinite
            && rect.origin.y.isFinite
            && rect.size.width.isFinite
            && rect.size.height.isFinite
    }

    private static func cleanLine(_ line: String) -> String {
        line
            .replacingOccurrences(of: "\u{00a0}", with: " ")
            .replacingOccurrences(of: "　", with: " ")
            .replacingOccurrences(of: #"^\s*[•·●○\-]\s*"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func stripHeaderArtifacts(from value: String) -> String {
        value
            .replacingOccurrences(of: #"^(序号|编号|发音|读音|單詞|单词|释义|釋義)+"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"(序号|编号|发音|读音|單詞|单词|释义|釋義|义|義)+$"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func normalizeMeaning(_ value: String) -> String {
        value
            .replacingOccurrences(of: #"^\s*(n\.|v\.|adj\.|adv\.|名|动|形|副)\s*"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func isUsefulTerm(_ term: String) -> Bool {
        guard term.count >= 1, term.count <= 42 else { return false }
        guard !term.allSatisfy(\.isNumber) else { return false }
        guard matches(pattern: #"^([A-Za-z][A-Za-z'\-]{0,41}|[\p{Han}\p{Hiragana}\p{Katakana}ー]+)$"#, in: term) else {
            return false
        }
        if isPureHan(term), term.count > 6 {
            return false
        }
        if term.count == 1 {
            return term.unicodeScalars.contains { scalar in
                let value = Int(scalar.value)
                return (0x3040...0x30ff).contains(value) || (0x4e00...0x9fff).contains(value)
            }
        }
        return true
    }

    private static func isUsefulMeaning(_ meaning: String) -> Bool {
        if meaning.count >= 2 { return true }
        return meaning.unicodeScalars.contains { scalar in
            (0x4e00...0x9fff).contains(Int(scalar.value))
        }
    }

    private static func isLikelyNoise(_ line: String) -> Bool {
        if line.count < 4 || line.count > 220 { return true }
        if isLikelyTableHeader(line) { return true }
        let lower = line.lowercased()
        return lower.hasPrefix("page ")
            || lower == "vocabulary"
            || lower == "index"
            || lower.hasPrefix("词单")
            || lower.hasPrefix("单词表")
            || lower.contains("moji辞書")
            || lower.contains("moji 辞書")
    }

    private static func isLikelyTableHeader(_ line: String) -> Bool {
        let compact = line
            .lowercased()
            .replacingOccurrences(of: #"[：:\s|,，、/\\\-]+"#, with: "", options: .regularExpression)
        let exactHeaders: Set<String> = [
            "序号", "编号", "发音", "讀音", "读音", "音标", "音標", "单词", "單詞", "词汇", "詞彙",
            "释义", "釋義", "含义", "含義", "意思", "中文", "word", "term", "meaning", "reading",
            "pronunciation", "phonetic", "no", "number"
        ]
        if exactHeaders.contains(compact) { return true }

        let headerTokens = [
            "序号", "编号", "no", "number",
            "发音", "讀音", "读音", "音标", "音標", "reading", "pronunciation", "phonetic",
            "单词", "單詞", "词汇", "詞彙", "word", "term",
            "释义", "釋義", "含义", "含義", "意思", "meaning"
        ]
        let hitCount = headerTokens.reduce(0) { count, token in
            compact.contains(token) ? count + 1 : count
        }
        return hitCount >= 3 && !compact.contains("[") && !compact.contains("【")
    }

    private static func looksLikeReadingToken(_ reading: String, term: String) -> Bool {
        if reading.count > 48 || term.isEmpty { return false }
        if reading.unicodeScalars.allSatisfy({ scalar in
            let value = Int(scalar.value)
            return (0x3040...0x30ff).contains(value) || value == 0x30fc
        }) {
            return true
        }
        if reading.range(of: #"^[A-Za-z'\-]+$"#, options: .regularExpression) != nil,
           containsJapanese(term) || term.unicodeScalars.contains(where: { (0x4e00...0x9fff).contains(Int($0.value)) }) {
            return true
        }
        return false
    }

    private static func isPartOfSpeechMarker(_ value: String) -> Bool {
        let compact = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "[]【】()（） "))
            .replacingOccurrences(of: #"[\s·・、,，/\\\-]+"#, with: "", options: .regularExpression)
            .lowercased()
        guard !compact.isEmpty else { return false }
        let markers: Set<String> = [
            "名", "名词", "名詞", "专", "代",
            "动", "動", "动词", "動詞", "自动", "自動", "他动", "他動", "自他", "サ变", "サ変",
            "形", "形容词", "形容詞", "形动", "形動", "形容动词", "形容動詞",
            "副", "副词", "副詞", "助", "助词", "助詞", "助动", "助動",
            "感", "接", "接头", "接頭", "接尾", "连体", "連体", "惯用", "慣用", "短语", "連語",
            "名形", "名形动", "名形動", "形动名", "形動名"
        ]
        return markers.contains(compact)
    }

    private static func isPureHan(_ value: String) -> Bool {
        value.unicodeScalars.allSatisfy { scalar in
            (0x4e00...0x9fff).contains(Int(scalar.value))
        }
    }

    private static func containsJapanese(_ value: String) -> Bool {
        value.unicodeScalars.contains { scalar in
            (0x3040...0x30ff).contains(Int(scalar.value))
        }
    }

    private static func confidenceScore(term: String, pronunciation: String?, meaning: String) -> Double {
        var score = 0.56
        if pronunciation != nil { score += 0.16 }
        if meaning.range(of: #"[，。；、,;]"#, options: .regularExpression) != nil { score += 0.08 }
        if term.range(of: #"^[A-Za-z'\-]+$"#, options: .regularExpression) != nil { score += 0.08 }
        if meaning.count > 6 { score += 0.08 }
        return min(score, 0.98)
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
