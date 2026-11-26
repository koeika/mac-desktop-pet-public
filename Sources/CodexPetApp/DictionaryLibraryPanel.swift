import SwiftUI

struct DictionaryLibraryPanel: View {
    @ObservedObject var store: AppDataStore
    @ObservedObject var index: VocabularyLibraryIndex
    @Binding var query: DictionaryLibraryQuery
    @State private var matches: [DictionarySummary] = []
    @Binding var page: Int
    @Binding var pageSize: Int
    @State private var loading = false

    private var queryKey: String { "\(index.generation)|\(query.search)|\(query.category)|\(query.enabled)|\(query.source)|\(query.sort)" }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                TextField("搜索词典名称、分类或描述", text: $query.search).textFieldStyle(.roundedBorder)
                Picker("排序", selection: $query.sort) {
                    Text("名称 A-Z").tag("名称 A-Z"); Text("词数最多").tag("词数最多")
                }.frame(width: 190)
            }
            ViewThatFits(in: .horizontal) {
                HStack { categoryFilter; enabledFilter; sourceFilter }
                VStack(alignment: .leading) { categoryFilter; HStack { enabledFilter; sourceFilter } }
            }
            Divider()
            ScrollViewReader { reader in
                ScrollView {
                    LazyVStack(spacing: 0) {
                        Color.clear.frame(height: 1).id("top")
                        if matches.isEmpty {
                            Text(loading ? "正在查询…" : "没有符合条件的词典").foregroundStyle(.secondary).padding(.vertical, 36)
                        }
                        let result = LibraryPage(count: matches.count, size: pageSize, requested: page)
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 260), spacing: 14)], spacing: 14) {
                            ForEach(Array(matches[result.range])) { summary in
                                DictionaryCard(store: store, summary: summary)
                            }
                        }.padding(.bottom, 8)
                    }.padding(.trailing, 4)
                }.scrollIndicators(.visible)
                .onChange(of: page) { _, _ in reader.scrollTo("top", anchor: .top) }
                .onChange(of: query) { _, _ in reader.scrollTo("top", anchor: .top) }
            }
            LibraryPagination(count: matches.count, page: $page, pageSize: $pageSize, sizes: [12, 24, 48])
        }
        .task(id: queryKey) {
            loading = true
            do { try await Task.sleep(for: .milliseconds(180)) } catch { return }
            let rows = index.dictionaries
            let current = query
            guard let result = try? await libraryBackground({ current.apply(to: rows) }) else { return }
            guard !Task.isCancelled else { return }
            matches = result
            page = LibraryPage(count: result.count, size: pageSize, requested: page).number
            loading = false
        }
        .onChange(of: query) { _, _ in page = 1 }
    }

    private var categoryFilter: some View {
        Picker("分类", selection: $query.category) {
            Text("全部").tag("全部")
            ForEach(index.categories, id: \.self) { Text($0).tag($0) }
        }.frame(maxWidth: 230)
        .onChange(of: index.categories) { _, categories in
            if query.category != "全部", !categories.contains(query.category) { query.category = "全部" }
        }
    }
    private var enabledFilter: some View {
        Picker("状态", selection: $query.enabled) {
            ForEach(["全部", "已启用", "未启用"], id: \.self) { Text($0).tag($0) }
        }.frame(maxWidth: 180)
    }
    private var sourceFilter: some View {
        Picker("来源", selection: $query.source) {
            ForEach(["全部", "内置", "导入"], id: \.self) { Text($0).tag($0) }
        }.frame(maxWidth: 180)
    }
}
