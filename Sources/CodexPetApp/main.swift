import AppKit
import CodexPetCore
import UniformTypeIdentifiers

final class AppDelegate: NSObject, NSApplicationDelegate, PetContentViewDelegate, NSMenuDelegate {
    private var store: AppDataStore!
    private var window: NSPanel!
    private var contentView: PetContentView!
    private var petVisibility: PetVisibilityController!
    private var statusItem: NSStatusItem!
    private var settingsWindowController: SettingsWindowController?
    private var httpServer: LocalHTTPServer?
    private let logWatcher = StatusLogWatcher()

    private var activePet: PetAsset?
    private var activeWord: ScopedDictionaryEntry?
    private var vocabularyAnswerRevealed = false
    private var exampleTranslationTask: Task<Void, Never>?
    private var exampleTranslationStatus: String?
    private var progressPriorityUntil = Date.distantPast
    private var queuedVocabulary = false
    private var behaviorEngine = PetBehaviorEngine()
    private var temporaryAction: CodexPetAction?
    private var temporaryActionUntil = Date.distantPast
    private var walkTimer: Timer?
    private var vocabTimer: Timer?
    private var idleCuteTimer: Timer?
    private var vocabularyQuestionTimer: Timer?
    private var manualVocabularyTimer: Timer?
    private var nextAutomaticVocabularyAt = Date().addingTimeInterval(90)
    private var vocabularyScheduleKey: String?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.regular)
        do {
            let testRoot = ProcessInfo.processInfo.environment["WHISKYCLING_DATA_DIR"].map { URL(fileURLWithPath: $0) }
            store = try AppDataStore(root: testRoot)
            if let port = ProcessInfo.processInfo.environment["WHISKYCLING_PORT"].flatMap(UInt16.init) {
                store.settings.serverPort = port
            }
        } catch {
            fatalError("Cannot initialize app store: \(error)")
        }

        setupWindow()
        setupMenu()
        startHTTPServer()
        startLogWatcher()
        startTimers()
        chooseRandomPet()
        let welcomeURL = store.rootURL.appendingPathComponent("companion-welcome-seen")
        if CommandLine.arguments.contains("--settings") || !FileManager.default.fileExists(atPath: welcomeURL.path) {
            showSettingsCenter()
            try? Data().write(to: welcomeURL, options: .atomic)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        store.settings.lastWindowOrigin = window.frame.origin
        store.saveSettings()
        httpServer?.stop()
        logWatcher.stop()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettingsCenter()
        return false
    }

    private func setupWindow() {
        let screenFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1280, height: 800)
        let placement = PetWindowPlacement.frame(savedOrigin: store.settings.lastWindowOrigin,
            screens: NSScreen.screens.map(\.visibleFrame), main: screenFrame)
        let size = placement.size
        window = NSPanel(
            contentRect: placement,
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
        window.becomesKeyOnlyIfNeeded = true
        window.isReleasedWhenClosed = false

        contentView = PetContentView(frame: NSRect(origin: .zero, size: size))
        contentView.delegate = self
        contentView.canDragWindow = !store.settings.positionLocked
        contentView.applyTheme(store.settings.visualTheme)
        NotificationCenter.default.addObserver(self, selector: #selector(applyVisualTheme), name: .companionThemeDidChange, object: store)
        window.contentView = contentView
        petVisibility = PetVisibilityController(window: window, contentView: contentView, store: store)
        behaviorEngine.snap(to: window.frame.origin)
    }

    @objc private func applyVisualTheme() {
        contentView.applyTheme(store.settings.visualTheme)
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
        menu.delegate = self
        menu.addItem(NSMenuItem(title: "打开配置中心...", action: #selector(showSettingsCenter), keyEquivalent: ","))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "显示 \(AppBrand.displayName)", action: #selector(showPet), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "隐藏 \(AppBrand.displayName)", action: #selector(hidePet), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "仅在单词卡出现时显示宠物", action: #selector(toggleVocabularyOnlyPet), keyEquivalent: ""))
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
        let mainMenu = NSMenu()
        let applicationItem = NSMenuItem(title: AppBrand.displayName, action: nil, keyEquivalent: "")
        let applicationMenu = NSMenu()
        let settingsItem = NSMenuItem(title: "配置中心…", action: #selector(showSettingsCenter), keyEquivalent: ",")
        settingsItem.target = self
        applicationMenu.addItem(settingsItem)
        let wordItem = NSMenuItem(title: "现在抽一个词", action: #selector(wordNow), keyEquivalent: "n")
        wordItem.target = self
        applicationMenu.addItem(wordItem)
        let visibilityItem = NSMenuItem(title: "仅在单词卡出现时显示宠物", action: #selector(toggleVocabularyOnlyPet), keyEquivalent: "")
        visibilityItem.target = self
        applicationMenu.addItem(visibilityItem)
        applicationMenu.delegate = self
        applicationMenu.addItem(.separator())
        let quitItem = NSMenuItem(title: "退出 \(AppBrand.displayName)", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        applicationMenu.addItem(quitItem)
        applicationItem.submenu = applicationMenu
        mainMenu.addItem(applicationItem)
        NSApp.mainMenu = mainMenu
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
            },
            vocabularyToken: store.captureToken,
            vocabularyHandler: { [weak self] method, body in
                try DispatchQueue.main.sync {
                    guard let self else { throw CaptureError.invalid("桌宠已退出。") }
                    return try self.store.handleVocabularyRequest(method: method, body: body)
                }
            },
            lookupHandler: { [weak self] body in
                guard let self else { throw CaptureError.invalid("桌宠已退出。") }
                return try await self.store.lookupVocabulary(body)
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
        if store.settings.walkingPaused || store.settings.positionLocked || contentView.isBubbleVisible {
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
        setTemporaryAction(event.status.petAction, duration: isCompletion ? 3.2 : 8)
        contentView.showProgressEvent(event)
        progressPriorityUntil = contentView.progressPriorityDeadline ?? Date().addingTimeInterval(isCompletion ? 12 : 8)
        if event.status == .done || event.status == .failed {
            queuedVocabulary = true
        }
        if manualVocabularyTimer != nil { resumeManualVocabularyRequest() }
    }

    private func showVocabularyRespectingPriority() {
        let now = Date()
        let key = "\(VocabularyDisplayScheduler.todayKey(for: now))-\(store.settings.vocabularyStudyStartMinute)-\(store.settings.vocabularyStudyEndMinute)-\(store.settings.dailyVocabularyLimit)-\(store.settings.dailyNewVocabularyLimit)-\(store.settings.dailyVocabularyUnlimited)-\(store.settings.dailyNewVocabularyUnlimited)-\(store.settings.vocabularyMinimumIntervalMinutes)"
        if let oldKey = vocabularyScheduleKey, oldKey != key {
            nextAutomaticVocabularyAt = max(now, (store.settings.lastAutomaticVocabularyDate ?? .distantPast).addingTimeInterval(Double(store.settings.vocabularyMinimumIntervalMinutes) * 60))
        }
        vocabularyScheduleKey = key
        store.resetVocabularyScheduleIfNeeded(now: now)
        guard activeWord == nil else { return }
        if Date() < progressPriorityUntil {
            queuedVocabulary = true
            return
        }
        guard now >= nextAutomaticVocabularyAt else { return }
        guard now.timeIntervalSince(store.settings.lastAutomaticVocabularyDate ?? .distantPast) >= Double(store.settings.vocabularyMinimumIntervalMinutes) * 60 else { return }
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
        guard Date() >= progressPriorityUntil else { return false }
        guard activeWord == nil else { return false }
        guard let selected = store.nextReviewWord(automatic: isAutomatic) else {
            if !isAutomatic {
                contentView.showMessage(
                    kicker: "词典",
                    title: "暂时没有待复习词",
                    body: "可以收藏新词、启用词典，或等下次复习到期。",
                    showActions: false
                )
            }
            return false
        }
        vocabularyQuestionTimer?.invalidate()
        activeWord = selected
        exampleTranslationStatus = nil
        vocabularyAnswerRevealed = !store.settings.vocabularyRecallMode
        store.recordVocabularyPresentation(selected, automatic: isAutomatic)
        chooseRandomPet()
        setTemporaryAction(.jumping, duration: 1.2)

        renderVocabularyCard(selected)
        if vocabularyAnswerRevealed { completeExampleTranslation(selected) }
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


    private func configureVocabularyControls(for word: ScopedDictionaryEntry) {
        contentView.configureVocabularyControls(revealed: vocabularyAnswerRevealed,
            known: store.reviewPreview(word, action: .known),
            unknown: store.reviewPreview(word, action: .unknown),
            hard: store.reviewPreview(word, action: .hard))
    }

    private func renderVocabularyCard(_ word: ScopedDictionaryEntry) {
        contentView.showVocabularyCard(kicker: word.dictionaryName, entry: word.entry,
            revealed: vocabularyAnswerRevealed, footer: vocabularyFooterText(),
            known: store.reviewPreview(word, action: .known), unknown: store.reviewPreview(word, action: .unknown),
            hard: store.reviewPreview(word, action: .hard), translationStatus: exampleTranslationStatus)
    }

    private func completeExampleTranslation(_ word: ScopedDictionaryEntry) {
        exampleTranslationTask?.cancel()
        guard word.entry.exampleTranslation == nil, let sentence = word.entry.example,
              sentence.range(of: "[一-龯]", options: .regularExpression) == nil ||
                sentence.range(of: "[ぁ-んァ-ン]", options: .regularExpression) != nil else { return }
        let key = word.statKey + "|" + sentence
        let cacheURL = store.rootURL.appendingPathComponent("example-translations.json")
        var cache = JSONFileStore.load([String: String].self, from: cacheURL, fallback: [:])
        if let translation = cache[key] {
            activeWord?.entry.exampleTranslation = translation
            if let activeWord { renderVocabularyCard(activeWord) }
            return
        }
        guard KeychainStore.readExampleAPIKey(provider: .deepSeek) != nil else { return }
        exampleTranslationStatus = "译文补全中…"
        exampleTranslationTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                guard let translation = try await store.translatedExample(for: word.entry), !Task.isCancelled else { return }
                cache = JSONFileStore.load([String: String].self, from: cacheURL, fallback: [:])
                cache[key] = translation
                try JSONFileStore.save(cache, to: cacheURL)
                guard activeWord?.statKey == word.statKey, activeWord?.entry.example == sentence else { return }
                activeWord?.entry.exampleTranslation = translation
                if vocabularyAnswerRevealed, let activeWord { renderVocabularyCard(activeWord) }
            } catch {
                guard !Task.isCancelled, activeWord?.statKey == word.statKey else { return }
                exampleTranslationStatus = "译文暂未加载，下次复习会重试。"
                if let activeWord, vocabularyAnswerRevealed { renderVocabularyCard(activeWord) }
            }
        }
    }

    func revealVocabularyAnswer() {
        guard let word = activeWord, !vocabularyAnswerRevealed else { return }
        vocabularyAnswerRevealed = true
        renderVocabularyCard(word)
        completeExampleTranslation(word)
    }


    private func vocabularyFooterText() -> String {
        guard let word = activeWord else { return "" }
        let pack = (store.dictionaries + store.personalVocabulary.packs).first { $0.id == word.dictionaryID }
        let entries = (pack?.entries ?? []).map {
            ScopedDictionaryEntry(dictionaryID: word.dictionaryID, dictionaryName: word.dictionaryName, entry: $0)
        }
        let progress = VocabularyStudyProgress(entries: entries, stats: store.vocabularyProgress.stats)
        return "本词典已学 \(progress.studied)/\(progress.total) · 今日反馈 \(progress.answeredToday) 词"
    }

    private func scheduleNextAutomaticVocabulary(after date: Date) {
        let snapshot = VocabularyDisplayScheduler.resetIfNeeded(store.vocabularyScheduleSnapshot, now: date)
        let interval = VocabularyDisplayScheduler.automaticInterval(snapshot, now: date,
            unlimited: store.settings.dailyVocabularyUnlimited, minimumMinutes: store.settings.vocabularyMinimumIntervalMinutes,
            jitter: Double.random(in: 0.75...1.25))
        nextAutomaticVocabularyAt = date.addingTimeInterval(interval)
    }

    private func clearActiveVocabularyQuestion() {
        exampleTranslationTask?.cancel()
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
        finishVocabularyFeedback(.known)
    }

    func markUnknown() {
        finishVocabularyFeedback(.unknown)
    }

    func markHard() { finishVocabularyFeedback(.hard) }

    func skipWord() {
        finishVocabularyFeedback(.skipped)
    }

    private func finishVocabularyFeedback(_ action: WordAction) {
        guard let word = activeWord else { return }
        guard action == .skipped || vocabularyAnswerRevealed else { return }
        do { try store.reviewWord(word, action: action) }
        catch {
            contentView.showMessage(kicker: "保存失败", title: word.entry.term,
                body: error.localizedDescription, showActions: true)
            configureVocabularyControls(for: word)
            return
        }
        setTemporaryAction(action == .known ? .waving : .review, duration: 1.6)
        clearActiveVocabularyQuestion()
        contentView.hideBubble(animated: true)
    }

    func requestVocabularyNow() {
        petVisibility.show()
        resumeManualVocabularyRequest()
    }

    private func resumeManualVocabularyRequest() {
        manualVocabularyTimer?.invalidate()
        manualVocabularyTimer = nil
        guard !petVisibility.isManuallyHidden else { return }
        guard activeWord == nil else { return }
        let remainingPriority = progressPriorityUntil.timeIntervalSinceNow
        if remainingPriority > 0 {
            manualVocabularyTimer = Timer.scheduledTimer(withTimeInterval: remainingPriority + 0.05, repeats: false) { [weak self] _ in
                self?.resumeManualVocabularyRequest()
            }
            if let manualVocabularyTimer { RunLoop.main.add(manualVocabularyTimer, forMode: .common) }
            return
        }
        _ = showVocabularyNow(isAutomatic: false)
    }

    func openSettings() {
        showSettingsCenter()
    }

    var petWalkingPaused: Bool { store?.settings.walkingPaused ?? false }

    func togglePetWalking() {
        store.setWalkingPaused(!store.settings.walkingPaused)
        behaviorEngine.snap(to: window.frame.origin)
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        for item in menu.items {
            if item.action == #selector(toggleWalking) { item.state = store.settings.walkingPaused ? .on : .off }
            if item.action == #selector(toggleLockPosition) { item.state = store.settings.positionLocked ? .on : .off }
            if item.action == #selector(toggleVocabularyOnlyPet) { item.state = store.settings.petOnlyWithVocabulary ? .on : .off }
        }
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
                    watchLogFile: { [weak self] in self?.watchLogFile() },
                    studyNow: { [weak self] in self?.requestVocabularyNow() }
                )
            )
        }
        settingsWindowController?.show()
    }

    @objc private func showPet() {
        petVisibility.show()
        if store.settings.petOnlyWithVocabulary { requestVocabularyNow() }
    }

    @objc private func hidePet() {
        manualVocabularyTimer?.invalidate()
        manualVocabularyTimer = nil
        petVisibility.hide()
    }

    @objc private func toggleVocabularyOnlyPet() {
        do { try store.setPetOnlyWithVocabulary(!store.settings.petOnlyWithVocabulary) }
        catch {
            let alert = NSAlert()
            alert.messageText = "显示设置未保存"
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
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
        requestVocabularyNow()
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
        togglePetWalking()
        item.state = store.settings.walkingPaused ? .on : .off
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
if CommandLine.arguments.contains("--self-test-learning-plan") {
    Task { @MainActor in
        do { try await LearningPlanRegression.run(); exit(0) }
        catch { fputs("learning-plan-regression failed: \(error)\n", stderr); exit(1) }
    }
    app.run()
    exit(1)
}
if CommandLine.arguments.contains("--export-user-guide") {
    Task { @MainActor in
        do { try await UserGuideSnapshots.run(); exit(0) }
        catch { fputs("user-guide snapshots failed: \(error)\n", stderr); exit(1) }
    }
    app.run()
    exit(1)
}
if CommandLine.arguments.contains("--self-test-enrichment") {
    Task { @MainActor in
        do { try await NotebookRegression.runEnrichment(); exit(0) }
        catch { fputs("enrichment-regression failed: \(error)\n", stderr); exit(1) }
    }
    app.run()
    exit(1)
}
if CommandLine.arguments.contains("--self-test-notebook") {
    Task { @MainActor in
        do { try await NotebookRegression.run(); exit(0) }
        catch { fputs("notebook-regression failed: \(error)\n", stderr); exit(1) }
    }
    app.run()
    exit(1)
}
let delegate = AppDelegate()
app.delegate = delegate
app.run()
