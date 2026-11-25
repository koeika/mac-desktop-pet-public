import AppKit
import CodexPetCore
import SwiftUI

struct PersonalVocabularyPanel: View {
    @ObservedObject var store: AppDataStore
    @State private var editing: CaptureDraft?
    @State private var search = ""
    @State private var filter = "全部"
    @State private var copied = false
    @State private var error: String?
    @State private var deleting: CapturedWord?

    private var words: [CapturedWord] {
        store.personalVocabulary.words.filter {
            (search.isEmpty || $0.content.term.localizedCaseInsensitiveContains(search) || $0.content.meaning.contains(search))
                && (filter == "全部" || stateLabel($0) == filter)
        }.sorted { $0.createdAt > $1.createdAt }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("我的生词本", systemImage: "bookmark").font(.headline)
                Spacer()
                Text("到期 \(store.dueVocabularyCount) · 收藏 \(store.personalVocabulary.words.count)")
                    .font(.caption).foregroundStyle(.secondary)
                Button { editing = CaptureDraft(content: CapturePayload(term: "")) } label: {
                    Label("收藏生词", systemImage: "plus")
                }
            }
            HStack {
                Button(copied ? "配对码已复制" : "复制 Chrome 配对码") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(store.captureToken, forType: .string)
                    copied = true
                }
                Text("127.0.0.1:\(String(store.settings.serverPort))").font(.caption.monospaced()).foregroundStyle(.secondary)
                Button("打开 Chrome 扩展文件夹") { openExtension() }
            }
            HStack {
                Stepper("每日新词 \(store.settings.dailyNewVocabularyLimit)", value: Binding(
                    get: { store.settings.dailyNewVocabularyLimit }, set: {
                        store.objectWillChange.send(); store.settings.dailyNewVocabularyLimit = $0; store.saveSettings()
                    }), in: 0...20)
                Toggle("先回忆再看释义", isOn: Binding(get: { store.settings.vocabularyRecallMode }, set: {
                    store.objectWillChange.send(); store.settings.vocabularyRecallMode = $0; store.saveSettings()
                })).toggleStyle(.switch)
            }
            HStack {
                Text("目标保持率 \(Int((store.settings.vocabularyRetention * 100).rounded()))%")
                Slider(value: Binding(get: { store.settings.vocabularyRetention }, set: {
                    store.objectWillChange.send(); store.settings.vocabularyRetention = $0; store.saveSettings()
                }), in: 0.8...0.95, step: 0.01).frame(maxWidth: 180)
                Spacer()
                ForEach(store.personalVocabulary.packs) { pack in
                    Toggle(pack.name, isOn: Binding(get: { store.settings.enabledDictionaryIDs.contains(pack.id) },
                        set: { store.toggleDictionary(pack.id, isEnabled: $0) }))
                        .toggleStyle(.checkbox).font(.caption)
                }
            }
            HStack {
                TextField("搜索生词或释义", text: $search)
                Picker("状态", selection: $filter) {
                    ForEach(["全部", "新收藏", "待加强", "已掌握"], id: \.self) { Text($0).tag($0) }
                }.frame(width: 190)
            }
            if let error { Text(error).foregroundStyle(.red).font(.caption) }
            if words.isEmpty { Text("暂无生词").foregroundStyle(.secondary).padding(.vertical, 12) }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(words) { word in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(word.content.term).font(.headline)
                                Text(stateLabel(word)).font(.caption).foregroundStyle(.secondary)
                                Spacer()
                                Button { editing = CaptureDraft(content: word.content, isEditing: true, existingID: word.id) } label: {
                                    Image(systemName: "pencil")
                                }.help("编辑词条")
                                Button { deleting = word } label: { Image(systemName: "trash") }.help("删除收藏")
                            }
                            Text(word.entry.phonetic ?? "").font(.caption).foregroundStyle(.secondary)
                            Text(word.content.meaning.isEmpty ? "待补充释义" : word.content.meaning).lineLimit(3)
                            if let sentence = word.entry.example { Text(sentence).font(.caption).lineLimit(3) }
                            if let translation = word.entry.exampleTranslation { Text(translation).font(.caption).foregroundStyle(.secondary).lineLimit(3) }
                            HStack {
                                Text(nextReviewText(word)).font(.caption).foregroundStyle(.secondary)
                                Spacer()
                                if let raw = word.content.sourceURL, let url = URL(string: raw) {
                                    Link(word.content.sourceTitle?.isEmpty == false ? word.content.sourceTitle! : "原网页", destination: url)
                                        .font(.caption).lineLimit(1)
                                }
                            }
                            DisclosureGroup("语境 \(word.contexts.count) · 复习记录") {
                                ForEach(Array(word.contexts.enumerated()), id: \.offset) { _, context in
                                    Text([context.example, context.translation, context.title].compactMap { $0 }.joined(separator: "\n"))
                                        .font(.caption).textSelection(.enabled)
                                }
                                ForEach(Array((store.vocabularyProgress.stats[word.statKey]?.review?.events ?? []).suffix(5).reversed()), id: \.id) { event in
                                    Text("\(event.at.formatted(date: .abbreviated, time: .shortened)) · \(event.action == .known ? "认识" : event.action == .hard ? "有点印象" : "不认识")")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            }.font(.caption)
                        }.padding(.vertical, 12)
                        Divider()
                    }
                }
            }.frame(height: words.isEmpty ? 0 : 300)
        }
        .padding(.vertical, 8)
        .sheet(item: $editing) { draft in
            CaptureEditor(store: store, draft: draft) { editing = nil }
        }
        .confirmationDialog("删除这个收藏？学习记录会保留。", isPresented: Binding(
            get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
            Button("删除", role: .destructive) {
                if let word = deleting { do { try store.deleteCapturedWord(word) } catch { self.error = error.localizedDescription } }
                deleting = nil
            }
        }
    }

    private func stateLabel(_ word: CapturedWord) -> String {
        guard let stat = store.vocabularyProgress.stats[word.statKey] else { return "新收藏" }
        if stat.learned { return "已掌握" }
        return stat.review == nil && stat.lastAction != .unknown && stat.lastAction != .hard ? "新收藏" : "待加强"
    }

    private func nextReviewText(_ word: CapturedWord) -> String {
        guard !word.content.meaning.isEmpty else { return "补充释义后开始复习" }
        guard let stat = store.vocabularyProgress.stats[word.statKey] else { return "等待首次学习" }
        let due = VocabularyReviewScheduler.dueDate(stat, now: Date())
        return due <= Date() ? "已到期" : "下次 \(due.formatted(date: .abbreviated, time: .shortened))"
    }

    private func openExtension() {
        let candidates = [Bundle.main.resourceURL?.appendingPathComponent("ChromeExtension"),
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("ChromeExtension")]
        if let url = candidates.compactMap({ $0 }).first(where: { FileManager.default.fileExists(atPath: $0.appendingPathComponent("manifest.json").path) }) {
            NSWorkspace.shared.open(url)
        } else { error = "请解压完整发布包，使用其中的 ChromeExtension 文件夹。" }
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
