import Foundation

public enum BuiltInDictionaries {
    public static let packs: [DictionaryPack] = [
        DictionaryPack(
            id: "ielts-sample",
            name: "IELTS sample",
            description: "Small legally safe sample words. Import your full IELTS list as CSV/JSON.",
            entries: [
                DictionaryEntry(term: "allocate", phonetic: "/ˈæləkeɪt/", meaning: "分配；拨出资源", example: "The team allocated two days to testing.", hint: "Often used with time, budget, or resources.", tags: ["ielts"]),
                DictionaryEntry(term: "coherent", phonetic: "/koʊˈhɪrənt/", meaning: "连贯的；条理清楚的", example: "A coherent essay has clear transitions.", hint: "Useful in IELTS writing.", tags: ["ielts"]),
                DictionaryEntry(term: "feasible", phonetic: "/ˈfiːzəbl/", meaning: "可行的", example: "The plan is feasible with a smaller scope.", hint: "More practical than simply possible.", tags: ["ielts"]),
                DictionaryEntry(term: "mitigate", phonetic: "/ˈmɪtɪɡeɪt/", meaning: "减轻；缓和", example: "Planning can mitigate project risk.", hint: "Common with risk, impact, effect.", tags: ["ielts"]),
                DictionaryEntry(term: "prevalent", phonetic: "/ˈprevələnt/", meaning: "普遍的；流行的", example: "Remote work became more prevalent.", hint: "Describes something common in a group.", tags: ["ielts"])
            ]
        ),
        DictionaryPack(
            id: "japanese-basic-sample",
            name: "Japanese beginner sample",
            description: "Small beginner Japanese sample. Import your licensed textbook list as CSV/JSON.",
            entries: [
                DictionaryEntry(term: "わたし", reading: "watashi", meaning: "我", example: "わたしは エンジニアです。", hint: "Polite, general first-person pronoun.", tags: ["japanese"]),
                DictionaryEntry(term: "これ", reading: "kore", meaning: "这个", example: "これは なんですか。", hint: "Near-speaker demonstrative.", tags: ["japanese"]),
                DictionaryEntry(term: "ほん", reading: "hon", meaning: "书", example: "これは 日本語の ほんです。", hint: "の can connect nouns.", tags: ["japanese"]),
                DictionaryEntry(term: "いま", reading: "ima", meaning: "现在", example: "いま なんじですか。", hint: "Used when asking current time.", tags: ["japanese"]),
                DictionaryEntry(term: "べんきょうします", reading: "benkyou shimasu", meaning: "学习", example: "毎晩 日本語を べんきょうします。", hint: "Noun + します forms many verbs.", tags: ["japanese"])
            ]
        )
    ]
}

