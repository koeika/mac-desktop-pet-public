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
    var studyNow: () -> Void = {}
}

final class SettingsWindowController {
    private let window: NSWindow

    init(store: AppDataStore, actions: SettingsActions) {
        let rootView = SettingsCenterView(store: store, actions: actions)
        let hostingController = NSHostingController(rootView: rootView)
        window = NSWindow(contentViewController: hostingController)
        window.title = "\(AppBrand.displayName) 配置中心"
        window.setContentSize(NSSize(width: 1120, height: 800))
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
    @State private var learningPage = "我的生词"
    @FocusState private var focusedTab: SettingsTab?
    private var theme: AppVisualTheme { store.settings.visualTheme }

    init(store: AppDataStore, actions: SettingsActions, initialTab: SettingsTab = .pets, initialLearningPage: String = "我的生词") {
        self.store = store
        self.actions = actions
        _selection = State(initialValue: initialTab == .dictionary ? SettingsTab.learningTab(initialLearningPage) : initialTab)
        _learningPage = State(initialValue: initialTab == .dictionary ? initialLearningPage : initialTab.isLearning ? initialTab.title : "我的生词")
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
            VStack(spacing: 0) {
                HStack {
                    Text(selection.title).font(.system(size: 18, weight: .semibold))
                    Spacer()
                }
                .padding(.horizontal, 22).frame(height: 56)
                Divider()
                content
            }
        }
        .frame(minWidth: 880, minHeight: 620)
        .background(theme.paper)
        .foregroundStyle(theme.ink)
        .tint(theme.accent)
        .environment(\.companionTheme, theme)
        .preferredColorScheme(.light)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(spacing: 8) {
                Image(systemName: "pawprint")
                    .font(.system(size: 20, weight: .regular))
                Text(AppBrand.displayName)
                    .font(.system(size: 16, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .padding(.top, 24).padding(.bottom, 8)

            VStack(spacing: 8) {
                tabButton(.pets)
                tabButton(.dictionary)
                tabButton(.library)
                tabButton(.plan)
                Divider().padding(.vertical, 8)
                tabButton(.connections)
                tabButton(.progress)
                tabButton(.appearance)
            }

            GeometryReader { geometry in
                if theme == .forest, geometry.size.height >= 86, let image = ForestThemeArtwork.ferns {
                    Image(nsImage: image).resizable().scaledToFit()
                        .frame(width: 108, height: 72)
                        .frame(maxHeight: .infinity, alignment: .bottom)
                        .padding(.bottom, 8).accessibilityHidden(true)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(store.isUsingAlternateDataDirectory ? "演示数据" : "本机数据")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(store.isUsingAlternateDataDirectory ? theme.accent : theme.ink)
                Text("127.0.0.1:\(String(store.settings.serverPort))")
                    .font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary)
                if theme == .forest {
                    Label(theme.title, systemImage: "leaf").font(.caption).foregroundStyle(theme.accent)
                }
            }
            .padding(.bottom, 20)
        }
        .padding(.horizontal, 12)
        .frame(width: 190)
        .background(theme.wash)
    }

    private var content: some View {
        ZStack {
            // Keep import drafts and query/page state alive while changing sidebar sections.
            DictionaryTab(store: store, actions: actions, initialPage: learningPage, isActive: selection.isLearning)
                .opacity(selection.isLearning ? 1 : 0)
                .disabled(!selection.isLearning)
                .allowsHitTesting(selection.isLearning)
                .accessibilityHidden(!selection.isLearning)
            if !selection.isLearning {
                Group {
                    switch selection {
                    case .pets: PetGalleryTab(store: store, actions: actions)
                    case .progress: ProgressConnectTab(store: store, actions: actions)
                    case .appearance: ThemeGalleryView(store: store)
                    default: EmptyView()
                    }
                }.frame(maxWidth: .infinity, maxHeight: .infinity).background(theme.paper)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func tabButton(_ tab: SettingsTab) -> some View {
        Button {
            selection = tab
            if tab.isLearning { learningPage = tab.title }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: tab.icon)
                    .frame(width: 20)
                Text(tab.title).font(.system(size: 13, weight: selection == tab ? .semibold : .regular))
                Spacer()
            }
            .padding(.horizontal, 10).frame(height: 36)
            .foregroundStyle(selection == tab ? theme.accent : theme.ink)
            .background(selection == tab ? theme.accent.opacity(0.08) : Color.clear, in: RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
        .focused($focusedTab, equals: tab)
        .focusEffectDisabled()
    }
}

enum SettingsTab: CaseIterable, Hashable {
    case pets
    case dictionary
    case library
    case plan
    case connections
    case progress
    case appearance

    var isLearning: Bool { [.dictionary, .library, .plan, .connections].contains(self) }

    static func learningTab(_ page: String) -> SettingsTab {
        switch page {
        case "词典库": return .library
        case "学习计划": return .plan
        case "连接与 AI": return .connections
        default: return .dictionary
        }
    }

    var title: String {
        switch self {
        case .pets: return "宠物管理"
        case .dictionary: return "我的生词"
        case .library: return "词典库"
        case .plan: return "学习计划"
        case .connections: return "连接与 AI"
        case .progress: return "AI 进度接入"
        case .appearance: return "外观与主题"
        }
    }

    var subtitle: String {
        switch self {
        case .pets: return "上传、启用、权重"
        case .dictionary: return "生词、词典、学习计划"
        case .library: return "导入、分类、管理"
        case .plan: return "学习时段与复习"
        case .connections: return "浏览器配对、AI"
        case .progress: return "命令、HTTP、事件"
        case .appearance: return "主题预览与切换"
        }
    }

    var icon: String {
        switch self {
        case .pets: return "pawprint.fill"
        case .dictionary: return "character.book.closed.fill"
        case .library: return "square.stack.3d.up"
        case .plan: return "calendar"
        case .connections: return "link"
        case .progress: return "bolt.horizontal.circle.fill"
        case .appearance: return "paintpalette"
        }
    }
}

struct PetGalleryTab: View {
    @Environment(\.companionTheme) private var theme
    @ObservedObject var store: AppDataStore
    let actions: SettingsActions
    @State private var installURLText = ""
    @State private var isPreparingInstall = false
    @State private var installPreview: PetInstallPreview?
    @State private var installError: String?
    @State private var installSuccess: String?
    @State private var selectedPetID: String?
    @State private var previewAction: CodexPetAction = .idle
    @State private var linkInstall = false
    @State private var visibilityError: String?

    private var selectedPet: PetAsset? {
        store.pets.first { $0.id == selectedPetID } ?? store.enabledPets().first ?? store.pets.first
    }

    var body: some View {
        GeometryReader { geometry in
            if geometry.size.width >= 760 {
                HStack(alignment: .top, spacing: 20) {
                    gallery.frame(maxWidth: .infinity)
                    Divider()
                    inspector.frame(width: 250)
                }
            } else {
                ScrollView {
                    VStack(spacing: 20) {
                        galleryContent
                        Divider()
                        inspectorContent
                    }.padding(.trailing, 4)
                }.scrollIndicators(.visible)
            }
        }
        .popover(isPresented: $linkInstall) {
            VStack(alignment: .leading, spacing: 16) {
                HStack { Text("链接安装").font(.headline); Spacer(); Button("完成") { linkInstall = false } }
                urlInstallPanel
            }.padding(24).frame(width: 480)
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
        .alert("显示设置未保存", isPresented: Binding(get: { visibilityError != nil }, set: { if !$0 { visibilityError = nil } })) {
            Button("好", role: .cancel) { visibilityError = nil }
        } message: { Text(visibilityError ?? "") }
    }

    private var gallery: some View {
        ScrollView { galleryContent.padding(.trailing, 4) }.scrollIndicators(.visible)
    }

    private var galleryContent: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Menu {
                    Button("上传图片 / GIF / 视频", action: actions.uploadPhotos)
                    Button("导入宠物包", action: actions.importPetPackage)
                    Button("链接安装") { linkInstall = true }
                } label: { Label("添加素材", systemImage: "plus") }
                Spacer()
                Button(action: actions.randomPreview) { Image(systemName: "shuffle") }.help("随机见一面")
            }
            Toggle("仅在单词卡出现时显示宠物", isOn: Binding(
                get: { store.settings.petOnlyWithVocabulary },
                set: { enabled in
                    do { try store.setPetOnlyWithVocabulary(enabled) }
                    catch { visibilityError = error.localizedDescription }
                }
            ))
            .toggleStyle(.switch).font(.subheadline)
            .accessibilityIdentifier("pet-only-with-vocabulary")
            .help("空闲时隐藏宠物；词卡关闭后隐藏。AI 通知单独显示，菜单栏仍可主动抽词。")
            if let pet = selectedPet {
                VStack(spacing: 8) {
                    if theme == .forest {
                        ForestPetStage { petPreview(pet, animated: true) }.frame(height: 270)
                    } else {
                        petPreview(pet, animated: true).frame(height: 190)
                    }
                    Text(pet.name).font(.system(size: 18, weight: .semibold)).lineLimit(2)
                    Label(pet.isEnabled ? "已加入桌面随机出现" : "未启用", systemImage: pet.isEnabled ? "checkmark.circle.fill" : "circle")
                        .font(.caption).foregroundStyle(.secondary)
                }.frame(maxWidth: .infinity).padding(.vertical, 12)
            }
            Divider()
            HStack {
                Text("我的小伙伴").font(.headline)
                Text("\(store.pets.count) 只").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Menu("批量样式") {
                    ForEach(CompanionStyle.allCases, id: \.rawValue) { style in
                        Button(style.title) { selectStyle(style) }
                    }
                }.fixedSize()
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 155), spacing: 10)], spacing: 10) {
                ForEach(store.pets) { pet in
                    Button { selectedPetID = pet.id; previewAction = .idle } label: {
                        HStack(spacing: 10) {
                            petPreview(pet, animated: false).frame(width: 56, height: 68)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(pet.name).font(.system(size: 13, weight: .semibold)).lineLimit(2)
                                Text(pet.mediaLabel).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
                            }.frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(10).frame(height: 92)
                        .background(selectedPet?.id == pet.id ? theme.accent.opacity(0.05) : theme.paper)
                        .clipShape(RoundedRectangle(cornerRadius: 7))
                        .overlay(RoundedRectangle(cornerRadius: 7).stroke(selectedPet?.id == pet.id ? theme.accent.opacity(0.6) : theme.line.opacity(0.5), lineWidth: 1))
                    }.buttonStyle(.plain).focusEffectDisabled()
                        .accessibilityLabel("选择宠物 \(pet.name)")
                        .accessibilityValue(selectedPet?.id == pet.id ? "已选择" : "未选择")
                }
            }
            if store.pets.isEmpty { EmptyGalleryCard() }
            if let installError { Text(installError).font(.caption).foregroundStyle(.red) }
            if let installSuccess { Text(installSuccess).font(.caption).foregroundStyle(.secondary) }
        }.frame(maxWidth: .infinity, alignment: .leading).padding(.bottom, 8)
    }

    @ViewBuilder private func petPreview(_ pet: PetAsset, animated: Bool) -> some View {
        if animated, let renderer = store.spriteRenderer(for: pet) {
            CompanionAnimation(renderer: renderer, action: previewAction).id(pet.id)
        } else if let image = store.previewImage(for: pet) {
            Image(nsImage: image).resizable().scaledToFit()
        } else {
            Image(systemName: pet.kind == .video ? "film" : "photo").font(.title).foregroundStyle(.secondary)
        }
    }

    private var inspector: some View {
        ScrollView { inspectorContent.padding(.trailing, 4) }.scrollIndicators(.visible)
    }

    private var inspectorContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let pet = selectedPet {
                HStack {
                    Text(pet.name).font(.system(size: 16, weight: .semibold)).lineLimit(2)
                    Spacer()
                    Menu {
                        Button("删除宠物", role: .destructive) { store.deletePet(pet) }
                    } label: { Image(systemName: "ellipsis") }.menuStyle(.borderlessButton).fixedSize().help("宠物操作")
                }
                Toggle("桌面显示", isOn: Binding(get: { selectedPet?.isEnabled ?? false }, set: {
                    selectedPetID = pet.id
                    store.setPetEnabled(pet, isEnabled: $0)
                })).toggleStyle(.switch)
                Divider()
                if pet.kind == .codexPackage {
                    Picker("动画预览", selection: $previewAction) {
                        ForEach(CodexPetAction.allCases) { item in Text(item.chineseName).tag(item) }
                    }
                }
                if pet.kind == .photo { Text("静态照片拟真有限").font(.caption).foregroundStyle(.secondary) }
                speedPanel
                Divider()
                clickFeedbackPanel
                Divider()
                HStack {
                    Text("出现权重")
                    Spacer()
                    Text(String(format: "%.1f", pet.weight)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
                Slider(value: Binding(get: { selectedPet?.weight ?? 1 }, set: { store.setPetWeight(pet, weight: $0) }), in: 0.1...5)
                Text("出现 \(pet.appearances) 次").font(.caption).foregroundStyle(.secondary)
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
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
        .background(theme.wash, in: RoundedRectangle(cornerRadius: 7))
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
                                get: { store.petClickFeedbackPhrase(at: index) },
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
        .padding(.vertical, 14)
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
                in: 0.05...1.4
            )
            Toggle("暂停走动", isOn: Binding(get: { store.settings.walkingPaused }, set: {
                store.setWalkingPaused($0)
            })).toggleStyle(.switch)
        }
        .padding(.vertical, 12)
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
                    linkInstall = false
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
        HStack(spacing: 24) {
            CompanionDuo(store: store).frame(maxWidth: .infinity)
            VStack(alignment: .leading, spacing: 16) {
                Text(theme == .storybook ? "绘本里的小伙伴" : "漫画里的小伙伴").font(.system(size: 20, weight: .semibold))
                Text("Whisky & Cling")
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
                ForEach([CompanionStyle.color, .ink, .original], id: \.rawValue) { style in
                    let selected = store.selectedCompanionStyle == style
                    Button { selectStyle(style) } label: {
                        HStack {
                            Text(style.title)
                            Spacer()
                            Image(systemName: "checkmark").opacity(selected ? 1 : 0)
                        }
                    }
                    .buttonStyle(InkButtonStyle(primary: selected))
                    .accessibilityValue(selected ? "已选择" : "未选择")
                }
            }.frame(width: 205, alignment: .leading)
        }
        .padding(.vertical, 18)
    }

    private func selectStyle(_ style: CompanionStyle) {
        do {
            try store.selectCompanionStyle(style)
            selectedPetID = store.enabledPets().first?.id
            actions.randomPreview()
        } catch {
            installError = error.localizedDescription
        }
    }
}

struct PetCard: View {
    @Environment(\.companionTheme) private var theme
    @ObservedObject var store: AppDataStore
    let pet: PetAsset
    @State private var action: CodexPetAction = .idle

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ZStack(alignment: .bottomTrailing) {
                RoundedRectangle(cornerRadius: 6)
                    .fill(theme.wash)
                    .frame(height: 150)
                if pet.kind == .codexPackage, let renderer = store.spriteRenderer(for: pet) {
                    CompanionAnimation(renderer: renderer, action: action)
                        .padding(10).frame(height: 150).frame(maxWidth: .infinity)
                } else if let image = store.previewImage(for: pet) {
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
                    .background(theme.paper, in: RoundedRectangle(cornerRadius: 4))
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

            if pet.kind == .codexPackage {
                Picker("预览动作", selection: $action) {
                    ForEach(CodexPetAction.allCases) { item in Text(item.chineseName).tag(item) }
                }.pickerStyle(.menu)
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
        .background(theme.paper, in: RoundedRectangle(cornerRadius: 7))
        .overlay(RoundedRectangle(cornerRadius: 7).stroke(theme == .comic ? theme.ink : theme.line, lineWidth: 1.2))
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
    let initialPage: String
    var isActive: Bool
    @StateObject private var index = VocabularyLibraryIndex()
    @State private var tab = "我的生词"
    @State private var notebookQuery = NotebookQuery()
    @State private var libraryQuery = DictionaryLibraryQuery()
    @State private var notebookPage = 1
    @State private var notebookPageSize = 20
    @State private var libraryPage = 1
    @State private var libraryPageSize = 12
    @State private var copied = false
    @State private var pdfDraft: DictionaryImportDraft?
    @State private var isImportingPDF = false
    @State private var importError: String?
    @State private var importSuccess: String?
    @State private var apiKeyInput = ""
    @State private var apiKeySaved = false
    @State private var modelInput = ""
    @State private var deepSeekBaseURLInput = ""

    init(store: AppDataStore, actions: SettingsActions, initialPage: String = "我的生词", isActive: Bool = true) {
        self.store = store
        self.actions = actions
        self.initialPage = initialPage
        self.isActive = isActive
        _tab = State(initialValue: initialPage)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Group {
                switch tab {
                case "我的生词":
                    PersonalVocabularyPanel(store: store, index: index, query: $notebookQuery, page: $notebookPage, pageSize: $notebookPageSize)
                case "词典库":
                    dictionaryLibrary
                case "连接与 AI":
                    connectionPanel
                default:
                    ScrollView {
                        VStack(alignment: .leading, spacing: 20) {
                            LearningPlanPanel(store: store, index: index, studyNow: actions.studyNow)
                            Divider()
                            DisclosureGroup("学习节奏与复习设置") {
                                VStack(alignment: .leading, spacing: 20) {
                                    learningPacePanel
                                    reviewPlanPanel
                                }.padding(.top, 16)
                            }
                        }.frame(maxWidth: .infinity, alignment: .leading).padding(.trailing, 4)
                    }.scrollIndicators(.visible)
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .task(id: store.libraryRevision) { await index.reload(store: store, now: Date()) }
        .onAppear { if tab == "连接与 AI" { syncProviderInputs() } }
        .onChange(of: initialPage) { _, page in
            tab = page
            if page == "连接与 AI" { syncProviderInputs() }
        }
        .onReceive(Timer.publish(every: 60, on: .main, in: .common).autoconnect()) { now in
            Task { await index.reload(store: store, now: now) }
        }
        .sheet(item: Binding(get: { isActive && tab == "词典库" ? pdfDraft : nil }, set: { _ in })) { draft in
            DictionaryDraftSheet(
                initialDraft: draft,
                onSave: { draftToSave in
                    do {
                        let pack = try store.importDictionaryDraft(draftToSave)
                        importSuccess = "已导入 \(pack.entries.count) 个词：\(pack.name)"
                        importError = nil
                        pdfDraft = nil
                    } catch { importError = error.localizedDescription }
                },
                onCancel: { pdfDraft = nil },
                generateExamples: { try await store.generateExamples(for: $0) },
                parseWithDeepSeek: { try await store.parsePDFDraftWithDeepSeek($0) }
            )
            .interactiveDismissDisabled()
        }
    }

    private var connectionPanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Label("Chrome 浏览器收藏", systemImage: "globe").font(.headline)
                Text("127.0.0.1:\(String(store.settings.serverPort))").font(.body.monospaced())
                HStack {
                    Button {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(store.captureToken, forType: .string)
                        copied = true
                    } label: { Label(copied ? "配对码已复制" : "复制 Chrome 配对码", systemImage: "doc.on.doc") }
                    Button { openExtension() } label: { Label("打开 Chrome 扩展文件夹", systemImage: "folder") }
                }
                Divider()
                openAISettingsPanel
                if let importError { Text(importError).font(.caption).foregroundStyle(.red) }
                if let importSuccess { Text(importSuccess).font(.caption).foregroundStyle(.secondary) }
            }.frame(maxWidth: 760, alignment: .leading).padding(.trailing, 4)
                .frame(maxWidth: .infinity, alignment: .leading)
        }.scrollIndicators(.visible)
    }

    private var dictionaryLibrary: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Button(action: actions.importDictionary) { Label("导入 CSV/JSON", systemImage: "square.and.arrow.down") }
                Button(action: importPDFDictionary) { Label(isImportingPDF ? "PDF 解析中…" : "导入 PDF", systemImage: "doc.richtext") }
                    .disabled(isImportingPDF)
                Menu {
                    Button("打开 CSV 模板", action: actions.openCSVTemplate)
                    Button("打开 JSON 模板", action: actions.openJSONTemplate)
                    Button("查看导入格式", action: actions.showImportFormat)
                    Divider()
                    Button("恢复示例词典") {
                        do { try store.restoreSampleDictionaries(); importSuccess = nil; importError = nil }
                        catch { importError = error.localizedDescription }
                    }
                } label: { Label("模板与格式", systemImage: "doc.text") }
                Spacer()
                Text("\(index.dictionaries.count) 个词典").font(.caption).foregroundStyle(.secondary)
            }
            if let importError { Text(importError).font(.caption).foregroundStyle(.red) }
            else if let importSuccess { Text(importSuccess).font(.caption).foregroundStyle(.secondary) }
            DictionaryLibraryPanel(store: store, index: index, query: $libraryQuery, page: $libraryPage, pageSize: $libraryPageSize)
        }
    }

    private var reviewPlanPanel: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label("新词与复习", systemImage: "arrow.triangle.2.circlepath").font(.headline)
            VocabularyLimitControl(title: "每天首次学习词数", count: Binding(
                get: { store.settings.dailyNewVocabularyLimit }, set: {
                    store.objectWillChange.send(); store.settings.dailyNewVocabularyLimit = $0; store.saveSettings()
                }), unlimited: Binding(get: { store.settings.dailyNewVocabularyUnlimited }, set: {
                    store.objectWillChange.send(); store.settings.dailyNewVocabularyUnlimited = $0; store.saveSettings()
                }), minimum: 0)
            Toggle("先回忆再看释义", isOn: Binding(get: { store.settings.vocabularyRecallMode }, set: {
                store.objectWillChange.send(); store.settings.vocabularyRecallMode = $0; store.saveSettings()
            })).toggleStyle(.switch)
            HStack {
                Text("目标保持率 \(Int((store.settings.vocabularyRetention * 100).rounded()))%")
                Slider(value: Binding(get: { store.settings.vocabularyRetention }, set: {
                    store.objectWillChange.send(); store.settings.vocabularyRetention = $0; store.saveSettings()
                }), in: 0.8...0.95, step: 0.01).frame(maxWidth: 220)
            }
            Text("目标保持率用于 FSRS 安排复习，不是已测得的掌握率；设置越高，通常需要越频繁地复习。")
                .font(.caption).foregroundStyle(.secondary)
        }.padding(.vertical, 8)
    }

    private func openExtension() {
        let candidates = [Bundle.main.resourceURL?.appendingPathComponent("ChromeExtension"),
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("ChromeExtension")]
        if let url = candidates.compactMap({ $0 }).first(where: { FileManager.default.fileExists(atPath: $0.appendingPathComponent("manifest.json").path) }) {
            NSWorkspace.shared.open(url)
        } else { importError = "请解压完整发布包，使用其中的 ChromeExtension 文件夹。" }
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
                VocabularyLimitControl(title: "每天自动展示次数", count: Binding(
                        get: { store.settings.dailyVocabularyLimit },
                        set: { store.setDailyVocabularyLimit($0) }
                    ), unlimited: Binding(get: { store.settings.dailyVocabularyUnlimited }, set: {
                        store.objectWillChange.send(); store.settings.dailyVocabularyUnlimited = $0; store.saveSettings()
                    }))
                VStack(alignment: .leading, spacing: 6) {
                    Text("最短弹出间隔").font(.subheadline.weight(.semibold))
                    HStack {
                        TextField("最短弹出间隔", value: Binding(get: { store.settings.vocabularyMinimumIntervalMinutes }, set: {
                            store.objectWillChange.send(); store.settings.vocabularyMinimumIntervalMinutes = max(1, $0); store.saveSettings()
                        }), format: .number.grouping(.never)).textFieldStyle(.roundedBorder).frame(width: 60)
                        Text("分钟")
                    }
                }
                Spacer()
            }

            HStack(alignment: .top, spacing: 16) {
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
        .padding(.vertical, 14)
        .overlay(alignment: .bottom) { Divider() }
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
        .padding(.vertical, 14)
        .overlay(alignment: .bottom) { Divider() }
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
            return "DeepSeek 使用 OpenAI-compatible Chat Completions + JSON 输出；默认模型 deepseek-flash，默认 Base URL https://api.deepseek.com。"
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
    @Environment(\.companionTheme) private var theme
    @ObservedObject var store: AppDataStore
    let summary: DictionarySummary
    @State private var isEditing = false
    @State private var nameInput = ""
    @State private var categoryInput = ""
    @State private var error: String?
    @State private var confirmDelete = false
    @State private var deleteError: String?

    private var visibleDescription: String {
        (summary.pack.description ?? "").components(separatedBy: "\n")
            .filter { !$0.hasPrefix("分类：") }.joined(separator: "\n")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(summary.pack.name)
                        .font(.system(size: 16, weight: .bold))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, minHeight: 38, maxHeight: 38, alignment: .topLeading)
                        .help(summary.pack.name)
                    Text("\(summary.studyProgress.total) 个词")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Toggle("", isOn: Binding(
                    get: { store.settings.enabledDictionaryIDs.contains(summary.pack.id) },
                    set: { store.toggleDictionary(summary.pack.id, isEnabled: $0) }
                ))
                .toggleStyle(.switch)
            }.frame(height: 54, alignment: .top)
            HStack(spacing: 6) {
                Text(summary.category ?? "未分类")
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(theme.wash, in: RoundedRectangle(cornerRadius: 4))
                    .foregroundStyle(theme.ink)
                if summary.isBuiltIn {
                    Text("示例")
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(theme.wash, in: RoundedRectangle(cornerRadius: 4))
                        .foregroundStyle(.secondary)
                }
            }.frame(height: 22, alignment: .leading)
            Text(visibleDescription)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, minHeight: 16, maxHeight: 16, alignment: .topLeading)
                .help(visibleDescription)
            DictionaryStudyProgressView(progress: summary.studyProgress)
            HStack(spacing: 10) {
                Text("已认识 \(summary.studyProgress.familiar)")
                Text("学习中 \(summary.studyProgress.learning)")
                Spacer(minLength: 0)
                Text("待学习 \(summary.studyProgress.remaining)")
            }.font(.caption2).foregroundStyle(.secondary).monospacedDigit()
            Spacer(minLength: 0)
            HStack {
                if !summary.isBuiltIn {
                    Button("编辑") {
                        nameInput = summary.pack.name
                        categoryInput = summary.category ?? ""
                        error = nil
                        isEditing = true
                    }
                }
                Spacer()
                Button(role: .destructive) { confirmDelete = true } label: { Image(systemName: "trash") }
                    .buttonStyle(.borderless)
                    .help(summary.isBuiltIn ? "移除示例，保留学习记录" : "移到废纸篓，保留学习记录")
                    .accessibilityLabel("移除词典 \(summary.pack.name)")
            }.font(.caption).frame(height: 26)
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .frame(height: 256, alignment: .topLeading)
        .background(theme.paper, in: RoundedRectangle(cornerRadius: 7))
        .overlay(RoundedRectangle(cornerRadius: 7).stroke(theme.line))
        .sheet(isPresented: $isEditing) {
            VStack(alignment: .leading, spacing: 16) {
                Text("编辑词典").font(.title2.weight(.semibold))
                TextField("词典名称", text: $nameInput).textFieldStyle(.roundedBorder)
                TextField("分类", text: $categoryInput).textFieldStyle(.roundedBorder)
                if let error { Text(error).font(.caption).foregroundStyle(.red) }
                HStack {
                    Button("取消", role: .cancel) { isEditing = false; error = nil }
                    Spacer()
                    Button("保存", action: saveDictionaryMeta).buttonStyle(.borderedProminent)
                }
            }.padding(24).frame(width: 360)
        }
        .confirmationDialog(summary.isBuiltIn ? "移除示例词典？" : "将词典移到废纸篓？", isPresented: $confirmDelete) {
            Button(summary.isBuiltIn ? "移除 \(summary.pack.name)" : "将 \(summary.pack.name) 移到废纸篓", role: .destructive) {
                deleteDictionary()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text(summary.isBuiltIn ? "学习记录会保留，可在“模板与格式”中恢复示例词典。" : "词典文件将移到系统废纸篓，学习记录默认保留。可从废纸篓放回文件，或重新导入同 ID 词典以继续学习。")
        }
        .alert("无法移除词典", isPresented: Binding(
            get: { deleteError != nil }, set: { if !$0 { deleteError = nil } }
        )) {
            Button("好", role: .cancel) { deleteError = nil }
        } message: {
            Text(deleteError ?? "")
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
            deleteError = nil
        } catch {
            deleteError = error.localizedDescription
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
    @Environment(\.companionTheme) private var theme
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
        .background(theme.paper, in: RoundedRectangle(cornerRadius: 7))
        .overlay(RoundedRectangle(cornerRadius: 7).stroke(theme.line))
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
        }
        .buttonStyle(InkButtonStyle(primary: true))
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
        }
        .buttonStyle(InkButtonStyle())
    }
}

struct StatPill: View {
    @Environment(\.companionTheme) private var theme
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
        .background(theme.wash, in: RoundedRectangle(cornerRadius: 5))
    }
}

struct StatusCard: View {
    @Environment(\.companionTheme) private var theme
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
        .background(theme.paper, in: RoundedRectangle(cornerRadius: 7))
        .overlay(RoundedRectangle(cornerRadius: 7).stroke(theme.line))
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
            .font(.system(size: 25, weight: .semibold))
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
