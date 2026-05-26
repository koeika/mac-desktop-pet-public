import AppKit
import CodexPetCore
import SwiftUI
import UniformTypeIdentifiers

struct SettingsActions {
    var uploadPhotos: () -> Void
    var importPetPackage: () -> Void
    var randomPreview: () -> Void
    var importDictionary: () -> Void
    var openCSVTemplate: () -> Void
    var openJSONTemplate: () -> Void
    var showImportFormat: () -> Void
    var sendTestProgress: () -> Void
    var chooseSyncFolder: () -> Void
    var watchLogFile: () -> Void
}

final class SettingsWindowController {
    private let window: NSWindow

    init(store: AppDataStore, actions: SettingsActions) {
        let rootView = SettingsCenterView(store: store, actions: actions)
        let hostingController = NSHostingController(rootView: rootView)
        window = NSWindow(contentViewController: hostingController)
        window.title = "\(AppBrand.displayName) 配置中心"
        window.setContentSize(NSSize(width: 980, height: 720))
        window.minSize = NSSize(width: 880, height: 620)
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.center()
    }

    func show() {
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

struct SettingsCenterView: View {
    @ObservedObject var store: AppDataStore
    let actions: SettingsActions
    @State private var selection: SettingsTab = .pets

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
            content
        }
        .frame(minWidth: 880, minHeight: 620)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 5) {
                Text(AppBrand.displayName)
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                Text("配置宠物、词典和 AI 进度接入")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 22)

            VStack(spacing: 8) {
                tabButton(.pets)
                tabButton(.dictionary)
                tabButton(.progress)
            }

            Spacer()

            VStack(alignment: .leading, spacing: 8) {
                Text("本地服务")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text("127.0.0.1:\(store.settings.serverPort)")
                    .font(.system(.body, design: .monospaced))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
            }
        }
        .padding(.horizontal, 18)
        .frame(width: 230)
        .background(
            LinearGradient(
                colors: [
                    Color(nsColor: .controlBackgroundColor),
                    Color(nsColor: .windowBackgroundColor)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }

    private var content: some View {
        Group {
            switch selection {
            case .pets:
                PetGalleryTab(store: store, actions: actions)
            case .dictionary:
                DictionaryTab(store: store, actions: actions)
            case .progress:
                ProgressConnectTab(store: store, actions: actions)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func tabButton(_ tab: SettingsTab) -> some View {
        Button {
            selection = tab
        } label: {
            HStack(spacing: 10) {
                Image(systemName: tab.icon)
                    .frame(width: 20)
                VStack(alignment: .leading, spacing: 2) {
                    Text(tab.title)
                        .font(.system(size: 14, weight: .semibold))
                    Text(tab.subtitle)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(12)
            .background(selection == tab ? Color.accentColor.opacity(0.16) : Color.clear, in: RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }
}

enum SettingsTab: CaseIterable {
    case pets
    case dictionary
    case progress

    var title: String {
        switch self {
        case .pets: return "宠物管理"
        case .dictionary: return "词典学习"
        case .progress: return "AI 进度接入"
        }
    }

    var subtitle: String {
        switch self {
        case .pets: return "上传、启用、权重"
        case .dictionary: return "导入和复习统计"
        case .progress: return "命令、HTTP、事件"
        }
    }

    var icon: String {
        switch self {
        case .pets: return "pawprint.fill"
        case .dictionary: return "character.book.closed.fill"
        case .progress: return "bolt.horizontal.circle.fill"
        }
    }
}

struct PetGalleryTab: View {
    @ObservedObject var store: AppDataStore
    let actions: SettingsActions
    @State private var installURLText = ""
    @State private var isPreparingInstall = false
    @State private var installPreview: PetInstallPreview?
    @State private var installError: String?
    @State private var installSuccess: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                sectionHeader("宠物管理", subtitle: "上传图片/GIF/视频，从在线链接安装 Codex pet，或导入已解压的宠物包。")

                HStack(alignment: .top, spacing: 18) {
                    heroPreview
                    VStack(spacing: 12) {
                        PrimaryActionButton(title: "上传宠物素材", systemImage: "photo.badge.plus", action: actions.uploadPhotos)
                        speedPanel
                        urlInstallPanel
                        SecondaryActionButton(title: "导入 Codex pet 包", systemImage: "folder.badge.plus", action: actions.importPetPackage)
                        SecondaryActionButton(title: "随机预览一次", systemImage: "shuffle", action: actions.randomPreview)
                    }
                    .frame(width: 260)
                }

                clickFeedbackPanel

                Text("宠物库")
                    .font(.headline)

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 210), spacing: 14)], spacing: 14) {
                    ForEach(store.pets) { pet in
                        PetCard(store: store, pet: pet)
                    }
                    if store.pets.isEmpty {
                        EmptyGalleryCard()
                    }
                }
                .padding(.bottom, 12)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.trailing, 4)
        }
        .sheet(item: $installPreview) { preview in
            InstallPreviewSheet(
                store: store,
                preview: preview,
                onInstall: {
                    installPet(preview)
                },
                onCancel: {
                    store.discardInstallPreview(preview)
                    installPreview = nil
                }
            )
        }
    }

    private var urlInstallPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "link.badge.plus")
                    .foregroundStyle(.tint)
                Text("从 URL 安装")
                    .font(.headline)
                Spacer()
                if isPreparingInstall {
                    ProgressView()
                        .controlSize(.small)
                }
            }
            TextField("粘贴 codex-pets.net 或 .zip 链接", text: $installURLText)
                .textFieldStyle(.roundedBorder)
            Button {
                prepareInstall()
            } label: {
                Label(isPreparingInstall ? "正在解析" : "预览并安装", systemImage: "arrow.down.app.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(isPreparingInstall || installURLText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            if let installError {
                Text(installError)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            } else if let installSuccess {
                Text(installSuccess)
                    .font(.caption)
                    .foregroundStyle(.green)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("会先下载并展示预览，确认后再写入本 App 和 Codex 宠物目录。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 14))
    }

    private var clickFeedbackPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("点击反馈", systemImage: "hand.tap.fill")
                    .font(.headline)
                Spacer()
                Text("\(store.settings.petClickFeedbackPhrases.count) / 5")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Text("点击桌宠时会随机说一句。建议配置 3-5 条短句。")
                .font(.caption)
                .foregroundStyle(.secondary)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 210), spacing: 10)], spacing: 10) {
                ForEach(Array(store.settings.petClickFeedbackPhrases.indices), id: \.self) { index in
                    HStack(spacing: 6) {
                        TextField(
                            "反馈词 \(index + 1)",
                            text: Binding(
                                get: { store.settings.petClickFeedbackPhrases[index] },
                                set: { store.setPetClickFeedbackPhrase(index: index, phrase: $0) }
                            )
                        )
                        .textFieldStyle(.roundedBorder)
                        Button {
                            store.removePetClickFeedbackPhrase(at: index)
                        } label: {
                            Image(systemName: "minus.circle.fill")
                        }
                        .buttonStyle(.borderless)
                        .foregroundStyle(.secondary)
                        .disabled(store.settings.petClickFeedbackPhrases.count <= 3)
                        .help("至少保留 3 条反馈词")
                    }
                }
            }

            Button {
                store.addPetClickFeedbackPhrase()
            } label: {
                Label("增加反馈词", systemImage: "plus.circle.fill")
            }
            .buttonStyle(.borderless)
            .disabled(store.settings.petClickFeedbackPhrases.count >= 5)
        }
        .padding(14)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 14))
    }

    private var speedPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("移动速度", systemImage: "tortoise.fill")
                    .font(.headline)
                Spacer()
                Text(String(format: "%.2fx", store.settings.movementSpeedMultiplier))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            Slider(
                value: Binding(
                    get: { store.settings.movementSpeedMultiplier },
                    set: { store.setMovementSpeedMultiplier($0) }
                ),
                in: 0.1...1.4
            )
            Text("默认 0.20x；可以降到 0.10x。桌宠会经常停住做动作，不会一直走。")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 14))
    }

    private func prepareInstall() {
        let input = installURLText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty else { return }
        isPreparingInstall = true
        installError = nil
        installSuccess = nil
        Task {
            do {
                let preview = try await store.prepareRemotePetInstall(from: input)
                await MainActor.run {
                    installPreview = preview
                    isPreparingInstall = false
                }
            } catch {
                await MainActor.run {
                    installError = error.localizedDescription
                    isPreparingInstall = false
                }
            }
        }
    }

    private func installPet(_ preview: PetInstallPreview) {
        do {
            _ = try store.installRemotePet(preview, overwrite: preview.alreadyInstalled)
            installSuccess = "已安装 \(preview.displayName)"
            installPreview = nil
            installURLText = ""
            actions.randomPreview()
        } catch {
            installError = error.localizedDescription
            installPreview = nil
        }
    }

    private var heroPreview: some View {
        HStack(spacing: 20) {
            ZStack {
                RoundedRectangle(cornerRadius: 24)
                    .fill(
                        LinearGradient(
                            colors: [Color.cyan.opacity(0.18), Color.indigo.opacity(0.12), Color.orange.opacity(0.12)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                RoundedRectangle(cornerRadius: 24)
                    .stroke(Color.white.opacity(0.45), lineWidth: 1)
                if let pet = store.enabledPets().first ?? store.pets.first,
                   let image = store.previewImage(for: pet) {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                        .padding(22)
                        .shadow(color: .black.opacity(0.18), radius: 14, y: 8)
                } else {
                    PixelPetPreview()
                        .frame(width: 120, height: 120)
                }
                Ellipse()
                    .fill(Color.black.opacity(0.12))
                    .frame(width: 150, height: 18)
                    .offset(y: 82)
            }
            .frame(width: 260, height: 210)

            VStack(alignment: .leading, spacing: 10) {
                Text("当前会随机出现")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text("\(store.enabledPets().count) 只已启用宠物")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                Text("权重越高，宠物越常出现。GIF/视频会循环播放；静态照片拟真有限。")
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
        .padding(18)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22))
    }
}

struct PetCard: View {
    @ObservedObject var store: AppDataStore
    let pet: PetAsset

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ZStack(alignment: .bottomTrailing) {
                RoundedRectangle(cornerRadius: 18)
                    .fill(Color(nsColor: .controlBackgroundColor))
                    .frame(height: 128)
                if let image = store.previewImage(for: pet) {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                        .padding(16)
                        .frame(height: 128)
                        .frame(maxWidth: .infinity)
                }
                Text(pet.mediaLabel)
                    .font(.caption2.weight(.bold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(.thinMaterial, in: Capsule())
                    .padding(10)
            }

            Text(pet.name)
                .font(.system(size: 15, weight: .semibold))
                .lineLimit(1)

            Toggle("启用", isOn: Binding(
                get: { pet.isEnabled },
                set: { store.setPetEnabled(pet, isEnabled: $0) }
            ))
            .toggleStyle(.switch)

            if pet.kind == .codexPackage, let renderer = store.spriteRenderer(for: pet) {
                ActionPreviewStrip(renderer: renderer)
            } else if pet.kind == .photo {
                Text("静态照片拟真有限；建议上传 GIF/视频或安装 Codex pet 包。")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text("出现权重")
                    Spacer()
                    Text(String(format: "%.1f", pet.weight))
                        .foregroundStyle(.secondary)
                }
                Slider(
                    value: Binding(
                        get: { pet.weight },
                        set: { store.setPetWeight(pet, weight: $0) }
                    ),
                    in: 0.1...5
                )
            }
            .font(.caption)

            HStack {
                Text("出现 \(pet.appearances) 次")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button(role: .destructive) {
                    store.deletePet(pet)
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(14)
        .background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.black.opacity(0.08)))
    }
}

struct InstallPreviewSheet: View {
    @ObservedObject var store: AppDataStore
    let preview: PetInstallPreview
    let onInstall: () -> Void
    let onCancel: () -> Void

    private var spriteURL: URL {
        preview.packageDirectoryURL.appendingPathComponent(preview.spriteFileName)
    }

    private var previewImage: NSImage? {
        if let previewFileName = preview.previewFileName {
            return NSImage(contentsOf: preview.packageDirectoryURL.appendingPathComponent(previewFileName))
        }
        return PetAnimationRenderer(spriteURL: spriteURL, framesPerAction: preview.framesPerAction)?.stillFrame()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 18) {
                ZStack {
                    RoundedRectangle(cornerRadius: 20)
                        .fill(Color(nsColor: .controlBackgroundColor))
                    if let previewImage {
                        Image(nsImage: previewImage)
                            .resizable()
                            .scaledToFit()
                            .padding(24)
                    } else {
                        PixelPetPreview()
                            .frame(width: 120, height: 120)
                    }
                }
                .frame(width: 220, height: 190)

                VStack(alignment: .leading, spacing: 10) {
                    Text("安装预览")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(preview.displayName)
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                    Text(preview.description ?? "这个宠物包包含 pet.json 和 spritesheet，可安装为桌面宠物。")
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 8) {
                        Label("原生 9 动作", systemImage: "sparkles")
                        Label("\(preview.framesPerAction) 帧/动作", systemImage: "film.stack")
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    if preview.alreadyInstalled {
                        Text("已安装同名宠物，确认后会覆盖更新。")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
                Spacer()
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("动作预览")
                    .font(.headline)
                ActionPreviewGrid(spriteURL: spriteURL, framesPerAction: preview.framesPerAction)
            }

            HStack {
                Button("取消", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button(preview.alreadyInstalled ? "覆盖安装" : "确认安装", action: onInstall)
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 720)
    }
}

struct ActionPreviewGrid: View {
    let renderer: PetAnimationRenderer?

    init(spriteURL: URL, framesPerAction: Int) {
        renderer = PetAnimationRenderer(spriteURL: spriteURL, framesPerAction: framesPerAction)
    }

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 94), spacing: 10)], spacing: 10) {
            ForEach(CodexPetAction.allCases) { action in
                VStack(spacing: 7) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color(nsColor: .controlBackgroundColor))
                        if let image = renderer?.stillFrame(for: action) {
                            Image(nsImage: image)
                                .resizable()
                                .interpolation(.none)
                                .scaledToFit()
                                .padding(10)
                        }
                    }
                    .frame(height: 68)
                    Text(action.chineseName)
                        .font(.caption2.weight(.semibold))
                        .lineLimit(1)
                }
            }
        }
    }
}

struct ActionPreviewStrip: View {
    let renderer: PetAnimationRenderer

    var body: some View {
        HStack(spacing: 5) {
            ForEach([CodexPetAction.idle, .runningRight, .waving, .jumping, .failed], id: \.self) { action in
                ZStack {
                    RoundedRectangle(cornerRadius: 7)
                        .fill(Color(nsColor: .controlBackgroundColor))
                    if let image = renderer.stillFrame(for: action) {
                        Image(nsImage: image)
                            .resizable()
                            .interpolation(.none)
                            .scaledToFit()
                            .padding(4)
                    }
                }
                .frame(width: 34, height: 30)
                .help(action.displayName)
            }
            Spacer(minLength: 0)
        }
    }
}

struct EmptyGalleryCard: View {
    var body: some View {
        VStack(spacing: 12) {
            PixelPetPreview()
                .frame(width: 94, height: 94)
            Text("还没有上传宠物")
                .font(.headline)
            Text("点击上方按钮上传图片、GIF 或视频。静态图片会自动抠图，GIF/视频会循环播放。")
                .font(.caption)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 18))
    }
}

struct DictionaryTab: View {
    @ObservedObject var store: AppDataStore
    let actions: SettingsActions
    @State private var pdfDraft: DictionaryImportDraft?
    @State private var isImportingPDF = false
    @State private var importError: String?
    @State private var importSuccess: String?
    @State private var apiKeyInput = ""
    @State private var apiKeySaved = false
    @State private var modelInput = ""
    @State private var deepSeekBaseURLInput = ""
    @State private var selectedCategory = "全部"

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                sectionHeader("词典学习", subtitle: "导入 CSV/JSON 或可复制文本 PDF，确认后启用词典。")

                HStack(spacing: 12) {
                    PrimaryActionButton(title: "导入 CSV/JSON 词典", systemImage: "square.and.arrow.down", action: actions.importDictionary)
                    PrimaryActionButton(title: isImportingPDF ? "PDF 解析中..." : "导入 PDF 词典", systemImage: "doc.richtext", action: importPDFDictionary)
                    SecondaryActionButton(title: "打开 CSV 模板", systemImage: "tablecells", action: actions.openCSVTemplate)
                    SecondaryActionButton(title: "打开 JSON 模板", systemImage: "curlybraces", action: actions.openJSONTemplate)
                    SecondaryActionButton(title: "查看导入格式", systemImage: "questionmark.circle", action: actions.showImportFormat)
                }

                learningPacePanel

                openAISettingsPanel

                dictionaryCategoryFilter

                if let importError {
                    Text(importError)
                        .font(.caption)
                        .foregroundStyle(.red)
                } else if let importSuccess {
                    Text(importSuccess)
                        .font(.caption)
                        .foregroundStyle(.green)
                }

                if filteredDictionarySummaries.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "tray")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                        Text("这个分类下还没有词典")
                            .font(.headline)
                        Text("可以编辑词典卡片的分类，或导入新的词典。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(28)
                    .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 16))
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 260), spacing: 14)], spacing: 14) {
                        ForEach(filteredDictionarySummaries) { summary in
                            DictionaryCard(store: store, summary: summary)
                        }
                    }
                    .padding(.bottom, 12)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.trailing, 4)
        }
        .sheet(item: $pdfDraft) { draft in
            DictionaryDraftSheet(
                initialDraft: draft,
                onSave: { draftToSave in
                    do {
                        let pack = try store.importDictionaryDraft(draftToSave)
                        importSuccess = "已导入 \(pack.entries.count) 个词：\(pack.name)"
                        importError = nil
                        pdfDraft = nil
                    } catch {
                        importError = error.localizedDescription
                    }
                },
                onCancel: {
                    pdfDraft = nil
                },
                generateExamples: { draftToGenerate in
                    try await store.generateExamples(for: draftToGenerate)
                },
                parseWithDeepSeek: { draftToParse in
                    try await store.parsePDFDraftWithDeepSeek(draftToParse)
                }
            )
        }
        .onAppear {
            syncProviderInputs()
        }
    }

    private var dictionaryCategoryFilter: some View {
        let summaries = store.dictionarySummaries()
        let categories = dictionaryCategories(from: summaries)
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("分类筛选", systemImage: "line.3.horizontal.decrease.circle")
                    .font(.headline)
                Spacer()
                Text("当前显示 \(filteredDictionarySummaries.count) 个词典")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(categories, id: \.self) { category in
                        categoryFilterButton(
                            title: category,
                            count: dictionaryCount(for: category, in: summaries)
                        )
                    }
                }
                .padding(.vertical, 1)
            }
        }
        .padding(14)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 14))
    }

    private var filteredDictionarySummaries: [DictionarySummary] {
        let summaries = store.dictionarySummaries()
        let validSelection = dictionaryCategories(from: summaries).contains(selectedCategory) ? selectedCategory : "全部"
        guard validSelection != "全部" else { return summaries }
        return summaries.filter { dictionaryCategoryLabel($0) == validSelection }
    }

    private func categoryFilterButton(title: String, count: Int) -> some View {
        let isSelected = title == selectedCategory || (!dictionaryCategories(from: store.dictionarySummaries()).contains(selectedCategory) && title == "全部")
        return Button {
            selectedCategory = title
        } label: {
            HStack(spacing: 6) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text("\(count)")
                    .font(.caption2.weight(.bold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(isSelected ? Color.white.opacity(0.22) : Color.black.opacity(0.06), in: Capsule())
            }
            .foregroundStyle(isSelected ? Color.white : Color.primary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(isSelected ? Color.accentColor : Color(nsColor: .windowBackgroundColor), in: Capsule())
            .overlay(Capsule().stroke(Color.black.opacity(isSelected ? 0 : 0.08)))
        }
        .buttonStyle(.plain)
    }

    private func dictionaryCategories(from summaries: [DictionarySummary]) -> [String] {
        let categories = Set(summaries.map(dictionaryCategoryLabel))
        let sorted = categories.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        return ["全部"] + sorted
    }

    private func dictionaryCount(for category: String, in summaries: [DictionarySummary]) -> Int {
        guard category != "全部" else { return summaries.count }
        return summaries.filter { dictionaryCategoryLabel($0) == category }.count
    }

    private func dictionaryCategoryLabel(_ summary: DictionarySummary) -> String {
        let category = summary.category?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return category.isEmpty ? "未分类" : category
    }

    private var learningPacePanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("学习节奏", systemImage: "clock.badge.checkmark")
                    .font(.headline)
                Spacer()
                Text(store.vocabularyScheduleStatusText())
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(alignment: .top, spacing: 16) {
                Stepper(
                    value: Binding(
                        get: { store.settings.dailyVocabularyLimit },
                        set: { store.setDailyVocabularyLimit($0) }
                    ),
                    in: 1...50
                ) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("每天自动展示 \(store.settings.dailyVocabularyLimit) 个词")
                            .font(.subheadline.weight(.semibold))
                        Text("范围 1-50；手动抽词不受限制。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("每天学习时段")
                        .font(.subheadline.weight(.semibold))
                    HStack(spacing: 8) {
                        DatePicker(
                            "开始",
                            selection: Binding(
                                get: { dateForMinute(store.settings.vocabularyStudyStartMinute) },
                                set: { store.setVocabularyStudyStartMinute(minuteOfDay($0)) }
                            ),
                            displayedComponents: .hourAndMinute
                        )
                        DatePicker(
                            "结束",
                            selection: Binding(
                                get: { dateForMinute(store.settings.vocabularyStudyEndMinute) },
                                set: { store.setVocabularyStudyEndMinute(minuteOfDay($0)) }
                            ),
                            displayedComponents: .hourAndMinute
                        )
                    }
                    Text("默认 10:00-18:00；结束时间必须晚于开始时间。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Toggle(
                    "词汇题持续展示直到反馈",
                    isOn: Binding(
                        get: { store.settings.vocabularyQuestionPersists },
                        set: { store.setVocabularyQuestionPersists($0) }
                    )
                )
                .toggleStyle(.switch)
            }
        }
        .padding(14)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 14))
    }

    private func dateForMinute(_ minute: Int) -> Date {
        Calendar.current.startOfDay(for: Date())
            .addingTimeInterval(TimeInterval(VocabularyDisplayScheduler.normalizedMinuteOfDay(minute) * 60))
    }

    private func minuteOfDay(_ date: Date) -> Int {
        VocabularyDisplayScheduler.minuteOfDay(for: date)
    }

    private var openAISettingsPanel: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("例句补充供应商", systemImage: "sparkles")
                    .font(.headline)
                Spacer()
                Text(apiKeySaved ? "\(store.settings.exampleProvider.displayName) key 已保存" : "未配置 \(store.settings.exampleProvider.displayName) key")
                    .font(.caption)
                    .foregroundStyle(apiKeySaved ? .green : .secondary)
            }
            Picker("供应商", selection: Binding(
                get: { store.settings.exampleProvider },
                set: { provider in
                    store.setExampleProvider(provider)
                    syncProviderInputs()
                }
            )) {
                ForEach(ExampleProvider.allCases) { provider in
                    Text(provider.displayName).tag(provider)
                }
            }
            .pickerStyle(.segmented)

            HStack(spacing: 10) {
                SecureField(apiKeyPlaceholder, text: $apiKeyInput)
                    .textFieldStyle(.roundedBorder)
                TextField("模型", text: $modelInput)
                .textFieldStyle(.roundedBorder)
                .frame(width: 150)
                Button(apiKeySaved ? "更新" : "保存") {
                    do {
                        if !apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            try KeychainStore.saveExampleAPIKey(apiKeyInput, provider: store.settings.exampleProvider)
                        }
                        applyProviderSettings()
                        apiKeyInput = ""
                        refreshAPIKeyState()
                        importError = nil
                        importSuccess = "\(store.settings.exampleProvider.displayName) 设置已保存。"
                    } catch {
                        importError = error.localizedDescription
                    }
                }
                .disabled(!hasProviderInputChanges)
            }

            if store.settings.exampleProvider == .deepSeek {
                TextField("DeepSeek Base URL", text: $deepSeekBaseURLInput)
                .textFieldStyle(.roundedBorder)
            }

            if apiKeySaved, apiKeyInput.isEmpty {
                Label("Key 已保存在 macOS Keychain；出于安全不会回显明文。输入新 key 后点“更新”即可替换。", systemImage: "lock.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
            }

            Text(providerHelpText)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 14))
    }

    private var apiKeyPlaceholder: String {
        if apiKeySaved {
            return "\(store.settings.exampleProvider.displayName) key 已保存，输入新 key 可替换"
        }
        return "\(store.settings.exampleProvider.displayName) API key"
    }

    private var hasProviderInputChanges: Bool {
        if !apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return true
        }
        switch store.settings.exampleProvider {
        case .openAI:
            return modelInput.trimmingCharacters(in: .whitespacesAndNewlines) != store.settings.openAIModel
        case .deepSeek:
            return modelInput.trimmingCharacters(in: .whitespacesAndNewlines) != store.settings.deepSeekModel
                || deepSeekBaseURLInput.trimmingCharacters(in: .whitespacesAndNewlines) != store.settings.deepSeekBaseURL
        }
    }

    private var providerHelpText: String {
        switch store.settings.exampleProvider {
        case .openAI:
            return "OpenAI 使用 Responses API + 结构化输出；只发送单词、释义、读音/音标和少量上下文。"
        case .deepSeek:
            return "DeepSeek 使用 OpenAI-compatible Chat Completions + JSON 输出；默认模型 deepseek-chat，默认 Base URL https://api.deepseek.com。"
        }
    }

    private func refreshAPIKeyState() {
        apiKeySaved = KeychainStore.hasExampleAPIKey(provider: store.settings.exampleProvider)
    }

    private func syncProviderInputs() {
        refreshAPIKeyState()
        apiKeyInput = ""
        switch store.settings.exampleProvider {
        case .openAI:
            modelInput = store.settings.openAIModel
            deepSeekBaseURLInput = store.settings.deepSeekBaseURL
        case .deepSeek:
            modelInput = store.settings.deepSeekModel
            deepSeekBaseURLInput = store.settings.deepSeekBaseURL
        }
    }

    private func applyProviderSettings() {
        switch store.settings.exampleProvider {
        case .openAI:
            store.setOpenAIModel(modelInput)
        case .deepSeek:
            store.setDeepSeekModel(modelInput)
            store.setDeepSeekBaseURL(deepSeekBaseURLInput)
        }
        syncProviderInputs()
    }

    private func importPDFDictionary() {
        guard !isImportingPDF else { return }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.pdf]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.prompt = "解析 PDF"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        isImportingPDF = true
        importError = nil
        importSuccess = nil
        Task.detached {
            do {
                let draft = try PDFDictionaryImporter.draft(fromPDF: url)
                await MainActor.run {
                    pdfDraft = draft
                    isImportingPDF = false
                }
            } catch {
                await MainActor.run {
                    importError = error.localizedDescription
                    importSuccess = nil
                    isImportingPDF = false
                }
            }
        }
    }
}

struct DictionaryDraftSheet: View {
    @State private var draft: DictionaryImportDraft
    @State private var isGenerating = false
    @State private var isAIParsing = false
    @State private var error: String?
    let onSave: (DictionaryImportDraft) -> Void
    let onCancel: () -> Void
    let generateExamples: (DictionaryImportDraft) async throws -> DictionaryImportDraft
    let parseWithDeepSeek: (DictionaryImportDraft) async throws -> DictionaryImportDraft

    init(
        initialDraft: DictionaryImportDraft,
        onSave: @escaping (DictionaryImportDraft) -> Void,
        onCancel: @escaping () -> Void,
        generateExamples: @escaping (DictionaryImportDraft) async throws -> DictionaryImportDraft,
        parseWithDeepSeek: @escaping (DictionaryImportDraft) async throws -> DictionaryImportDraft
    ) {
        _draft = State(initialValue: initialDraft)
        self.onSave = onSave
        self.onCancel = onCancel
        self.generateExamples = generateExamples
        self.parseWithDeepSeek = parseWithDeepSeek
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("PDF 词典导入预览")
                        .font(.system(size: 24, weight: .bold, design: .rounded))
                    Text("\(draft.sourceFileName) · 识别 \(draft.entries.count) 个候选词 · \(draft.entries.filter(\.needsReview).count) 个待确认")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(isAIParsing ? "DeepSeek 解析中..." : "用 DeepSeek 解析 PDF") {
                    parsePDFWithDeepSeek()
                }
                .disabled(isAIParsing || isGenerating)
                Button(isGenerating ? "生成中..." : "为缺失项生成例句") {
                    generateMissingExamples()
                }
                .disabled(isGenerating || isAIParsing || draft.entries.allSatisfy { !($0.example ?? "").isEmpty })
            }

            TextField("词典名称", text: $draft.dictionaryName)
                .textFieldStyle(.roundedBorder)

            if let error {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            ScrollView {
                VStack(spacing: 10) {
                    ForEach($draft.entries) { $entry in
                        DraftEntryRow(entry: $entry)
                    }
                }
                .padding(.vertical, 4)
            }
            .frame(minHeight: 360)

            HStack {
                if !draft.rejectedLines.isEmpty {
                    Text("未识别行 \(draft.rejectedLines.count) 条，已保留在草稿信息中。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("取消", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("确认导入") {
                    onSave(draft)
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(draft.entries.filter { !$0.term.isEmpty && !$0.meaning.isEmpty }.isEmpty)
            }
        }
        .padding(24)
        .frame(width: 900, height: 680)
    }

    private func generateMissingExamples() {
        isGenerating = true
        error = nil
        Task {
            do {
                let updated = try await generateExamples(draft)
                await MainActor.run {
                    draft = updated
                    isGenerating = false
                }
            } catch {
                await MainActor.run {
                    self.error = error.localizedDescription
                    isGenerating = false
                }
            }
        }
    }

    private func parsePDFWithDeepSeek() {
        isAIParsing = true
        error = nil
        Task {
            do {
                let updated = try await parseWithDeepSeek(draft)
                await MainActor.run {
                    draft = updated
                    isAIParsing = false
                }
            } catch {
                await MainActor.run {
                    self.error = error.localizedDescription
                    isAIParsing = false
                }
            }
        }
    }
}

struct DraftEntryRow: View {
    @Binding var entry: DictionaryImportDraftEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                TextField("term", text: $entry.term)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 150)
                TextField("reading/phonetic", text: Binding(
                    get: { entry.phonetic ?? entry.reading ?? "" },
                    set: { value in
                        if containsJapanese(entry.term) {
                            entry.reading = value.nilIfBlank
                        } else {
                            entry.phonetic = value.nilIfBlank
                        }
                    }
                ))
                .textFieldStyle(.roundedBorder)
                .frame(width: 150)
                TextField("meaning", text: $entry.meaning)
                    .textFieldStyle(.roundedBorder)
                Toggle("待确认", isOn: $entry.needsReview)
                    .toggleStyle(.checkbox)
                    .frame(width: 78)
            }
            TextField("example", text: Binding(
                get: { entry.example ?? "" },
                set: { entry.example = $0.nilIfBlank }
            ))
            .textFieldStyle(.roundedBorder)
            if !entry.context.isEmpty {
                Text(entry.context)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(10)
        .background(entry.needsReview ? Color.orange.opacity(0.10) : Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
    }

    private func containsJapanese(_ value: String) -> Bool {
        value.unicodeScalars.contains { scalar in
            (0x3040...0x30ff).contains(Int(scalar.value))
        }
    }
}

struct DictionaryCard: View {
    @ObservedObject var store: AppDataStore
    let summary: DictionarySummary
    @State private var isEditing = false
    @State private var nameInput = ""
    @State private var categoryInput = ""
    @State private var error: String?
    @State private var confirmDelete = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(summary.pack.name)
                        .font(.system(size: 16, weight: .bold))
                    Text("\(summary.pack.entries.count) 个词")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Toggle("", isOn: Binding(
                    get: { summary.isEnabled },
                    set: { store.toggleDictionary(summary.pack.id, isEnabled: $0) }
                ))
                .toggleStyle(.switch)
            }
            HStack(spacing: 6) {
                Text(summary.category ?? "未分类")
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.green.opacity(0.12), in: Capsule())
                    .foregroundStyle(.green)
                if summary.isBuiltIn {
                    Text("内置")
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.blue.opacity(0.10), in: Capsule())
                        .foregroundStyle(.blue)
                }
            }
            if let description = summary.pack.description {
                let visibleDescription = description.components(separatedBy: "\n").filter { !$0.hasPrefix("分类：") }.joined(separator: "\n")
                if !visibleDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(visibleDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            HStack(spacing: 8) {
                StatPill(label: "已学", value: summary.learnedCount, color: .green)
                StatPill(label: "待加强", value: summary.unknownCount, color: .orange)
                StatPill(label: "跳过", value: summary.skippedCount, color: .secondary)
            }
            if isEditing {
                VStack(spacing: 8) {
                    TextField("词典名称", text: $nameInput)
                        .textFieldStyle(.roundedBorder)
                    TextField("分类，如 IELTS / 日语 / 工作术语", text: $categoryInput)
                        .textFieldStyle(.roundedBorder)
                    if let error {
                        Text(error)
                            .font(.caption2)
                            .foregroundStyle(.red)
                    }
                    HStack {
                        Button("取消") {
                            isEditing = false
                            error = nil
                        }
                        Spacer()
                        Button("保存") {
                            saveDictionaryMeta()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
            } else {
                HStack {
                    Button("编辑") {
                        nameInput = summary.pack.name
                        categoryInput = summary.category ?? ""
                        error = nil
                        isEditing = true
                    }
                    .disabled(summary.isBuiltIn)
                    Spacer()
                    Button(role: .destructive) {
                        confirmDelete = true
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderless)
                    .disabled(summary.isBuiltIn)
                    .help(summary.isBuiltIn ? "内置示例词典不能删除，只能关闭启用。" : "删除词典")
                }
                .font(.caption)
            }
        }
        .padding(16)
        .background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.black.opacity(0.08)))
        .confirmationDialog("删除词典？", isPresented: $confirmDelete) {
            Button("删除 \(summary.pack.name)", role: .destructive) {
                deleteDictionary()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("会删除本地词典文件；学习记录默认保留，重新导入同 ID 词典后还能继续使用。")
        }
    }

    private func saveDictionaryMeta() {
        do {
            try store.renameDictionary(summary.pack.id, name: nameInput, category: categoryInput)
            isEditing = false
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func deleteDictionary() {
        do {
            try store.deleteDictionary(summary.pack.id)
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }
}

struct ProgressConnectTab: View {
    @ObservedObject var store: AppDataStore
    let actions: SettingsActions

    private var progressCommand: String {
        "curl --silent --show-error -X POST http://127.0.0.1:\(store.settings.serverPort)/v1/progress -H 'content-type: application/json' -d '{\"source\":\"codex\",\"stage\":\"实现功能\",\"message\":\"正在修改文件\",\"progress\":60,\"status\":\"running\"}'"
    }

    private var doneCommand: String {
        "curl --silent --show-error -X POST http://127.0.0.1:\(store.settings.serverPort)/v1/progress -H 'content-type: application/json' -d '{\"source\":\"codex\",\"stage\":\"完成\",\"message\":\"任务完成\",\"progress\":100,\"status\":\"done\"}'"
    }

    private var curlCommand: String {
        "curl --silent --show-error -X POST http://127.0.0.1:\(store.settings.serverPort)/v1/progress -H 'content-type: application/json' -d '{\"source\":\"codex\",\"stage\":\"验证\",\"message\":\"正在运行检查\",\"progress\":80,\"status\":\"review\"}'"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                sectionHeader("AI 进度接入", subtitle: "复制命令给 Codex、Cursor、Claude Code 或脚本使用。")

                HStack(spacing: 12) {
                    StatusCard(title: "本地服务", value: "127.0.0.1:\(store.settings.serverPort)", icon: "antenna.radiowaves.left.and.right")
                    StatusCard(title: "最近阶段", value: store.progressState.state.current?.stage ?? "暂无", icon: "clock")
                    StatusCard(title: "事件数", value: "\(store.progressState.state.events.count)", icon: "list.bullet.rectangle")
                }

                HStack {
                    PrimaryActionButton(title: "发送测试进度", systemImage: "paperplane.fill", action: actions.sendTestProgress)
                    SecondaryActionButton(title: "选择同步文件夹", systemImage: "icloud.and.arrow.up", action: actions.chooseSyncFolder)
                    SecondaryActionButton(title: "监听状态日志", systemImage: "doc.text.magnifyingglass", action: actions.watchLogFile)
                }

                VStack(alignment: .leading, spacing: 12) {
                    CopyCommandCard(title: "Codex 进行中", command: progressCommand)
                    CopyCommandCard(title: "Codex 完成", command: doneCommand)
                    CopyCommandCard(title: "HTTP curl", command: curlCommand)
                    CopyCommandCard(title: "Codex skill", command: "使用 skills/codex-desktop-pet/SKILL.md 中的进度上报模板")
                }
                .padding(.bottom, 12)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.trailing, 4)
        }
    }
}

struct CopyCommandCard: View {
    let title: String
    let command: String
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text(title)
                    .font(.headline)
                Spacer()
                Button(copied ? "已复制" : "复制") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(command, forType: .string)
                    copied = true
                }
            }
            Text(command)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.black.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
        }
        .padding(16)
        .background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.black.opacity(0.08)))
    }
}

struct PrimaryActionButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
    }
}

struct SecondaryActionButton: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
    }
}

struct StatPill: View {
    let label: String
    let value: Int
    let color: Color

    var body: some View {
        VStack(spacing: 2) {
            Text("\(value)")
                .font(.system(size: 16, weight: .bold))
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
    }
}

struct StatusCard: View {
    let title: String
    let value: String
    let icon: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.headline)
                    .lineLimit(1)
            }
            Spacer()
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(Color.black.opacity(0.08)))
    }
}

struct PixelPetPreview: View {
    var body: some View {
        ZStack {
            Rectangle().fill(Color.clear)
            VStack(spacing: 0) {
                HStack(spacing: 8) {
                    pixel(.mint, width: 20, height: 28)
                    Spacer().frame(width: 48)
                    pixel(.mint, width: 20, height: 28)
                }
                ZStack {
                    RoundedRectangle(cornerRadius: 18)
                        .fill(Color.mint)
                        .frame(width: 118, height: 92)
                    HStack(spacing: 28) {
                        pixel(.black.opacity(0.82), width: 12, height: 16)
                        pixel(.black.opacity(0.82), width: 12, height: 16)
                    }
                    .offset(y: -8)
                    pixel(.pink, width: 26, height: 8)
                        .offset(y: 20)
                }
                HStack(spacing: 36) {
                    pixel(.teal, width: 18, height: 18)
                    pixel(.teal, width: 18, height: 18)
                }
            }
        }
    }

    private func pixel(_ color: Color, width: CGFloat, height: CGFloat) -> some View {
        Rectangle()
            .fill(color)
            .frame(width: width, height: height)
    }
}

@ViewBuilder
private func sectionHeader(_ title: String, subtitle: String) -> some View {
    VStack(alignment: .leading, spacing: 5) {
        Text(title)
            .font(.system(size: 28, weight: .bold, design: .rounded))
        Text(subtitle)
            .foregroundStyle(.secondary)
    }
}

private extension String {
    var nilIfBlank: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
