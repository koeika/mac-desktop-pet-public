import AppKit
import CodexPetCore
import SwiftUI

struct PersonalVocabularyPanel: View {
    @ObservedObject var store: AppDataStore
    @ObservedObject var index: VocabularyLibraryIndex
    @State private var editing: CaptureDraft?
    @State private var selectedID: String?
    @Environment(\.companionTheme) private var theme
    @Binding var query: NotebookQuery
    @State private var matches: [NotebookRow] = []
    @Binding var page: Int
    @Binding var pageSize: Int
    @State private var loading = false
    @State private var error: String?
    @State private var deleting: CapturedWord?

    private var queryKey: String { "\(index.generation)|\(query.search)|\(query.state)|\(query.language)|\(query.source)|\(query.sort)" }

    private var visibleRows: [NotebookRow] {
        Array(matches[LibraryPage(count: matches.count, size: pageSize, requested: page).range])
    }

    private var selectedWord: CapturedWord? {
        guard let candidate = visibleRows.first(where: { $0.id == selectedID })?.word ?? visibleRows.first?.word else { return nil }
        return store.personalVocabulary.words.first { $0.id == candidate.id }
    }

    var body: some View {
        GeometryReader { geometry in
            if geometry.size.width >= 700 {
                HStack(spacing: 0) {
                    wordList.frame(width: min(330, max(260, geometry.size.width * 0.38)))
                    Divider().padding(.horizontal, 18)
                    detail.frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                VStack(spacing: 14) {
                    wordList.frame(height: max(230, geometry.size.height * 0.43))
                    Divider()
                    detail.frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .task(id: queryKey) {
            loading = true
            do { try await Task.sleep(for: .milliseconds(180)) } catch { return }
            let rows = index.words
            let current = query
            guard let result = try? await libraryBackground({ current.apply(to: rows, now: Date()) }) else { return }
            guard !Task.isCancelled else { return }
            matches = result
            page = LibraryPage(count: result.count, size: pageSize, requested: page).number
            loading = false
        }
        .onChange(of: query) { _, _ in page = 1 }
        .sheet(item: $editing) { draft in CaptureEditor(store: store, draft: draft) { editing = nil } }
        .confirmationDialog("删除这个收藏？学习记录会保留。", isPresented: Binding(
            get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
            Button("删除", role: .destructive) {
                if let word = deleting {
                    do { try store.deleteCapturedWord(word) } catch { self.error = error.localizedDescription }
                }
                deleting = nil
            }
        }
    }

    @ViewBuilder private var detail: some View {
        if let word = selectedWord {
            NotebookWordDetail(store: store, word: word, edit: {
                editing = CaptureDraft(content: word.content, isEditing: true, existingID: word.id)
            }, delete: { deleting = word }).id(word.id)
        } else {
            ContentUnavailableView("没有选中的生词", systemImage: "book.closed")
        }
    }

    private var wordList: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("收藏 \(index.words.count) · 到期复习 \(index.dueWords)").font(.subheadline).foregroundStyle(.secondary)
                Spacer()
                Button { editing = CaptureDraft(content: CapturePayload(term: "")) } label: {
                    Image(systemName: "plus")
                }.help("添加单词").accessibilityLabel("添加单词")
            }
            HStack {
                TextField("搜索单词或释义", text: $query.search).textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("notebook-search")
                Menu {
                    statusFilter
                    languageFilter
                    sourceFilter
                    Picker("排序", selection: $query.sort) {
                        ForEach(["最近添加", "最早添加", "单词 A-Z", "优先到期"], id: \.self) { Text($0).tag($0) }
                    }
                } label: { Image(systemName: "line.3.horizontal.decrease") }.fixedSize().help("筛选与排序")
            }
            if query.state != "全部" || query.language != "全部" || query.source != "全部" {
                HStack {
                    Text([query.state, query.language, query.source].filter { $0 != "全部" }.joined(separator: " · "))
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    Spacer()
                    Button("清除筛选") { query.state = "全部"; query.language = "全部"; query.source = "全部" }
                        .buttonStyle(.borderless).font(.caption)
                }
            }
            if let error { Text(error).foregroundStyle(.red).font(.caption) }
            Divider()
            ScrollViewReader { reader in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        Color.clear.frame(height: 1).id("top")
                        if matches.isEmpty {
                            Text(loading ? "正在查询…" : "没有符合条件的生词").foregroundStyle(.secondary).padding(.vertical, 36)
                                .frame(maxWidth: .infinity)
                        }
                        ForEach(visibleRows) { row in
                                Button { selectedID = row.id } label: {
                                    VStack(alignment: .leading, spacing: 5) {
                                        HStack {
                                            Text(row.word.content.term).font(.system(size: 14, weight: .semibold)).lineLimit(1)
                                            Spacer(minLength: 4)
                                            Text(row.state).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                                        }
                                        Text(row.word.content.meaning.isEmpty ? "待补充释义" : row.word.content.meaning)
                                            .font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1)
                                        Text(row.word.content.language.uppercased() + " · " + nextReviewText(row))
                                            .font(.caption).foregroundStyle(.secondary)
                                    }.padding(10).frame(maxWidth: .infinity, minHeight: 76, alignment: .leading)
                                        .background(selectedWord?.id == row.id ? theme.accent.opacity(0.07) : .clear, in: RoundedRectangle(cornerRadius: 6))
                                        .contentShape(Rectangle())
                                }.buttonStyle(.plain).focusEffectDisabled().help("查看释义、语境与学习记录")
                                    .accessibilityValue(selectedWord?.id == row.id ? "已选择" : "未选择")
                            Divider()
                        }
                    }
                }.scrollIndicators(.visible)
                .onChange(of: page) { _, _ in reader.scrollTo("top", anchor: .top) }
                .onChange(of: query) { _, _ in reader.scrollTo("top", anchor: .top) }
            }
            LibraryPagination(count: matches.count, page: $page, pageSize: $pageSize, compact: true)
        }
        .overlay(alignment: .topTrailing) {
            if loading { ProgressView().controlSize(.small).offset(y: 38).accessibilityLabel("正在查询生词") }
        }
    }

    private var statusFilter: some View {
        Picker("学习状态", selection: $query.state) {
            ForEach(["全部", "新收藏", "待加强", "到期复习", "已掌握"], id: \.self) { Text($0).tag($0) }
        }.frame(maxWidth: 230)
    }
    private var languageFilter: some View {
        Picker("语言", selection: $query.language) {
            Text("全部").tag("全部"); Text("英语").tag("en"); Text("日语").tag("ja"); Text("其他").tag("other")
        }.frame(maxWidth: 180)
    }
    private var sourceFilter: some View {
        Picker("来源", selection: $query.source) {
            ForEach(["全部", "有网页来源", "无网页来源"], id: \.self) { Text($0).tag($0) }
        }.frame(maxWidth: 220)
    }
    private func nextReviewText(_ row: NotebookRow) -> String {
        guard !row.word.content.meaning.isEmpty else { return "补充释义后开始复习" }
        guard let due = row.due else { return "等待首次学习" }
        return due <= Date() ? "已到期" : "下次 \(due.formatted(date: .abbreviated, time: .shortened))"
    }
}

struct NotebookWordDetail: View {
    @ObservedObject var store: AppDataStore
    let word: CapturedWord
    var edit: () -> Void = {}
    var delete: () -> Void = {}
    @Environment(\.companionTheme) private var theme
    @State private var error: String?
    @State private var feedback: String?
    private var current: CapturedWord { store.personalVocabulary.words.first { $0.id == word.id } ?? word }
    private var scoped: ScopedDictionaryEntry {
        ScopedDictionaryEntry(dictionaryID: current.dictionaryID, dictionaryName: "我的生词", entry: current.entry)
    }
    var body: some View {
        let word = current
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(word.content.language.uppercased() + " · 收藏词条").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button(action: edit) { Image(systemName: "pencil") }.help("编辑词条")
                Menu {
                    Button("删除收藏", role: .destructive, action: delete)
                } label: { Image(systemName: "ellipsis") }.fixedSize().help("词条操作")
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VocabularyDetailText(entry: word.entry, theme: theme)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityIdentifier("notebook-word-body")
                    if let hint = word.content.hint, !hint.isEmpty {
                        Divider()
                        Text("语境说明").font(.subheadline.weight(.semibold))
                        Text(hint).font(.system(size: 13)).fixedSize(horizontal: false, vertical: true)
                    }
                    if let raw = word.content.sourceURL, let url = URL(string: raw), ["http", "https"].contains(url.scheme?.lowercased() ?? "") {
                        Link(word.content.sourceTitle ?? "原网页", destination: url)
                    }
                    DisclosureGroup("语境与来源 · \(word.contexts.count)") {
                        VStack(alignment: .leading, spacing: 12) {
                            ForEach(Array(word.contexts.enumerated()), id: \.offset) { _, context in
                                Text([context.example, context.translation, context.title].compactMap { $0 }.joined(separator: "\n"))
                                Divider()
                            }
                        }.padding(.top, 10)
                    }.font(.caption)
                    DisclosureGroup("最近学习记录") {
                        let events = store.vocabularyProgress.stats[word.statKey]?.review?.events ?? []
                        VStack(alignment: .leading, spacing: 8) {
                            if events.isEmpty { Text("尚无学习记录").foregroundStyle(.secondary) }
                            ForEach(Array(events.suffix(30).reversed()), id: \.id) { event in
                                Text("\(event.at.formatted(date: .abbreviated, time: .shortened)) · \(event.action == .known ? "认识" : event.action == .hard ? "有点印象" : "不认识")")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }.padding(.top, 10)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled)
            }.scrollIndicators(.visible)
            Divider()
            if let error { Text(error).font(.caption).foregroundStyle(.red) }
            if let feedback { Text(feedback).font(.caption).foregroundStyle(.secondary) }
            ViewThatFits(in: .horizontal) {
                HStack { reviewButtons }
                VStack(alignment: .leading) { reviewButtons }
            }
        }
    }

    @ViewBuilder private var reviewButtons: some View {
        ForEach([WordAction.unknown, .hard, .known], id: \.rawValue) { action in
            Button {
                let next = store.reviewPreview(scoped, action: action)
                do {
                    try store.reviewWord(scoped, action: action)
                    feedback = "已记录 · 下次复习 \(next)后"
                    error = nil
                } catch { self.error = error.localizedDescription }
            } label: {
                Text(action == .known ? "认识啦" : action == .hard ? "有点印象" : "不认识")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(action == .known ? theme.accent : .secondary)
            .disabled(current.content.meaning.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .help("下次复习：\(store.reviewPreview(scoped, action: action))")
        }
    }
}

struct VocabularyDetailText: NSViewRepresentable {
    let entry: DictionaryEntry
    let theme: AppVisualTheme

    func makeNSView(context: Context) -> NSTextView {
        let view = NSTextView()
        view.isEditable = false
        view.isSelectable = true
        view.isRichText = true
        view.drawsBackground = false
        view.textContainerInset = .zero
        view.textContainer?.lineFragmentPadding = 0
        view.isHorizontallyResizable = false
        view.isVerticallyResizable = true
        view.textContainer?.widthTracksTextView = true
        return view
    }

    func updateNSView(_ view: NSTextView, context: Context) {
        update(view, width: max(200, view.bounds.width))
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView view: NSTextView, context: Context) -> CGSize? {
        let width = max(1, proposal.width ?? 350)
        update(view, width: width)
        guard let container = view.textContainer, let layout = view.layoutManager else { return nil }
        container.containerSize = NSSize(width: width, height: .greatestFiniteMagnitude)
        layout.ensureLayout(for: container)
        return NSSize(width: width, height: ceil(layout.usedRect(for: container).height) + 2)
    }

    private func update(_ view: NSTextView, width: CGFloat) {
        let content = VocabularyCardTypography.content(entry: entry, revealed: true, theme: theme, availableWidth: width)
        if view.textStorage?.isEqual(to: content) != true { view.textStorage?.setAttributedString(content) }
    }
}

struct CaptureDraft: Identifiable {
    let id = UUID()
    var content: CapturePayload
    var isEditing = false
    var existingID: String?
}

struct CaptureEditor: View {
    @ObservedObject var store: AppDataStore
    @State var draft: CaptureDraft
    let close: () -> Void
    @State private var pasted = ""
    @State private var busy = false
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(draft.isEditing ? "编辑生词" : "收藏生词").font(.title2.bold())
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    TextField("单词或短语", text: $draft.content.term).disabled(draft.isEditing)
                    Picker("语言", selection: $draft.content.language) {
                        Text("英语").tag("en"); Text("日语").tag("ja"); Text("其他").tag("other")
                    }.disabled(draft.isEditing)
                    TextField("英国音标 / 日语读音", text: optional($draft.content.phoneticUK))
                    TextField("美国音标", text: optional($draft.content.phoneticUS))
                    TextField("释义（含词性）", text: $draft.content.meaning, axis: .vertical).lineLimit(2...5)
                    TextField("原文例句", text: optional($draft.content.example), axis: .vertical).lineLimit(2...4)
                    TextField("例句翻译", text: optional($draft.content.exampleTranslation), axis: .vertical).lineLimit(2...4)
                    TextField("语境说明", text: optional($draft.content.hint), axis: .vertical).lineLimit(2...4)
                    TextField("来源网址", text: optional($draft.content.sourceURL))
                    TextField("网页标题", text: optional($draft.content.sourceTitle))
                    Text("粘贴沉浸式翻译内容").font(.headline)
                    TextEditor(text: $pasted).frame(height: 100).border(.quaternary)
                    Button(busy ? "正在补全…" : "用 DeepSeek 解析并补全") {
                        busy = true; error = nil
                        Task { @MainActor in
                            defer { busy = false }
                            do { draft.content = try await store.enrichCapturedWord(draft.content, copiedText: pasted) }
                            catch { self.error = error.localizedDescription }
                        }
                    }.disabled(busy || draft.content.term.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    Text("仅发送此词、语境及粘贴内容；生成结果可编辑。未填释义的收藏暂不自动出题。")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            if let error { Text(error).font(.caption).foregroundStyle(.red) }
            HStack {
                Spacer()
                Button("取消", action: close).disabled(busy)
                Button("保存") {
                    do {
                        if let id = draft.existingID { try store.updateCapturedWord(id: id, payload: draft.content) }
                        else { try store.captureWord(draft.content) }
                        close()
                    } catch { self.error = error.localizedDescription }
                }.keyboardShortcut(.defaultAction).disabled(busy)
            }
        }.padding(24).frame(width: 590, height: 670)
    }

    private func optional(_ binding: Binding<String?>) -> Binding<String> {
        Binding(get: { binding.wrappedValue ?? "" }, set: { binding.wrappedValue = $0.isEmpty ? nil : $0 })
    }
}
