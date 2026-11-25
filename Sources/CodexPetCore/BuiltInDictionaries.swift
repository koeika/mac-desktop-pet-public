import Foundation

public enum BuiltInDictionaries {
    public static let packs: [DictionaryPack] = [
        DictionaryPack(
            id: "ielts-sample",
            name: "IELTS sample",
            description: "Small legally safe sample words. Import your full IELTS list as CSV/JSON.",
            entries: [
                DictionaryEntry(term: "allocate", phonetic: "/ˈæləkeɪt/", meaning: "分配；拨出资源", example: "The team allocated two days to testing.", exampleTranslation: "团队安排了两天时间进行测试。", hint: "常与时间、预算或资源搭配。", tags: ["ielts"]),
                DictionaryEntry(term: "coherent", phonetic: "/koʊˈhɪrənt/", meaning: "连贯的；条理清楚的", example: "A coherent essay has clear transitions.", exampleTranslation: "一篇条理清晰的文章有明确的过渡。", hint: "常用于描述文章和论证。", tags: ["ielts"]),
                DictionaryEntry(term: "feasible", phonetic: "/ˈfiːzəbl/", meaning: "可行的", example: "The plan is feasible with a smaller scope.", exampleTranslation: "缩小范围后，这个计划是可行的。", tags: ["ielts"]),
                DictionaryEntry(term: "mitigate", phonetic: "/ˈmɪtɪɡeɪt/", meaning: "减轻；缓和", example: "Planning can mitigate project risk.", exampleTranslation: "规划可以降低项目风险。", tags: ["ielts"]),
                DictionaryEntry(term: "prevalent", phonetic: "/ˈprevələnt/", meaning: "普遍的；流行的", example: "Remote work became more prevalent.", exampleTranslation: "远程办公变得更加普遍。", tags: ["ielts"])
            ]
        ),
        DictionaryPack(
            id: "japanese-basic-sample",
            name: "Japanese beginner sample",
            description: "Small beginner Japanese sample. Import your licensed textbook list as CSV/JSON.",
            entries: [
                DictionaryEntry(term: "わたし", reading: "わたし", meaning: "我", example: "わたしは エンジニアです。", exampleTranslation: "我是工程师。", tags: ["japanese"]),
                DictionaryEntry(term: "これ", reading: "これ", meaning: "这个", example: "これは なんですか。", exampleTranslation: "这是什么？", tags: ["japanese"]),
                DictionaryEntry(term: "ほん", reading: "ほん", meaning: "书", example: "これは 日本語の ほんです。", exampleTranslation: "这是日语书。", tags: ["japanese"]),
                DictionaryEntry(term: "いま", reading: "いま", meaning: "现在", example: "いま なんじですか。", exampleTranslation: "现在几点？", tags: ["japanese"]),
                DictionaryEntry(term: "べんきょうします", reading: "べんきょうします", meaning: "学习", example: "毎晩 日本語を べんきょうします。", exampleTranslation: "我每天晚上学习日语。", tags: ["japanese"])
            ]
        )
    ]
}

