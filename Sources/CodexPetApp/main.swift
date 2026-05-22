import AppKit
import CodexPetCore
import UniformTypeIdentifiers

final class AppDelegate: NSObject, NSApplicationDelegate, PetContentViewDelegate {
    private var store: AppDataStore!
    private var window: NSPanel!
    private var contentView: PetContentView!
    private var statusItem: NSStatusItem!
    private var settingsWindowController: SettingsWindowController?
    private var httpServer: LocalHTTPServer?
    private let logWatcher = StatusLogWatcher()

    private var activePet: PetAsset?
    private var activeWord: ScopedDictionaryEntry?
    private var progressPriorityUntil = Date.distantPast
    private var queuedVocabulary = false
    private var behaviorEngine = PetBehaviorEngine()
    private var temporaryAction: CodexPetAction?
    private var temporaryActionUntil = Date.distantPast
    private var walkTimer: Timer?
    private var vocabTimer: Timer?
    private var idleCuteTimer: Timer?
    private var vocabularyQuestionTimer: Timer?
    private var nextAutomaticVocabularyAt = Date().addingTimeInterval(90)

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.regular)
        do {
            store = try AppDataStore()
        } catch {
            fatalError("Cannot initialize app store: \(error)")
        }

        setupWindow()
        setupMenu()
        startHTTPServer()
        startLogWatcher()
        startTimers()
        chooseRandomPet()
        if store.pets.isEmpty {
            showSettingsCenter()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        store.settings.lastWindowOrigin = window.frame.origin
        store.saveSettings()
        httpServer?.stop()
        logWatcher.stop()
    }

    private func setupWindow() {
        let size = NSSize(width: 420, height: 500)
        let screenFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1280, height: 800)
        let fallbackOrigin = CGPoint(x: screenFrame.maxX - size.width - 42, y: screenFrame.minY + 60)
        let origin = visibleWindowOrigin(
            savedOrigin: store.settings.lastWindowOrigin,
            fallbackOrigin: fallbackOrigin,
            size: size
        )
        window = NSPanel(
            contentRect: NSRect(origin: origin, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces]
        window.hidesOnDeactivate = false
        window.isReleasedWhenClosed = false

        contentView = PetContentView(frame: NSRect(origin: .zero, size: size))
        contentView.delegate = self
        contentView.canDragWindow = !store.settings.positionLocked
        window.contentView = contentView
        window.orderFrontRegardless()
        behaviorEngine.snap(to: window.frame.origin)
    }

    private func visibleWindowOrigin(savedOrigin: CGPoint?, fallbackOrigin: CGPoint, size: NSSize) -> CGPoint {
        let frames = NSScreen.screens.map(\.visibleFrame)
        let fallbackFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1280, height: 800)
        if let savedOrigin {
            let savedRect = NSRect(origin: savedOrigin, size: size)
            if let frame = frames.first(where: { $0.intersection(savedRect).width >= 80 && $0.intersection(savedRect).height >= 80 }) {
                return clampedOrigin(savedOrigin, size: size, in: frame)
            }
        }
        return clampedOrigin(fallbackOrigin, size: size, in: fallbackFrame)
    }

    private func clampedOrigin(_ origin: CGPoint, size: NSSize, in frame: NSRect) -> CGPoint {
        CGPoint(
            x: min(max(origin.x, frame.minX + 8), frame.maxX - size.width - 8),
            y: min(max(origin.y, frame.minY + 8), frame.maxY - size.height - 8)
        )
    }

    private func setupMenu() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let icon = statusBarIcon() {
            statusItem.button?.image = icon
            statusItem.button?.imagePosition = .imageOnly
            statusItem.button?.toolTip = AppBrand.displayName
        } else {
            statusItem.button?.title = AppBrand.displayName
        }

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "打开配置中心...", action: #selector(showSettingsCenter), keyEquivalent: ","))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "显示 \(AppBrand.displayName)", action: #selector(showPet), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "隐藏 \(AppBrand.displayName)", action: #selector(hidePet), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "上传宠物素材...", action: #selector(uploadPetPhotos), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "导入 Codex pet 包...", action: #selector(importCodexPackage), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "随机预览宠物", action: #selector(randomPetNow), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "导入词典...", action: #selector(importDictionary), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "现在抽一个词", action: #selector(wordNow), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "选择 iCloud Drive 同步文件夹...", action: #selector(chooseSyncFolder), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "监听状态日志文件...", action: #selector(watchLogFile), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        let pause = NSMenuItem(title: "暂停走动", action: #selector(toggleWalking), keyEquivalent: "")
        pause.state = store.settings.walkingPaused ? .on : .off
        menu.addItem(pause)
        let lock = NSMenuItem(title: "锁定位置", action: #selector(toggleLockPosition), keyEquivalent: "")
        lock.state = store.settings.positionLocked ? .on : .off
        menu.addItem(lock)
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "退出", action: #selector(quit), keyEquivalent: "q"))
        statusItem.menu = menu
    }

    private func statusBarIcon() -> NSImage? {
        guard let url = AppResourceLocator.file(named: "AppIcon", extension: "png"),
              let image = NSImage(contentsOf: url) else {
            return nil
        }
        image.size = NSSize(width: 18, height: 18)
        image.isTemplate = false
        return image
    }

    private func startHTTPServer() {
        httpServer = LocalHTTPServer(
            port: store.settings.serverPort,
            stateProvider: { [weak self] in self?.store.progressState.state ?? AgentState() },
            eventHandler: { [weak self] event in
                DispatchQueue.main.async {
                    self?.receiveProgress(event)
                }
            }
        )
        do {
            try httpServer?.start()
        } catch {
            contentView.showMessage(
                kicker: "HTTP server",
                title: "Port \(store.settings.serverPort) unavailable",
                body: error.localizedDescription,
                showActions: false
            )
        }
    }

    private func startLogWatcher() {
        logWatcher.paths = store.settings.logPaths
        logWatcher.onEvent = { [weak self] event in
            DispatchQueue.main.async {
                self?.receiveProgress(event)
            }
        }
        logWatcher.start()
    }

    private func startTimers() {
        walkTimer = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { [weak self] _ in
            self?.walkTick()
        }
        RunLoop.main.add(walkTimer!, forMode: .common)

        vocabTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            self?.showVocabularyRespectingPriority()
        }
        RunLoop.main.add(vocabTimer!, forMode: .common)

        idleCuteTimer = Timer.scheduledTimer(withTimeInterval: 900, repeats: true) { [weak self] _ in
            self?.showIdleCuteMessageIfAppropriate()
        }
        RunLoop.main.add(idleCuteTimer!, forMode: .common)
    }

    private func walkTick() {
        guard let screenFrame = window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame else { return }
        let preferredAction = Date() < temporaryActionUntil ? temporaryAction : nil

        guard window.isVisible else { return }
        if store.settings.walkingPaused || store.settings.positionLocked {
            behaviorEngine.snap(to: window.frame.origin)
            contentView.setPetAction(preferredAction ?? .idle)
            return
        }

        if distance(behaviorEngine.origin, window.frame.origin) > 48 {
            behaviorEngine.snap(to: window.frame.origin)
        }

        let state = behaviorEngine.tick(
            deltaTime: 0.08,
            bounds: screenFrame,
            petSize: window.frame.size,
            preferredAction: preferredAction,
            speedMultiplier: store.settings.movementSpeedMultiplier
        )
        setWindowOriginIfNeeded(state.origin)
        contentView.setPetAction(state.action)
    }

    private func setTemporaryAction(_ action: CodexPetAction, duration: TimeInterval) {
        temporaryAction = action
        temporaryActionUntil = Date().addingTimeInterval(duration)
        contentView.setPetAction(action)
    }

    private func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
        hypot(a.x - b.x, a.y - b.y)
    }

    private func setWindowOriginIfNeeded(_ origin: CGPoint) {
        let rounded = CGPoint(x: origin.x.rounded(), y: origin.y.rounded())
        guard distance(rounded, window.frame.origin) >= 1 else { return }
        window.setFrameOrigin(rounded)
    }

    private func receiveProgress(_ event: ProgressEvent) {
        clearActiveVocabularyQuestion()
        store.progressState.apply(event)
        store.objectWillChange.send()
        let isCompletion = event.status == .done || event.progress == 100
        progressPriorityUntil = Date().addingTimeInterval(isCompletion ? 12 : 8)
        setTemporaryAction(event.status.petAction, duration: isCompletion ? 3.2 : 8)
        let progressText = event.progress.map { " · \($0)%" } ?? ""
        let stageText = isCompletion ? "任务完成" : event.stage
        let bodyText: String
        if isCompletion {
            bodyText = event.message.isEmpty ? "\(event.source) 会话已完成。" : event.message
        } else {
            bodyText = event.message.isEmpty ? event.status.rawValue : event.message
        }
        contentView.showMessage(
            kicker: "\(event.source)\(progressText)",
            title: stageText,
            body: bodyText,
            showActions: false,
            autoHideAfter: isCompletion ? 12 : 8
        )
        if event.status == .done || event.status == .failed {
            queuedVocabulary = true
        }
    }

    private func showVocabularyRespectingPriority() {
        let now = Date()
        store.resetVocabularyScheduleIfNeeded(now: now)
        guard activeWord == nil else { return }
        if Date() < progressPriorityUntil {
            queuedVocabulary = true
            return
        }
        guard queuedVocabulary || now >= nextAutomaticVocabularyAt else { return }
        guard store.canShowAutomaticVocabulary(now: now) else { return }
        if queuedVocabulary || now >= nextAutomaticVocabularyAt {
            queuedVocabulary = false
            if showVocabularyNow(isAutomatic: true) {
                scheduleNextAutomaticVocabulary(after: now)
            }
        }
    }

    @discardableResult
    private func showVocabularyNow(isAutomatic: Bool = false) -> Bool {
        let entries = store.enabledEntries()
        guard let selected = VocabularyPicker.pick(
            from: entries,
            stats: store.vocabularyProgress.stats
        ) else {
            if !isAutomatic {
                contentView.showMessage(
                    kicker: "词典",
                    title: "没有可用词汇",
                    body: "请在配置中心导入 CSV/JSON/PDF 词典，或启用内置示例词典。",
                    showActions: false
                )
            }
            return false
        }
        vocabularyQuestionTimer?.invalidate()
        activeWord = selected
        if isAutomatic {
            store.recordAutomaticVocabularyShown()
        }
        store.vocabularyProgress.recordSeen(dictionaryID: selected.dictionaryID, term: selected.entry.term)
        store.saveLearningProgress()
        chooseRandomPet()
        setTemporaryAction(.jumping, duration: 1.2)

        contentView.showMessage(
            kicker: selected.dictionaryName,
            title: selected.entry.term,
            body: vocabularyCardBody(for: selected),
            showActions: true,
            footer: vocabularyFooterText()
        )
        if !store.settings.vocabularyQuestionPersists {
            vocabularyQuestionTimer = Timer.scheduledTimer(withTimeInterval: 22, repeats: false) { [weak self] _ in
                self?.clearActiveVocabularyQuestion()
                self?.contentView.hideBubble(animated: true)
            }
            if let vocabularyQuestionTimer {
                RunLoop.main.add(vocabularyQuestionTimer, forMode: .common)
            }
        }
        return true
    }

    private func vocabularyCardBody(for word: ScopedDictionaryEntry) -> String {
        var sections: [String] = []
        let reading = cleanVocabularyField(word.entry.phonetic ?? word.entry.reading)
        if !reading.isEmpty {
            if word.entry.phonetic != nil {
                sections.append("发音：\(reading.hasPrefix("/") ? reading : "/\(reading)/")")
            } else {
                sections.append("读音：\(reading)")
            }
        } else if looksLikeEnglishTerm(word.entry.term) {
            sections.append("拼写：\(word.entry.term)")
        }

        let meaning = cleanVocabularyField(word.entry.meaning)
        if !meaning.isEmpty {
            sections.append("[释义]\n\(meaning)")
        } else {
            sections.append("[释义]\n还没有释义，可以在词典管理里补充。")
        }

        if let example = cleanOptionalVocabularyField(word.entry.example) {
            sections.append("[例句]\n\(example)")
        }

        if let hint = cleanOptionalVocabularyField(word.entry.hint) {
            sections.append("[提示]\n\(hint)")
        }

        return sections.joined(separator: "\n\n")
    }

    private func cleanOptionalVocabularyField(_ value: String?) -> String? {
        let cleaned = cleanVocabularyField(value)
        return cleaned.isEmpty ? nil : cleaned
    }

    private func cleanVocabularyField(_ value: String?) -> String {
        (value ?? "")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func looksLikeEnglishTerm(_ value: String) -> Bool {
        value.range(of: #"^[A-Za-z][A-Za-z\s'./-]*$"#, options: .regularExpression) != nil
    }

    private func vocabularyFooterText() -> String {
        let limit = max(1, store.settings.dailyVocabularyLimit)
        let shown = min(max(0, store.settings.vocabularyShownCount), limit)
        return "今日 \(shown) / \(limit)"
    }

    private func scheduleNextAutomaticVocabulary(after date: Date) {
        let limit = max(1, store.settings.dailyVocabularyLimit)
        let interval = max(60, Double(store.settings.vocabularyWindowHours * 3600) / Double(limit))
        nextAutomaticVocabularyAt = date.addingTimeInterval(interval * Double.random(in: 0.75...1.25))
    }

    private func clearActiveVocabularyQuestion() {
        vocabularyQuestionTimer?.invalidate()
        vocabularyQuestionTimer = nil
        activeWord = nil
    }

    private func showIdleCuteMessageIfAppropriate() {
        guard window.isVisible,
              activeWord == nil,
              Date() >= progressPriorityUntil,
              !contentView.isBubbleVisible,
              Bool.random() else {
            return
        }
        let messages = [
            ("摸鱼雷达", "我只是路过看一眼。"),
            ("陪你上班", "喝口水，再继续也不迟。"),
            ("小提示", "我会安静一点，等你需要我。"),
            ("今日状态", "尾巴摆摆，任务继续。")
        ]
        guard let message = messages.randomElement() else { return }
        contentView.showMessage(kicker: AppBrand.displayName, title: message.0, body: message.1, showActions: false, autoHideAfter: 5)
    }

    private func chooseRandomPet() {
        let enabledPets = store.enabledPets()
        guard !enabledPets.isEmpty,
              let index = WeightedChoice.pickIndex(weights: enabledPets.map(\.weight)) else {
            activePet = nil
            contentView.setPetImage(nil)
            return
        }
        activePet = enabledPets[index]
        if let activePet {
            store.recordAppearance(for: activePet)
        }
        if let activePet {
            if activePet.kind == .codexPackage,
               let renderer = store.spriteRenderer(for: activePet) {
                contentView.setPetRenderer(renderer, fallbackImage: store.previewImage(for: activePet))
            } else if activePet.kind == .animatedImage,
                      let mediaURL = store.mediaURL(for: activePet) {
                contentView.setAnimatedPetRenderer(
                    AnimatedPetRenderer(url: mediaURL),
                    fallbackImage: store.previewImage(for: activePet)
                )
            } else if activePet.kind == .video,
                      let mediaURL = store.mediaURL(for: activePet) {
                contentView.setPetVideo(url: mediaURL)
            } else {
                contentView.setPetImage(store.previewImage(for: activePet))
            }
        }
    }

    func markKnown() {
        guard let word = activeWord else { return }
        vocabularyQuestionTimer?.invalidate()
        store.vocabularyProgress.mark(dictionaryID: word.dictionaryID, term: word.entry.term, action: .known)
        store.saveLearningProgress()
        setTemporaryAction(.waving, duration: 2.0)
        contentView.showMessage(
            kicker: "已学习",
            title: word.entry.term,
            body: "已标记为认识。之后它还会偶尔出现，但频率会降低。",
            showActions: false,
            footer: vocabularyFooterText()
        )
        activeWord = nil
    }

    func markUnknown() {
        guard let word = activeWord else { return }
        vocabularyQuestionTimer?.invalidate()
        store.vocabularyProgress.mark(dictionaryID: word.dictionaryID, term: word.entry.term, action: .unknown)
        store.saveLearningProgress()
        setTemporaryAction(.review, duration: 3.0)
        let explanation = [
            word.entry.meaning,
            word.entry.example.map { "例句：\($0)" },
            word.entry.hint.map { "提示：\($0)" }
        ].compactMap { $0 }.joined(separator: " ")
        contentView.showMessage(
            kicker: "待加强",
            title: word.entry.term,
            body: explanation,
            showActions: true,
            footer: vocabularyFooterText()
        )
        if !store.settings.vocabularyQuestionPersists {
            vocabularyQuestionTimer = Timer.scheduledTimer(withTimeInterval: 22, repeats: false) { [weak self] _ in
                self?.clearActiveVocabularyQuestion()
                self?.contentView.hideBubble(animated: true)
            }
            if let vocabularyQuestionTimer {
                RunLoop.main.add(vocabularyQuestionTimer, forMode: .common)
            }
        }
    }

    func skipWord() {
        guard let word = activeWord else { return }
        vocabularyQuestionTimer?.invalidate()
        store.vocabularyProgress.mark(dictionaryID: word.dictionaryID, term: word.entry.term, action: .skipped)
        store.saveLearningProgress()
        setTemporaryAction(.idle, duration: 0.8)
        contentView.showMessage(
            kicker: "已跳过",
            title: word.entry.term,
            body: "这个词后续出现频率会降低。",
            showActions: false,
            footer: vocabularyFooterText()
        )
        activeWord = nil
    }

    func requestVocabularyNow() {
        _ = showVocabularyNow(isAutomatic: false)
    }

    func openSettings() {
        showSettingsCenter()
    }

    func petClicked() {
        guard activeWord == nil, Date() >= progressPriorityUntil else {
            setTemporaryAction(.waving, duration: 1.0)
            return
        }
        let phrase = store.availablePetClickFeedbackPhrases.randomElement() ?? "我在这儿。"
        let action = [CodexPetAction.waving, .jumping, .review].randomElement() ?? .waving
        setTemporaryAction(action, duration: 1.4)
        contentView.showMessage(
            kicker: "",
            title: phrase,
            body: "",
            showActions: false,
            autoHideAfter: 4,
            presentation: .compact
        )
    }

    @objc private func showSettingsCenter() {
        if settingsWindowController == nil {
            settingsWindowController = SettingsWindowController(
                store: store,
                actions: SettingsActions(
                    uploadPhotos: { [weak self] in self?.uploadPetPhotos() },
                    importPetPackage: { [weak self] in self?.importCodexPackage() },
                    randomPreview: { [weak self] in self?.randomPetNow() },
                    importDictionary: { [weak self] in self?.importDictionary() },
                    openCSVTemplate: { [weak self] in self?.openTemplate(named: "dictionary-template.csv") },
                    openJSONTemplate: { [weak self] in self?.openTemplate(named: "dictionary-template.json") },
                    showImportFormat: { [weak self] in self?.showImportFormat() },
                    sendTestProgress: { [weak self] in self?.sendTestProgress() },
                    chooseSyncFolder: { [weak self] in self?.chooseSyncFolder() },
                    watchLogFile: { [weak self] in self?.watchLogFile() }
                )
            )
        }
        settingsWindowController?.show()
    }

    @objc private func showPet() {
        window.orderFrontRegardless()
    }

    @objc private func hidePet() {
        window.orderOut(nil)
    }

    @objc private func uploadPetPhotos() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [
            .image,
            .gif,
            .png,
            UTType(filenameExtension: "zip") ?? .data,
            .movie,
            .mpeg4Movie,
            UTType(filenameExtension: "apng") ?? .png
        ]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK else { return }

        var imported = 0
        for url in panel.urls {
            do {
                let pets = try store.importPetMediaItems(from: url)
                imported += pets.count
            } catch {
                contentView.showMessage(kicker: "宠物素材", title: "导入失败", body: error.localizedDescription, showActions: false)
            }
        }
        if imported > 0 {
            chooseRandomPet()
            contentView.showMessage(kicker: "宠物", title: "已导入 \(imported) 个素材", body: "图片 zip 会自动合成为 9 动作宠物；单张图片、GIF 和视频会按权重随机出现。", showActions: false)
        }
    }

    @objc private func importCodexPackage() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.prompt = "导入"
        guard panel.runModal() == .OK else { return }

        var imported = 0
        var mediaImported = 0
        for url in panel.urls {
            do {
                _ = try store.importCodexPackage(from: url)
                imported += 1
            } catch {
                if url.pathExtension.lowercased() == "zip",
                   let pets = try? store.importPetMediaItems(from: url),
                   !pets.isEmpty {
                    mediaImported += pets.count
                } else {
                    contentView.showMessage(kicker: "Pet 包", title: "导入失败", body: error.localizedDescription, showActions: false)
                }
            }
        }
        if imported > 0 || mediaImported > 0 {
            chooseRandomPet()
            let title = imported > 0
                ? "已导入 \(imported) 个宠物包"
                : "已导入 \(mediaImported) 个宠物素材"
            let body = mediaImported > 0
                ? "其中 \(mediaImported) 个图片/GIF/视频已作为宠物素材导入。"
                : "它们会和照片宠物一起随机出现。"
            contentView.showMessage(kicker: "Pet 包", title: title, body: body, showActions: false)
        }
    }

    @objc private func randomPetNow() {
        chooseRandomPet()
        setTemporaryAction(.waving, duration: 1.6)
    }

    @objc private func importDictionary() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "csv")!, UTType(filenameExtension: "json")!]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK else { return }

        var count = 0
        do {
            for url in panel.urls {
                let packs = try store.importDictionary(from: url)
                count += packs.reduce(0) { $0 + $1.entries.count }
            }
            contentView.showMessage(kicker: "词典", title: "已导入 \(count) 个词", body: "导入词典已自动启用，之后宠物会随机抽词。", showActions: false)
        } catch {
            contentView.showMessage(kicker: "词典", title: "导入失败", body: error.localizedDescription, showActions: false)
        }
    }

    @objc private func wordNow() {
        _ = showVocabularyNow(isAutomatic: false)
    }

    @objc private func chooseSyncFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Use Folder"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        store.setSyncDirectory(url)
        contentView.showMessage(
            kicker: "学习同步",
            title: "已启用同步文件",
            body: "学习记录会写入 \(url.lastPathComponent)/codex-desktop-pet-learning.json。",
            showActions: false
        )
    }

    @objc private func watchLogFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.plainText, .json]
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK else { return }
        for url in panel.urls where !store.settings.logPaths.contains(url.path) {
            store.settings.logPaths.append(url.path)
        }
        store.saveSettings()
        startLogWatcher()
        contentView.showMessage(
            kicker: "状态日志",
            title: "正在监听 \(panel.urls.count) 个文件",
            body: "只解析 JSON 状态行或 PET_PROGRESS 标记。",
            showActions: false
        )
    }

    private func sendTestProgress() {
        receiveProgress(ProgressEvent(
            source: "codex",
            stage: "测试进度",
            message: "配置中心发来的测试进度已成功显示。",
            progress: 66,
            status: .running,
            threadId: "settings-test"
        ))
    }

    private func openTemplate(named fileName: String) {
        let url = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("examples")
            .appendingPathComponent(fileName)
        if FileManager.default.fileExists(atPath: url.path) {
            NSWorkspace.shared.open(url)
        } else {
            contentView.showMessage(kicker: "模板", title: "没有找到模板文件", body: url.path, showActions: false)
        }
    }

    private func showImportFormat() {
        let message = "CSV 至少需要 term 和 meaning。推荐字段：dictionaryName, term, reading, phonetic, meaning, example, hint, tags。JSON 可导入 DictionaryPack 或 DictionaryEntry 数组。"
        contentView.showMessage(kicker: "词典格式", title: "CSV / JSON 导入说明", body: message, showActions: false)
        showSettingsCenter()
    }

    @objc private func toggleWalking(_ item: NSMenuItem) {
        store.settings.walkingPaused.toggle()
        item.state = store.settings.walkingPaused ? .on : .off
        store.saveSettings()
    }

    @objc private func toggleLockPosition(_ item: NSMenuItem) {
        store.settings.positionLocked.toggle()
        contentView.canDragWindow = !store.settings.positionLocked
        item.state = store.settings.positionLocked ? .on : .off
        store.saveSettings()
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
