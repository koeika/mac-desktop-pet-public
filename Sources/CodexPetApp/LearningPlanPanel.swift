import CodexPetCore
import SwiftUI

struct LearningPlanPanel: View {
    @ObservedObject var store: AppDataStore
    @ObservedObject var index: VocabularyLibraryIndex
    let studyNow: () -> Void
    @State private var search = ""
    @State private var enabledOnly = false
    @State private var page = 1
    @State private var pageSize = 4

    private var sources: [DictionarySummary] {
        index.learningDictionaries.filter {
            (!enabledOnly || $0.isEnabled) && (search.isEmpty || $0.pack.name.localizedCaseInsensitiveContains(search))
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("今天的学习").font(.title2.weight(.semibold))
                    Text(store.vocabularyScheduleStatusText()).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button(action: studyNow) { Label("继续学习", systemImage: "play.fill") }
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("learning-plan.continue")
                    .disabled(!index.learningDictionaries.contains { $0.isEnabled && !$0.pack.entries.isEmpty })
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), alignment: .leading)], alignment: .leading, spacing: 16) {
                metric("今日完成反馈", value: index.studyProgress.answeredToday, detail: "当前来源 · 词条去重")
                metric("其中新学", value: index.studyProgress.newLearnedToday, detail: "今天首次完成学习反馈")
                metric("其中复习", value: index.studyProgress.reviewedToday, detail: "以前学过，今天再复习")
                metric("到期待复习", value: index.studyProgress.due, detail: "随反馈和时间更新")
            }
            if index.studyProgress.unclassifiedToday > 0 {
                Text("另有 \(index.studyProgress.unclassifiedToday) 个旧记录词条，无法追溯首次学习日期，未区分为新学或复习。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            todayPlan
            DisclosureGroup("学习方法：主动回忆 + FSRS 间隔复习") {
                methodDetails.padding(.top, 10)
            }
            Divider()
            sourceProgress
        }
    }

    private var methodDetails: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(store.settings.vocabularyRecallMode ? "先回忆，再查看释义，最后按实际记忆程度反馈。" : "当前直接展示释义；反馈仍参与下次复习安排。")
            Text("到期词优先；每 4 次自动展示预留 1 次新词机会，新词名额用完后只复习。新收藏优先于词典中的普通新词；同一词两次展示至少间隔 10 分钟。")
            Text("不认识 / 有点印象 / 认识啦分别参与 FSRS 计算，下次时间以词卡按钮提示为准；稍后再看延后一天，不算完成学习。")
            Text("已学表示至少完成一次反馈，不代表永久掌握；已认识表示最近一次反馈为认识。旧版没有逐次记录的学习，只计累计进度，不补造历史。")
                .foregroundStyle(.secondary)
        }.font(.callout).fixedSize(horizontal: false, vertical: true)
    }

    private func metric(_ title: String, value: Int, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text("\(value)").font(.system(size: 26, weight: .semibold)).monospacedDigit()
            Text(detail).font(.caption2).foregroundStyle(.secondary)
        }
    }

    private var todayPlan: some View {
        let sameDay = store.settings.vocabularyShownCountDate == VocabularyDisplayScheduler.todayKey(for: Date())
        let introduced = sameDay ? store.settings.newVocabularyKeys.count : 0
        let left = max(0, store.settings.dailyNewVocabularyLimit - introduced)
        let newText = store.settings.dailyNewVocabularyUnlimited ? "新词不限量" : "自动新词还可首次展示 \(left) 个"
        return VStack(alignment: .leading, spacing: 7) {
            Text("待办：复习 \(index.studyProgress.due) 个到期词 · \(newText)")
                .font(.subheadline.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
            if index.studyProgress.pendingFeedback > 0 {
                Text("另有 \(index.studyProgress.pendingFeedback) 个已出题但未完成反馈的词，仍会进入学习队列。")
                    .font(.callout)
            }
            if index.studyProgress.total == 0 {
                Text("尚未选择学习来源。在下方启用词典或生词本。")
            } else if index.studyProgress.due == 0, let next = index.studyProgress.nextReview {
                Text("当前没有到期复习，下次到期：\(next.formatted(date: .abbreviated, time: .shortened))。")
            }
            Text("新词名额按自动首次展示计，不等于完成数；手动学习不受时段和自动上限限制。未反馈的词仍待学习，自动弹出也不会替你完成任务。")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var sourceProgress: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("参与计划的词典").font(.headline)
                Spacer()
                Text("已启用 \(index.learningDictionaries.filter(\.isEnabled).count) 个来源")
                    .font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                TextField("搜索词典或生词本", text: $search).textFieldStyle(.roundedBorder)
                Toggle("只看已启用", isOn: $enabledOnly).toggleStyle(.checkbox).fixedSize()
            }
            let result = LibraryPage(count: sources.count, size: pageSize, requested: page)
            if sources.isEmpty { Text("没有符合条件的学习来源").foregroundStyle(.secondary) }
            ForEach(Array(sources[result.range])) { source in
                HStack(spacing: 12) {
                    Image(systemName: "book.closed").foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(source.pack.name).font(.subheadline.weight(.semibold))
                            .lineLimit(2).fixedSize(horizontal: false, vertical: true)
                        Text("\(source.studyProgress.total) 个词")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Toggle("参与学习", isOn: Binding(get: { store.settings.enabledDictionaryIDs.contains(source.id) },
                        set: { store.toggleDictionary(source.id, isEnabled: $0) }))
                        .toggleStyle(.switch).fixedSize()
                        .accessibilityIdentifier("learning-plan.source.\(source.id)")
                }.padding(.vertical, 10)
                Divider()
            }
            LibraryPagination(count: sources.count, page: $page, pageSize: $pageSize, sizes: [4, 12, 24])
        }
        .onChange(of: search) { _, _ in page = 1 }
        .onChange(of: enabledOnly) { _, _ in page = 1 }
    }
}

struct DictionaryStudyProgressView: View {
    let progress: VocabularyStudyProgress

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("已学 \(progress.studied) / \(progress.total)")
                Spacer()
                Text(progress.fraction, format: .percent.precision(.fractionLength(0)))
            }.font(.caption).monospacedDigit()
            ProgressView(value: progress.fraction).accessibilityLabel("词典学习进度")
        }
        .help("按已完成学习反馈的不同词条计数；重复展示不增加进度，已学不等于永久掌握。")
    }
}
