import AppKit
import CodexPetCore
import NaturalLanguage

enum VocabularyCardTypography {
    static func content(entry: DictionaryEntry, revealed: Bool, theme: AppVisualTheme,
                        translationStatus: String? = nil, availableWidth: CGFloat = 364) -> NSAttributedString {
        let text = NSMutableAttributedString()
        let muted = NSColor(calibratedWhite: 0.45, alpha: 1)
        func append(_ value: String, font: NSFont, color: NSColor, spacing: CGFloat = 12,
                    indent: CGFloat = 0) {
            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = .left
            paragraph.lineSpacing = 4
            paragraph.paragraphSpacing = spacing
            paragraph.headIndent = indent
            paragraph.tabStops = [NSTextTab(textAlignment: .left, location: max(28, indent))]
            text.append(NSAttributedString(string: value + "\n", attributes: [
                .font: font, .foregroundColor: color, .paragraphStyle: paragraph
            ]))
        }
        let pronunciation = pronunciation(entry)
        let termWidth = (entry.term as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 25, weight: .bold)]).width
        let ipaWidth = ((pronunciation ?? "") as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 12.5)]).width
        if let pronunciation, termWidth + ipaWidth + 18 <= availableWidth {
            append(entry.term + "   " + pronunciation, font: .systemFont(ofSize: 25, weight: .bold), color: theme.inkNSColor, spacing: 18)
            text.addAttributes([.font: NSFont.systemFont(ofSize: 12.5), .foregroundColor: muted],
                               range: NSRange(location: (entry.term as NSString).length, length: ("   " + pronunciation as NSString).length))
        } else {
            append(entry.term, font: .systemFont(ofSize: 25, weight: .bold), color: theme.inkNSColor, spacing: 5)
            if let pronunciation {
                append(pronunciation, font: .systemFont(ofSize: 12.5), color: muted, spacing: 18)
            }
        }
        guard revealed else {
            // The hidden answer must not reserve a trailing paragraph or an empty text line.
            if text.string.hasSuffix("\n") { text.deleteCharacters(in: NSRange(location: text.length - 1, length: 1)) }
            if text.length > 0, let paragraph = (text.attribute(.paragraphStyle, at: text.length - 1, effectiveRange: nil) as? NSParagraphStyle)?.mutableCopy() as? NSMutableParagraphStyle {
                paragraph.paragraphSpacing = 0
                let last = (text.string as NSString).paragraphRange(for: NSRange(location: text.length - 1, length: 0))
                text.addAttribute(.paragraphStyle, value: paragraph, range: last)
            }
            return text
        }
        let meaning = entry.meaning.trimmingCharacters(in: .whitespacesAndNewlines)
        for line in meaning.components(separatedBy: .newlines).filter({ !$0.trimmingCharacters(in: .whitespaces).isEmpty }) {
            let tag = #"(?:vt|vi|adj|adv|prep|pron|conj|interj|aux|art|num|n|v|名词|形容词|助动词|形容動詞|動詞|助詞|形动|惯用|名|形|动|副)\.?"#
            let compound = tag + #"(?:\s*[/·・、]\s*"# + tag + #")*"#
            let range = (line as NSString).range(of: #"^\s*(?:\["# + compound + #"\]|"# + compound + #"\.)\s*"#,
                                                 options: [.regularExpression, .caseInsensitive])
            if range.location != NSNotFound {
                let original = line as NSString
                let part = original.substring(with: range).trimmingCharacters(in: CharacterSet(charactersIn: "[] "))
                let definition = original.substring(from: range.length)
                let start = text.length
                let columnWidth = max(28, ceil((part as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 13)]).width) + 12)
                append(part + "\t" + definition, font: .systemFont(ofSize: 15, weight: .semibold), color: theme.inkNSColor, indent: columnWidth)
                text.addAttributes([.font: NSFont.systemFont(ofSize: 13), .foregroundColor: muted],
                                   range: NSRange(location: start, length: (part as NSString).length))
            } else {
                append(line, font: .systemFont(ofSize: 15, weight: .semibold), color: theme.inkNSColor)
            }
        }
        if meaning.isEmpty {
            append("释义暂缺", font: .systemFont(ofSize: 14), color: muted)
        }
        if let example = nonEmpty(entry.example) {
            let start = text.length
            append(example, font: .systemFont(ofSize: 14), color: theme.inkNSColor, spacing: 5)
            for range in highlightedRanges(term: entry.term, example: example) {
                text.addAttribute(.foregroundColor, value: NSColor(calibratedRed: 0.86, green: 0.25, blue: 0.48, alpha: 1),
                                  range: NSRange(location: start + range.location, length: range.length))
            }
            append(nonEmpty(entry.exampleTranslation) ?? translationStatus ?? "译文暂缺",
                   font: .systemFont(ofSize: 13), color: muted, spacing: 8)
        }
        return text
    }

    static func pronunciation(_ entry: DictionaryEntry) -> String? {
        if let raw = nonEmpty(entry.phonetic) {
            // Unlabelled legacy IPA stays unlabelled; a single accent must not be invented as both US and UK.
            return raw.replacingOccurrences(of: " · ", with: "   ·   ")
        }
        return nonEmpty(entry.reading).map { "读音  " + $0 }
    }

    static func highlightedRanges(term: String, example: String) -> [NSRange] {
        guard !term.isEmpty else { return [] }
        let aliases = term.components(separatedBy: "/").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        var ranges: [NSRange] = []
        let latinAliases = Set(aliases.filter { $0.range(of: #"^[A-Za-z][A-Za-z '-]*$"#, options: .regularExpression) != nil }.map { $0.lowercased() })
        for alias in aliases {
            let escaped = NSRegularExpression.escapedPattern(for: alias)
            let pattern = latinAliases.contains(alias.lowercased()) ? #"(?<![\p{L}\p{N}_])"# + escaped + #"(?![\p{L}\p{N}_])"# : escaped
            guard let expression = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { continue }
            for match in expression.matches(in: example, range: NSRange(location: 0, length: (example as NSString).length)) where !ranges.contains(match.range) {
                ranges.append(match.range)
            }
        }
        if !latinAliases.isEmpty {
            let tagger = NLTagger(tagSchemes: [.lemma])
            tagger.string = example
            tagger.setLanguage(.english, range: example.startIndex..<example.endIndex)
            tagger.enumerateTags(in: example.startIndex..<example.endIndex, unit: .word, scheme: .lemma,
                                 options: [.omitWhitespace, .omitPunctuation]) { tag, range in
                if let lemma = tag?.rawValue.lowercased(), latinAliases.contains(lemma) {
                    let value = NSRange(range, in: example)
                    if !ranges.contains(value) { ranges.append(value) }
                }
                return true
            }
        }
        return ranges.sorted { $0.location < $1.location }
    }

    private static func nonEmpty(_ value: String?) -> String? {
        let result = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return result.isEmpty ? nil : result
    }
}
