import CodexPetCore
import SwiftUI

func libraryBackground<Value>(_ work: @escaping () throws -> Value) async throws -> Value {
    let task = Task.detached(priority: .userInitiated, operation: work)
    return try await withTaskCancellationHandler(operation: {
        let value = try await task.value
        try Task.checkCancellation()
        return value
    }, onCancel: { task.cancel() })
}

struct LibraryPage {
    let count: Int
    let size: Int
    let number: Int
    var pages: Int { max(1, (count + size - 1) / size) }
    var range: Range<Int> {
        let start = min(count, (number - 1) * size)
        return start..<min(count, start + size)
    }
    init(count: Int, size: Int, requested: Int) {
        self.count = max(0, count)
        self.size = max(1, size)
        self.number = min(max(1, requested), max(1, (max(0, count) + max(1, size) - 1) / max(1, size)))
    }
}

struct NotebookRow: Identifiable {
    var id: String { word.id }
    let word: CapturedWord
    let state: String
    let due: Date?
    let searchable: String

    init(word: CapturedWord, stat: WordStat?, now: Date) {
        self.word = word
        state = stat?.learned == true ? "已掌握" :
            (stat?.review != nil || stat?.lastAction == .unknown || stat?.lastAction == .hard ? "待加强" : "新收藏")
        due = stat?.review != nil || stat?.lastAction != nil ? VocabularyReviewScheduler.dueDate(stat, now: now) : nil
        searchable = [word.content.term, word.content.meaning, word.content.phoneticUK ?? "",
                      word.content.phoneticUS ?? "", word.content.sourceTitle ?? ""].joined(separator: "\n")
    }
}

struct NotebookQuery: Equatable {
    var search = ""
    var state = "全部"
    var language = "全部"
    var source = "全部"
    var sort = "最近添加"

    func apply(to rows: [NotebookRow], now: Date) -> [NotebookRow] {
        let term = search.trimmingCharacters(in: .whitespacesAndNewlines)
        return (try? rows.filter { row in
            try Task.checkCancellation()
            return (term.isEmpty || row.searchable.localizedCaseInsensitiveContains(term)) &&
            (state == "全部" || (state == "到期复习" ? row.due.map { $0 <= now } == true : row.state == state)) &&
            (language == "全部" || row.word.content.language == language) &&
            (source == "全部" || (row.word.content.sourceURL?.isEmpty == false ? "有网页来源" : "无网页来源") == source)
        }.sorted { a, b in
            try Task.checkCancellation()
            switch sort {
            case "单词 A-Z":
                let order = a.word.content.term.localizedStandardCompare(b.word.content.term)
                if order != .orderedSame { return order == .orderedAscending }
            case "最早添加":
                if a.word.createdAt != b.word.createdAt { return a.word.createdAt < b.word.createdAt }
            case "优先到期":
                if a.due != b.due { return (a.due ?? .distantFuture) < (b.due ?? .distantFuture) }
            default:
                if a.word.createdAt != b.word.createdAt { return a.word.createdAt > b.word.createdAt }
            }
            return a.id < b.id
        }) ?? []
    }
}

struct DictionaryLibraryQuery: Equatable {
    var search = ""
    var category = "全部"
    var enabled = "全部"
    var source = "全部"
    var sort = "名称 A-Z"

    func apply(to rows: [DictionarySummary]) -> [DictionarySummary] {
        let term = search.trimmingCharacters(in: .whitespacesAndNewlines)
        return (try? rows.filter { row in
            try Task.checkCancellation()
            return (term.isEmpty || [row.pack.name, row.category ?? "", row.pack.description ?? ""].contains { $0.localizedCaseInsensitiveContains(term) }) &&
            (category == "全部" || (row.category ?? "未分类") == category) &&
            (enabled == "全部" || row.isEnabled == (enabled == "已启用")) &&
            (source == "全部" || row.isBuiltIn == (source == "内置"))
        }.sorted { a, b in
            try Task.checkCancellation()
            if sort == "词数最多", a.pack.entries.count != b.pack.entries.count { return a.pack.entries.count > b.pack.entries.count }
            let order = a.pack.name.localizedStandardCompare(b.pack.name)
            return order == .orderedSame ? a.id < b.id : order == .orderedAscending
        }) ?? []
    }
}

// Array/dictionary snapshots use copy-on-write. Index construction and queries never read the mutable store off-main.
@MainActor final class VocabularyLibraryIndex: ObservableObject {
    @Published private(set) var generation = 0
    private(set) var words: [NotebookRow] = []
    private(set) var dictionaries: [DictionarySummary] = []
    private(set) var categories: [String] = []
    private(set) var dueWords = 0
    private(set) var personalSources: [String] = []
    private var request = 0

    func reload(store: AppDataStore, now: Date, beforePublishing: (() async -> Void)? = nil) async {
        request &+= 1
        let currentRequest = request
        let words = store.personalVocabulary.words
        let packs = store.dictionaries
        let stats = store.vocabularyProgress.stats
        let enabled = store.settings.enabledDictionaryIDs
        guard let result = try? await libraryBackground({
            let rows = try words.map { word in
                try Task.checkCancellation()
                return NotebookRow(word: word, stat: stats[word.statKey], now: now)
            }
            let summaries = AppDataStore.dictionarySummaries(packs: packs, stats: stats, enabledIDs: enabled, isCancelled: { Task.isCancelled })
            let categories = Set(summaries.map { $0.category ?? "未分类" }).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
            return (rows, summaries, categories, rows.filter { $0.due.map { $0 <= now } == true }.count)
        }) else { return }
        // Tests can hold a completed old snapshot while a newer refresh publishes.
        await beforePublishing?()
        guard !Task.isCancelled, currentRequest == request else { return }
        self.words = result.0
        dictionaries = result.1
        categories = result.2
        dueWords = result.3
        personalSources = Set(result.0.map { $0.word.dictionaryID }).sorted()
        generation &+= 1
    }
}

struct LibraryPagination: View {
    let count: Int
    @Binding var page: Int
    @Binding var pageSize: Int
    var sizes = [20, 50, 100]
    var compact = false

    var body: some View {
        let result = LibraryPage(count: count, size: pageSize, requested: page)
        HStack(spacing: 12) {
            if !compact {
                Text(count == 0 ? "0 条结果" : "\(result.range.lowerBound + 1)-\(result.range.upperBound) / \(count) 条")
                    .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                Spacer()
                pageSizePicker
            }
            Button { page = result.number - 1 } label: { Image(systemName: "chevron.left") }
                .disabled(result.number == 1).help("上一页")
            TextField("页码", value: Binding(get: { result.number }, set: {
                page = LibraryPage(count: count, size: pageSize, requested: $0).number
            }), format: .number.grouping(.never)).textFieldStyle(.roundedBorder).frame(width: compact ? 36 : 52)
                .accessibilityLabel("跳转页码")
            Text("/ \(result.pages)").font(.caption).monospacedDigit()
            Button { page = result.number + 1 } label: { Image(systemName: "chevron.right") }
                .disabled(result.number == result.pages).help("下一页")
            if compact { Spacer(minLength: 0); pageSizePicker.labelsHidden() }
        }.padding(.top, 8)
        .onChange(of: pageSize) { _, _ in page = 1 }
        .onChange(of: count) { _, _ in page = LibraryPage(count: count, size: pageSize, requested: page).number }
    }

    private var pageSizePicker: some View {
        Picker("每页", selection: $pageSize) {
            ForEach(sizes, id: \.self) { Text("\($0) 条").tag($0) }
        }.fixedSize()
    }
}
