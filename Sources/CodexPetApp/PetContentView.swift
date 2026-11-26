import AppKit
import AVFoundation
import CodexPetCore
import QuartzCore

protocol PetContentViewDelegate: AnyObject {
    func markKnown()
    func markUnknown()
    func markHard()
    func revealVocabularyAnswer()
    func skipWord()
    func requestVocabularyNow()
    func openSettings()
    func petClicked()
    var petWalkingPaused: Bool { get }
    func togglePetWalking()
}

enum BubblePresentation {
    case standard
    case compact
}

private final class PetActionButton: NSButton {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

private final class PetTextDocument: NSView {
    override var isFlipped: Bool { true }
}

final class PetContentView: NSView {
    weak var delegate: PetContentViewDelegate?
    var canDragWindow = true
    var onPresentationChange: (() -> Void)?
    private var presentationUpdateDepth = 0
    private(set) var visualTheme: AppVisualTheme = .comic

    func applyTheme(_ theme: AppVisualTheme) {
        guard visualTheme != theme else { return }
        visualTheme = theme
        bubbleView.theme = theme
        progressStack.theme = theme
        titleLabel.textColor = theme.inkNSColor
        kickerLabel.textColor = theme == .comic ? NSColor(calibratedWhite: 0.38, alpha: 1) : theme.accentNSColor
        if vocabularyEntry != nil {
            renderVocabularyText()
        } else {
            let text = NSMutableAttributedString(attributedString: bodyLabel.attributedStringValue)
            text.addAttribute(.foregroundColor, value: theme.inkNSColor, range: NSRange(location: 0, length: text.length))
            bodyLabel.attributedStringValue = text
        }
        styleActionButton(knownButton, background: theme.accentNSColor, foreground: .white)
        styleActionButton(revealButton, background: theme.accentNSColor, foreground: .white)
        let neutral = theme == .comic ? NSColor(calibratedWhite: 0.96, alpha: 1) : theme.washNSColor
        styleActionButton(unknownButton, background: neutral, foreground: theme.inkNSColor)
        styleActionButton(hardButton, background: neutral, foreground: theme.inkNSColor)
        styleActionButton(skipButton, background: .clear, foreground: NSColor(calibratedWhite: 0.43, alpha: 1))
        skipButton.font = .systemFont(ofSize: 11.5, weight: .medium)
        needsLayout = true
    }

    private let bubbleView = SpeechBubbleBackgroundView()
    private let progressStack = CompanionProgressStackView()
    private var messagePresentation: BubblePresentation = .standard
    private let kickerLabel = NSTextField(labelWithString: "")
    private let titleLabel = NSTextField(wrappingLabelWithString: "")
    private let bodyLabel = NSTextField(wrappingLabelWithString: "")
    private let vocabularyTextView = NSTextView()
    private let bodyScroll = NSScrollView()
    private let bodyDocument = PetTextDocument()
    private let contextPanel = NSView()
    private let contextTextView = NSTextView()
    private var vocabularyEntry: DictionaryEntry?
    private var vocabularyRevealed = false
    private var translationStatus: String?
    private var resetBodyScroll = false
    private var sizingBody: String?
    private var vocabularyLayoutKey: String?
    private var lockedVocabularySize: NSSize?
    private let footerLabel = NSTextField(labelWithString: "")
    private let knownButton = PetActionButton(title: "认识啦", target: nil, action: nil)
    private let unknownButton = PetActionButton(title: "不认识", target: nil, action: nil)
    private let skipButton = PetActionButton(title: "先跳过", target: nil, action: nil)
    private let hardButton = PetActionButton(title: "有点印象", target: nil, action: nil)
    private let revealButton = PetActionButton(title: "查看释义", target: nil, action: nil)
    private let petContainer = NSView()
    private let imageView = NSImageView()
    private let videoView = NSView()
    private let defaultPixelPet = DefaultPixelPetView()

    private var dragStartPoint: NSPoint?
    private var dragWindowOrigin: NSPoint?
    private var animationRenderer: PetAnimationRenderer?
    private var animatedRenderer: AnimatedPetRenderer?
    private var player: AVPlayer?
    private var playerLayer: AVPlayerLayer?
    private var currentAction: CodexPetAction = .idle
    private var frameIndex = 0
    private var spriteFrameElapsed: TimeInterval = 0
    private var frameTimer: Timer?
    private var bubbleHideTimer: Timer?
    private var bubbleRevision = 0
    private var clickStartedOnPet = false
    private var didDrag = false
    private let frameTimerInterval: TimeInterval = 1.0 / 30.0
    private let spriteFrameInterval: TimeInterval = 0.16

    var isBubbleVisible: Bool {
        !bubbleView.isHidden || progressStack.hasVisibleEvents
    }

    var hasVisibleVocabularyCard: Bool { !bubbleView.isHidden && bubbleView.style == .vocabulary }
    var isPetVisible: Bool { !petContainer.isHidden }

    func setPetVisible(_ visible: Bool) {
        guard petContainer.isHidden == visible else { return }
        petContainer.isHidden = !visible
        if visible {
            player?.play()
            startBreathingAnimation()
        } else {
            player?.pause()
            petContainer.layer?.removeAllAnimations()
            clickStartedOnPet = false
            dragStartPoint = nil
            dragWindowOrigin = nil
            didDrag = false
        }
    }

    private func notifyPresentationChange() {
        if presentationUpdateDepth == 0 { onPresentationChange?() }
    }

    var progressPriorityDeadline: Date? { progressStack.priorityDeadline }

    var visualLayoutSnapshot: (pet: NSRect, message: NSRect, progress: NSRect, titleFont: CGFloat) {
        (petContainer.frame, bubbleView.frame, progressStack.frame, titleLabel.font?.pointSize ?? 0)
    }

    func showProgressEvent(_ event: ProgressEvent) {
        presentationUpdateDepth += 1
        defer { presentationUpdateDepth -= 1; notifyPresentationChange() }
        hideBubble(animated: false, preservingProgress: true)
        vocabularyEntry = nil
        vocabularyTextView.isHidden = true
        contextPanel.isHidden = true
        progressStack.receive(event)
        needsLayout = true
        layoutSubtreeIfNeeded()
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    var bubbleLayoutSnapshot: (bubble: NSRect, controls: [NSRect]) {
        (bubbleView.frame, [revealButton, unknownButton, hardButton, knownButton, skipButton]
            .filter { !$0.isHidden }.map(\.frame))
    }

    var vocabularyTypographySnapshot: (text: NSAttributedString, viewport: NSRect, document: NSRect, context: NSRect, contextVisible: Bool, scrollOffset: NSPoint, footer: String, contextText: NSAttributedString) {
        (vocabularyEntry == nil ? bodyLabel.attributedStringValue : vocabularyTextView.attributedString(), bodyScroll.frame, bodyDocument.frame, contextPanel.frame,
         !contextPanel.isHidden, bodyScroll.contentView.bounds.origin, footerLabel.stringValue, contextTextView.attributedString())
    }

    func showVocabularyCard(kicker: String, entry: DictionaryEntry, revealed: Bool, footer: String,
                            known: String, unknown: String, hard: String, translationStatus: String? = nil) {
        presentationUpdateDepth += 1
        defer { presentationUpdateDepth -= 1; notifyPresentationChange() }
        let key = kicker + "|" + entry.term
        let sameWord = vocabularyLayoutKey == key
        let samePresentation = sameWord && vocabularyRevealed == revealed
        let previousSize = samePresentation ? lockedVocabularySize : nil
        if !sameWord {
            showMessage(kicker: kicker, title: "", body: "", showActions: true, footer: footer, animated: false)
        } else {
            bubbleHideTimer?.invalidate()
            footerLabel.stringValue = footer
        }
        vocabularyLayoutKey = key
        lockedVocabularySize = previousSize
        vocabularyEntry = entry
        vocabularyRevealed = revealed
        self.translationStatus = translationStatus
        titleLabel.isHidden = true
        kickerLabel.alignment = .left
        bodyLabel.isHidden = false
        resetBodyScroll = !samePresentation
        renderVocabularyText()
        configureVocabularyControls(revealed: revealed, known: known, unknown: unknown, hard: hard)
        needsLayout = true
        layoutSubtreeIfNeeded()
        lockedVocabularySize = bubbleView.frame.size
    }

    func showVocabularyCard(kicker: String, title: String, prompt: String, answer: String,
                            revealed: Bool, footer: String, known: String, unknown: String, hard: String) {
        presentationUpdateDepth += 1
        defer { presentationUpdateDepth -= 1; notifyPresentationChange() }
        let key = kicker + "|" + title
        let previousSize = vocabularyLayoutKey == key && vocabularyRevealed == revealed ? lockedVocabularySize : nil
        showMessage(kicker: kicker, title: title, body: revealed ? answer : prompt,
                    showActions: true, footer: footer, animated: false)
        vocabularyLayoutKey = key
        lockedVocabularySize = previousSize
        vocabularyRevealed = revealed
        sizingBody = revealed ? answer : prompt
        configureVocabularyControls(revealed: revealed, known: known, unknown: unknown, hard: hard)
        needsLayout = true
        layoutSubtreeIfNeeded()
        lockedVocabularySize = bubbleView.frame.size
    }

    private var usesProceduralActionAnimation: Bool {
        animationRenderer == nil && animatedRenderer == nil && player == nil
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        startBreathingAnimation()
        startFrameTimer()
    }

    func showMessage(
        kicker: String,
        title: String,
        body: String,
        showActions: Bool,
        footer: String? = nil,
        autoHideAfter: TimeInterval? = nil,
        presentation: BubblePresentation = .standard,
        bodyAlignment: NSTextAlignment = .center,
        animated: Bool = true
    ) {
        presentationUpdateDepth += 1
        defer { presentationUpdateDepth -= 1; notifyPresentationChange() }
        bubbleHideTimer?.invalidate()
        progressStack.clear()
        messagePresentation = presentation
        bubbleView.style = showActions ? .vocabulary : presentation == .compact ? .feedback : .notification
        vocabularyEntry = nil
        vocabularyTextView.isHidden = true
        contextPanel.isHidden = true
        titleLabel.isHidden = false
        kickerLabel.alignment = .left
        kickerLabel.font = .systemFont(ofSize: 10.5, weight: .medium)
        sizingBody = nil
        vocabularyLayoutKey = nil
        lockedVocabularySize = nil
        bubbleRevision += 1
        let cleanKicker = kicker.trimmingCharacters(in: .whitespacesAndNewlines)
        kickerLabel.stringValue = cleanKicker
        kickerLabel.isHidden = cleanKicker.isEmpty
        titleLabel.stringValue = title
        titleLabel.font = .systemFont(ofSize: presentation == .compact ? 15 : 14, weight: .semibold)
        titleLabel.alignment = presentation == .compact ? .center : .left
        setBodyText(body, alignment: showActions ? bodyAlignment : .left, presentation: presentation)
        resetBodyScroll = true
        bodyLabel.isHidden = body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        footerLabel.stringValue = footer ?? ""
        footerLabel.font = .monospacedSystemFont(ofSize: 14, weight: .medium)
        footerLabel.isHidden = footer?.isEmpty ?? true
        knownButton.isHidden = !showActions
        unknownButton.isHidden = !showActions
        skipButton.isHidden = !showActions
        hardButton.isHidden = true
        revealButton.isHidden = true
        bubbleView.randomizeStyle()
        bubbleView.isHidden = false
        needsLayout = true
        layoutSubtreeIfNeeded()
        if animated && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.16
                bubbleView.animator().alphaValue = 1
            }
        } else {
            bubbleView.alphaValue = 1
        }

        let resolvedAutoHide = autoHideAfter ?? (showActions ? nil : 6)
        if let resolvedAutoHide {
            bubbleHideTimer = Timer.scheduledTimer(withTimeInterval: resolvedAutoHide, repeats: false) { [weak self] _ in
                self?.hideBubble(animated: true)
            }
            if let bubbleHideTimer {
                RunLoop.main.add(bubbleHideTimer, forMode: .common)
            }
        }
    }

    func hideBubble(animated: Bool, preservingProgress: Bool = false) {
        if !preservingProgress { progressStack.clear() }
        vocabularyLayoutKey = nil
        lockedVocabularySize = nil
        bubbleRevision += 1
        let revision = bubbleRevision
        bubbleHideTimer?.invalidate()
        bubbleHideTimer = nil
        knownButton.isHidden = true
        unknownButton.isHidden = true
        skipButton.isHidden = true
        hardButton.isHidden = true
        revealButton.isHidden = true

        let complete = { [weak self] in
            guard let self, self.bubbleRevision == revision else { return }
            self.bubbleView.isHidden = true
            self.bubbleView.alphaValue = 0
            self.notifyPresentationChange()
        }
        guard animated, !bubbleView.isHidden else {
            complete()
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.16
            bubbleView.animator().alphaValue = 0
        } completionHandler: {
            complete()
        }
    }

    func setPetImage(_ image: NSImage?) {
        clearVideo()
        animationRenderer = nil
        animatedRenderer = nil
        spriteFrameElapsed = 0
        withoutImplicitLayerAnimations {
            imageView.layer?.transform = CATransform3DIdentity
            imageView.image = image
            imageView.isHidden = image == nil
            videoView.isHidden = true
            defaultPixelPet.isHidden = image != nil
        }
        startBreathingAnimation()
    }

    func configureVocabularyControls(revealed: Bool, known: String, unknown: String, hard: String) {
        revealButton.isHidden = revealed
        knownButton.isHidden = !revealed
        unknownButton.isHidden = !revealed
        hardButton.isHidden = !revealed
        knownButton.title = "认识啦"
        unknownButton.title = "不认识"
        skipButton.title = "稍后再看"
        knownButton.toolTip = "下次复习：\(known)"
        unknownButton.toolTip = "下次复习：\(unknown)"
        hardButton.toolTip = "想起来了但费力；下次复习：\(hard)"
        footerLabel.stringValue += revealed ? "\n不认识 \(unknown) · 印象 \(hard) · 认识 \(known)" : ""
        footerLabel.font = .systemFont(ofSize: 11, weight: .medium)
        footerLabel.maximumNumberOfLines = 2
        needsLayout = true
    }

    func setPetRenderer(_ renderer: PetAnimationRenderer?, fallbackImage: NSImage?) {
        clearVideo()
        animationRenderer = renderer
        animatedRenderer = nil
        frameIndex = 0
        spriteFrameElapsed = 0
        withoutImplicitLayerAnimations {
            imageView.layer?.transform = CATransform3DIdentity
            if let renderer, let frame = renderer.frame(for: currentAction, frameIndex: frameIndex) ?? renderer.stillFrame() {
                imageView.image = frame
                imageView.isHidden = false
                videoView.isHidden = true
                defaultPixelPet.isHidden = true
            } else {
                imageView.image = fallbackImage
                imageView.isHidden = fallbackImage == nil
                videoView.isHidden = true
                defaultPixelPet.isHidden = fallbackImage != nil
            }
        }
        applyActionAnimation(currentAction)
    }

    func setAnimatedPetRenderer(_ renderer: AnimatedPetRenderer?, fallbackImage: NSImage?) {
        clearVideo()
        animationRenderer = nil
        animatedRenderer = renderer
        frameIndex = 0
        spriteFrameElapsed = 0
        withoutImplicitLayerAnimations {
            imageView.layer?.transform = CATransform3DIdentity
            imageView.image = renderer?.stillFrame ?? fallbackImage
            imageView.isHidden = imageView.image == nil
            videoView.isHidden = true
            defaultPixelPet.isHidden = imageView.image != nil
        }
        applyActionAnimation(currentAction)
    }

    func setPetVideo(url: URL) {
        animationRenderer = nil
        animatedRenderer = nil
        spriteFrameElapsed = 0
        imageView.image = nil
        imageView.isHidden = true
        defaultPixelPet.isHidden = true
        videoView.isHidden = false

        clearVideo()
        let item = AVPlayerItem(url: url)
        let player = AVPlayer(playerItem: item)
        player.isMuted = true
        player.actionAtItemEnd = .none
        let layer = AVPlayerLayer(player: player)
        layer.videoGravity = .resizeAspect
        layer.frame = videoView.bounds
        videoView.layer?.addSublayer(layer)
        self.player = player
        self.playerLayer = layer
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(videoDidFinish(_:)),
            name: .AVPlayerItemDidPlayToEndTime,
            object: item
        )
        if !petContainer.isHidden { player.play() }
        applyActionAnimation(currentAction)
    }

    func setPetAction(_ action: CodexPetAction) {
        guard action != currentAction else { return }
        currentAction = action
        frameIndex = 0
        spriteFrameElapsed = 0
        renderCurrentFrame()
        applyActionAnimation(action)
    }

    override func mouseDown(with event: NSEvent) {
        guard !petContainer.isHidden, petContainer.frame.contains(convert(event.locationInWindow, from: nil)) else {
            clickStartedOnPet = false
            didDrag = false
            dragStartPoint = nil
            dragWindowOrigin = nil
            return
        }
        if event.modifierFlags.contains(.control), petContainer.frame.contains(convert(event.locationInWindow, from: nil)) {
            presentPetMenu(with: event)
            return
        }
        dragStartPoint = window?.convertPoint(toScreen: event.locationInWindow)
        dragWindowOrigin = window?.frame.origin
        clickStartedOnPet = petContainer.frame.contains(event.locationInWindow)
        didDrag = false
    }

    override func rightMouseDown(with event: NSEvent) {
        guard menu(for: event) != nil else {
            super.rightMouseDown(with: event)
            return
        }
        presentPetMenu(with: event)
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        guard !petContainer.isHidden, petContainer.frame.contains(convert(event.locationInWindow, from: nil)) else { return nil }
        clickStartedOnPet = false
        didDrag = false
        dragStartPoint = nil
        dragWindowOrigin = nil
        let menu = NSMenu()
        menu.autoenablesItems = false
        let word = NSMenuItem(title: "单词", action: #selector(requestWordFromPet), keyEquivalent: "")
        word.image = NSImage(systemSymbolName: "character.book.closed", accessibilityDescription: nil)
        word.target = self
        menu.addItem(word)
        let settings = NSMenuItem(title: "配置中心…", action: #selector(openPetSettings), keyEquivalent: "")
        settings.image = NSImage(systemSymbolName: "gearshape", accessibilityDescription: nil)
        settings.target = self
        menu.addItem(settings)
        menu.addItem(.separator())
        let pause = NSMenuItem(title: delegate?.petWalkingPaused == true ? "继续走动" : "暂停走动",
            action: #selector(togglePetMovement), keyEquivalent: "")
        pause.image = NSImage(systemSymbolName: delegate?.petWalkingPaused == true ? "play" : "pause", accessibilityDescription: nil)
        pause.target = self
        menu.addItem(pause)
        return menu
    }

    private func presentPetMenu(with event: NSEvent) {
        guard let menu = menu(for: event) else { return }
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    @objc private func requestWordFromPet() {
        delegate?.requestVocabularyNow()
    }

    @objc private func openPetSettings() { delegate?.openSettings() }
    @objc private func togglePetMovement() { delegate?.togglePetWalking() }

    override func mouseDragged(with event: NSEvent) {
        guard canDragWindow,
              let window,
              let dragStartPoint,
              let dragWindowOrigin else {
            return
        }
        let currentPoint = window.convertPoint(toScreen: event.locationInWindow)
        let delta = NSPoint(x: currentPoint.x - dragStartPoint.x, y: currentPoint.y - dragStartPoint.y)
        if hypot(delta.x, delta.y) > 4 {
            didDrag = true
        }
        window.setFrameOrigin(NSPoint(x: dragWindowOrigin.x + delta.x, y: dragWindowOrigin.y + delta.y))
    }

    override func mouseUp(with event: NSEvent) {
        defer {
            clickStartedOnPet = false
            dragStartPoint = nil
            dragWindowOrigin = nil
            didDrag = false
        }
        guard clickStartedOnPet,
              !petContainer.isHidden,
              !didDrag,
              petContainer.frame.contains(event.locationInWindow) else {
            return
        }
        delegate?.petClicked()
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        if !bubbleView.isHidden, bubbleView.frame.contains(point) {
            return super.hitTest(point)
        }
        if progressStack.hasVisibleEvents, progressStack.frame.contains(point) {
            return super.hitTest(point)
        }
        if !petContainer.isHidden, petContainer.frame.contains(point) {
            return self
        }
        return nil
    }

    private func setup() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor

        bubbleView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(bubbleView)
        addSubview(progressStack)
        progressStack.onChange = { [weak self] in
            self?.needsLayout = true
            self?.notifyPresentationChange()
        }

        kickerLabel.font = .systemFont(ofSize: 14, weight: .heavy)
        kickerLabel.textColor = NSColor(calibratedWhite: 0.38, alpha: 1)
        kickerLabel.alignment = .center
        kickerLabel.lineBreakMode = .byTruncatingTail
        titleLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        titleLabel.textColor = NSColor(calibratedWhite: 0.13, alpha: 1)
        titleLabel.alignment = .center
        titleLabel.lineBreakMode = .byWordWrapping
        titleLabel.maximumNumberOfLines = 2
        bodyLabel.maximumNumberOfLines = 0
        footerLabel.font = .monospacedSystemFont(ofSize: 16, weight: .bold)
        footerLabel.textColor = NSColor(calibratedWhite: 0.45, alpha: 1)
        footerLabel.alignment = .center

        knownButton.target = self
        knownButton.action = #selector(knownTapped)
        unknownButton.target = self
        unknownButton.action = #selector(unknownTapped)
        skipButton.target = self
        skipButton.action = #selector(skipTapped)
        hardButton.target = self
        hardButton.action = #selector(hardTapped)
        revealButton.target = self
        revealButton.action = #selector(revealTapped)
        styleActionButton(knownButton, background: NSColor(calibratedWhite: 0.08, alpha: 1), foreground: .white)
        styleActionButton(unknownButton, background: NSColor(calibratedWhite: 0.96, alpha: 1), foreground: .black)
        styleActionButton(skipButton, background: .clear, foreground: .darkGray)
        styleActionButton(hardButton, background: NSColor(calibratedWhite: 0.96, alpha: 1), foreground: .black)
        styleActionButton(revealButton, background: NSColor(calibratedWhite: 0.08, alpha: 1), foreground: .white)

        bodyScroll.drawsBackground = false
        bodyScroll.hasVerticalScroller = true
        bodyScroll.autohidesScrollers = true
        bodyScroll.borderType = .noBorder
        bodyScroll.scrollerStyle = .overlay
        bodyDocument.addSubview(bodyLabel)
        vocabularyTextView.isEditable = false
        vocabularyTextView.isSelectable = true
        vocabularyTextView.isRichText = true
        vocabularyTextView.drawsBackground = false
        vocabularyTextView.textContainerInset = .zero
        vocabularyTextView.textContainer?.lineFragmentPadding = 0
        vocabularyTextView.isHorizontallyResizable = false
        vocabularyTextView.isVerticallyResizable = false
        vocabularyTextView.isHidden = true
        bodyDocument.addSubview(vocabularyTextView)
        contextPanel.wantsLayer = true
        contextPanel.layer?.cornerRadius = 6
        contextTextView.isEditable = false
        contextTextView.isSelectable = true
        contextTextView.isRichText = true
        contextTextView.drawsBackground = false
        contextTextView.textContainerInset = .zero
        contextTextView.textContainer?.lineFragmentPadding = 0
        contextTextView.isHorizontallyResizable = false
        contextTextView.isVerticallyResizable = false
        contextPanel.addSubview(contextTextView)
        bodyDocument.addSubview(contextPanel)
        bodyScroll.documentView = bodyDocument
        for view in [kickerLabel, titleLabel, bodyScroll, footerLabel, revealButton, unknownButton, hardButton, knownButton, skipButton] {
            bubbleView.addSubview(view)
        }

        petContainer.translatesAutoresizingMaskIntoConstraints = false
        petContainer.wantsLayer = true
        addSubview(petContainer)

        videoView.translatesAutoresizingMaskIntoConstraints = false
        videoView.wantsLayer = true
        videoView.layer?.backgroundColor = NSColor.clear.cgColor
        videoView.isHidden = true
        petContainer.addSubview(videoView)

        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.wantsLayer = true
        imageView.layer?.contentsGravity = .resizeAspect
        imageView.layer?.shadowColor = NSColor.black.cgColor
        imageView.imageAlignment = .alignBottom
        imageView.layer?.magnificationFilter = .linear
        imageView.layer?.minificationFilter = .trilinear
        imageView.layer?.shadowOpacity = 0.08
        imageView.layer?.shadowRadius = 5
        imageView.layer?.shadowOffset = CGSize(width: 0, height: -2)
        petContainer.addSubview(imageView)

        defaultPixelPet.translatesAutoresizingMaskIntoConstraints = false
        petContainer.addSubview(defaultPixelPet)

        NSLayoutConstraint.activate([
            petContainer.centerXAnchor.constraint(equalTo: centerXAnchor),
            petContainer.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -CompanionVisualMetrics.petBottom),
            petContainer.widthAnchor.constraint(equalToConstant: CompanionVisualMetrics.petSize),
            petContainer.heightAnchor.constraint(equalToConstant: CompanionVisualMetrics.petSize),

            imageView.leadingAnchor.constraint(equalTo: petContainer.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: petContainer.trailingAnchor),
            imageView.topAnchor.constraint(equalTo: petContainer.topAnchor),
            imageView.bottomAnchor.constraint(equalTo: petContainer.bottomAnchor),

            videoView.leadingAnchor.constraint(equalTo: petContainer.leadingAnchor),
            videoView.trailingAnchor.constraint(equalTo: petContainer.trailingAnchor),
            videoView.topAnchor.constraint(equalTo: petContainer.topAnchor),
            videoView.bottomAnchor.constraint(equalTo: petContainer.bottomAnchor),

            defaultPixelPet.centerXAnchor.constraint(equalTo: petContainer.centerXAnchor),
            defaultPixelPet.centerYAnchor.constraint(equalTo: petContainer.centerYAnchor),
            defaultPixelPet.widthAnchor.constraint(equalTo: petContainer.widthAnchor),
            defaultPixelPet.heightAnchor.constraint(equalTo: petContainer.heightAnchor)
        ])

        hideBubble(animated: false)
    }

    private func styleActionButton(_ button: NSButton, background: NSColor, foreground: NSColor) {
        button.bezelStyle = .regularSquare
        button.isBordered = false
        button.controlSize = .regular
        button.font = .systemFont(ofSize: 12, weight: .medium)
        button.contentTintColor = foreground
        button.wantsLayer = true
        button.layer?.backgroundColor = background.cgColor
        button.layer?.cornerRadius = 7
        button.layer?.masksToBounds = true
        button.focusRingType = .none
    }

    override func layout() {
        super.layout()
        playerLayer?.frame = videoView.bounds
        let progressSize = progressStack.idealSize(maxWidth: min(368, bounds.width - 24))
        progressStack.frame = NSRect(x: (bounds.width - progressSize.width) / 2, y: CompanionVisualMetrics.bubbleAnchor,
                                    width: progressSize.width, height: progressSize.height)
        if let entry = vocabularyEntry {
            layoutVocabulary(entry)
            return
        }
        let hasControls = !skipButton.isHidden
        if !hasControls {
            layoutMessage()
            return
        }
        let reserved = sizingBody ?? bodyLabel.stringValue
        let maxWidth = min(352, bounds.width - 24)
        let titleWidth = (titleLabel.stringValue as NSString).size(withAttributes: [.font: titleLabel.font!]).width
        let lineWidth = reserved.components(separatedBy: "\n").map {
            ($0 as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 13)]).width
        }.max() ?? 0
        let width = lockedVocabularySize?.width ?? min(maxWidth, max(hasControls ? 320 : 190, min(max(titleWidth, lineWidth) + 48, maxWidth)))
        let innerWidth = width - 48
        let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 14, weight: .semibold)]
        let measured = (reserved as NSString).boundingRect(with: NSSize(width: innerWidth, height: 2000), options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: attributes).height
        let bodyHeight = reserved.isEmpty ? 0 : min(max(30, ceil(measured) + 12), hasControls ? 140 : 112)
        let headerHeight: CGFloat = kickerLabel.isHidden ? 46 : 70
        let controlsHeight: CGFloat = hasControls ? 106 : 0
        let height = lockedVocabularySize?.height ?? min(bounds.height - 175, headerHeight + bodyHeight + controlsHeight + 48)
        bubbleView.frame = NSRect(x: (bounds.width - width) / 2, y: CompanionVisualMetrics.bubbleAnchor, width: width, height: height)
        var top = height - 24
        if !kickerLabel.isHidden { kickerLabel.frame = NSRect(x: 24, y: top - 18, width: innerWidth, height: 18); top -= 25 }
        titleLabel.frame = NSRect(x: 24, y: top - 37, width: innerWidth, height: 37); top -= 46
        let bottom: CGFloat = hasControls ? 142 : 38
        let availableBody = max(0, top - bottom)
        bodyScroll.frame = NSRect(x: 24, y: bottom, width: innerWidth, height: availableBody)
        bodyScroll.isHidden = bodyLabel.isHidden
        let actualHeight = max(availableBody, ceil(bodyLabel.attributedStringValue.boundingRect(
            with: NSSize(width: innerWidth, height: 4000), options: [.usesLineFragmentOrigin, .usesFontLeading]).height) + 8)
        bodyLabel.frame = NSRect(x: 0, y: 0, width: innerWidth, height: actualHeight)
        bodyDocument.frame = bodyLabel.frame
        if resetBodyScroll { bodyScroll.contentView.scroll(to: .zero); resetBodyScroll = false }
        footerLabel.frame = NSRect(x: 24, y: 112, width: innerWidth, height: 28)
        let row = revealButton.isHidden ? [unknownButton, hardButton, knownButton].filter { !$0.isHidden } : [revealButton, skipButton]
        if !row.isEmpty {
            let gap: CGFloat = 8
            let controlWidth = (innerWidth - gap * CGFloat(row.count - 1)) / CGFloat(row.count)
            for (index, control) in row.enumerated() {
                control.frame = NSRect(x: 24 + CGFloat(index) * (controlWidth + gap), y: 76, width: controlWidth, height: 30)
            }
        }
        if revealButton.isHidden { skipButton.frame = NSRect(x: (width - 112) / 2, y: 40, width: 112, height: 28) }
        bubbleView.needsDisplay = true
    }

    private func layoutMessage() {
        let compact = messagePresentation == .compact
        let maxWidth = min(compact ? 272 : 352, bounds.width - 24)
        let font = titleLabel.font ?? .systemFont(ofSize: 14, weight: .semibold)
        let titleWidth = max(titleLabel.intrinsicContentSize.width,
            (titleLabel.attributedStringValue).size().width) + 8
        let bodyWidth = bodyLabel.attributedStringValue.size().width + 8
        let width = min(maxWidth, max(compact ? 96 : 220, max(titleWidth, bodyWidth) + 40))
        let innerWidth = width - 40
        let titleHeight = min(44, max(22, ceil(titleLabel.cell?.cellSize(forBounds:
            NSRect(x: 0, y: 0, width: innerWidth, height: 1000)).height ?? font.boundingRectForFont.height) + 2))
        titleLabel.toolTip = titleLabel.stringValue
        let fullBodyHeight = ceil(bodyLabel.cell?.cellSize(forBounds:
            NSRect(x: 0, y: 0, width: innerWidth, height: 10000)).height ?? 0) + 4
        let bodyHeight = bodyLabel.isHidden ? 0 : min(86, fullBodyHeight)
        let kickerHeight: CGFloat = kickerLabel.isHidden ? 0 : 18
        let footerHeight: CGFloat = footerLabel.isHidden ? 0 : 20
        let desired = 40 + kickerHeight + titleHeight + (bodyHeight > 0 ? bodyHeight + 6 : 0) + footerHeight
        let height = min(desired, max(64, bounds.height - CompanionVisualMetrics.bubbleAnchor - 12))
        bubbleView.frame = NSRect(x: (bounds.width - width) / 2, y: CompanionVisualMetrics.bubbleAnchor, width: width, height: height)
        var top = height - 20
        if !kickerLabel.isHidden {
            kickerLabel.frame = NSRect(x: 20, y: top - 14, width: innerWidth, height: 14)
            top -= kickerHeight
        }
        titleLabel.frame = NSRect(x: 20, y: top - titleHeight, width: innerWidth, height: titleHeight)
        top -= titleHeight
        let bottom: CGFloat = 20 + footerHeight
        bodyScroll.frame = NSRect(x: 20, y: bottom, width: innerWidth, height: max(0, top - 6 - bottom))
        bodyScroll.isHidden = bodyLabel.isHidden
        bodyLabel.frame = NSRect(x: 0, y: 0, width: innerWidth, height: max(bodyScroll.bounds.height, fullBodyHeight))
        bodyDocument.frame = bodyLabel.frame
        if resetBodyScroll { bodyScroll.contentView.scroll(to: .zero); resetBodyScroll = false }
        footerLabel.frame = NSRect(x: 20, y: 18, width: innerWidth, height: 16)
        footerLabel.font = .systemFont(ofSize: 10.5)
    }

    private func renderVocabularyText() {
        guard let entry = vocabularyEntry else { return }
        bodyLabel.isHidden = true
        vocabularyTextView.isHidden = false
        vocabularyTextView.textStorage?.setAttributedString(VocabularyCardTypography.content(entry: entry,
            revealed: vocabularyRevealed, theme: visualTheme, translationStatus: translationStatus,
            availableWidth: (lockedVocabularySize?.width ?? min(CompanionVisualMetrics.wordMaxWidth, max(280, bounds.width - 24))) - 48))
        let hint = entry.hint?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        contextPanel.isHidden = !vocabularyRevealed || hint.isEmpty
        contextPanel.layer?.backgroundColor = (visualTheme == .comic ? NSColor(calibratedWhite: 0.96, alpha: 1) : visualTheme.washNSColor).cgColor
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .left
        paragraph.lineSpacing = 4
        paragraph.paragraphSpacing = 6
        let context = NSMutableAttributedString(string: "语境说明\n", attributes: [
            .font: NSFont.systemFont(ofSize: 11, weight: .semibold),
            .foregroundColor: NSColor(calibratedWhite: 0.45, alpha: 1), .paragraphStyle: paragraph
        ])
        context.append(NSAttributedString(string: hint, attributes: [
            .font: NSFont.systemFont(ofSize: 13), .foregroundColor: visualTheme.inkNSColor, .paragraphStyle: paragraph
        ]))
        contextTextView.textStorage?.setAttributedString(context)
    }

    private func layoutVocabulary(_ entry: DictionaryEntry) {
        let width = lockedVocabularySize?.width ?? min(CompanionVisualMetrics.wordMaxWidth, max(280, bounds.width - 24))
        let innerWidth = width - 48
        func measuredRichText(_ text: NSAttributedString, width: CGFloat? = nil) -> CGFloat {
            let storage = NSTextStorage(attributedString: text)
            let manager = NSLayoutManager()
            let container = NSTextContainer(containerSize: NSSize(width: width ?? innerWidth, height: .greatestFiniteMagnitude))
            container.lineFragmentPadding = 0
            storage.addLayoutManager(manager)
            manager.addTextContainer(container)
            manager.ensureLayout(for: container)
            return ceil(manager.usedRect(for: container).height) + 2
        }
        let textHeight = measuredRichText(vocabularyTextView.attributedString())
        let hasContext = vocabularyRevealed && !(entry.hint?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        let contextHeight = hasContext ? measuredRichText(contextTextView.attributedString(), width: innerWidth - 24) + 24 : 0
        let headerHeight: CGFloat = kickerLabel.isHidden ? 24 : 50
        let bottom: CGFloat = vocabularyRevealed ? 124 : 84
        let desired = headerHeight + bottom + textHeight + (hasContext ? contextHeight + 10 : 0)
        let minimum: CGFloat = vocabularyRevealed ? 244 : 176
        let height = lockedVocabularySize?.height ?? min(max(minimum, desired), max(minimum, bounds.height - CompanionVisualMetrics.bubbleAnchor - 12))
        bubbleView.frame = NSRect(x: (bounds.width - width) / 2, y: CompanionVisualMetrics.bubbleAnchor, width: width, height: height)
        kickerLabel.frame = NSRect(x: 24, y: height - 37, width: innerWidth, height: 17)
        kickerLabel.font = .systemFont(ofSize: 11, weight: .medium)
        bodyScroll.frame = NSRect(x: 24, y: bottom, width: innerWidth, height: max(0, height - headerHeight - bottom))
        bodyScroll.isHidden = false
        vocabularyTextView.frame = NSRect(x: 0, y: 0, width: innerWidth, height: textHeight)
        vocabularyTextView.textContainer?.containerSize = NSSize(width: innerWidth, height: .greatestFiniteMagnitude)
        contextPanel.frame = NSRect(x: 0, y: textHeight + 10, width: innerWidth, height: contextHeight)
        contextTextView.frame = NSRect(x: 12, y: 12, width: innerWidth - 24, height: max(0, contextHeight - 24))
        contextTextView.textContainer?.containerSize = NSSize(width: innerWidth - 24, height: .greatestFiniteMagnitude)
        let documentHeight = textHeight + (contextPanel.isHidden ? 0 : contextHeight + 10)
        bodyDocument.frame = NSRect(x: 0, y: 0, width: innerWidth, height: max(bodyScroll.bounds.height, documentHeight))
        if resetBodyScroll { bodyScroll.contentView.scroll(to: .zero); resetBodyScroll = false }
        footerLabel.frame = NSRect(x: 24, y: vocabularyRevealed ? 96 : 62, width: innerWidth, height: vocabularyRevealed ? 24 : 18)
        footerLabel.font = .systemFont(ofSize: 10, weight: .regular)
        let row = revealButton.isHidden ? [unknownButton, hardButton, knownButton] : [revealButton, skipButton]
        let gap: CGFloat = 8
        let controlWidth = floor((innerWidth - gap * CGFloat(row.count - 1)) / CGFloat(row.count))
        let rowWidth = controlWidth * CGFloat(row.count) + gap * CGFloat(row.count - 1)
        for (index, control) in row.enumerated() {
            control.frame = NSRect(x: (width - rowWidth) / 2 + CGFloat(index) * (controlWidth + gap), y: vocabularyRevealed ? 60 : 26, width: controlWidth, height: 30)
        }
        if revealButton.isHidden { skipButton.frame = NSRect(x: (width - 112) / 2, y: 28, width: 112, height: 24) }
        bubbleView.needsDisplay = true
    }

    private func setBodyText(_ text: String, alignment: NSTextAlignment, presentation: BubblePresentation) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 2
        paragraph.paragraphSpacing = 0
        paragraph.alignment = alignment
        bodyLabel.alignment = alignment
        bodyLabel.attributedStringValue = NSAttributedString(
            string: text,
            attributes: [
                .font: NSFont.systemFont(ofSize: 13, weight: .regular),
                .foregroundColor: visualTheme == .comic ? NSColor(calibratedWhite: 0.34, alpha: 1) : visualTheme.inkNSColor,
                .paragraphStyle: paragraph
            ]
        )
    }

    private func startFrameTimer() {
        guard frameTimer == nil else { return }
        frameTimer = Timer.scheduledTimer(withTimeInterval: frameTimerInterval, repeats: true) { [weak self] _ in
            self?.advanceAnimationFrame()
        }
        if let frameTimer {
            RunLoop.main.add(frameTimer, forMode: .common)
        }
    }

    private func advanceAnimationFrame() {
        guard !petContainer.isHidden, window?.isVisible != false else { return }
        if animationRenderer != nil {
            spriteFrameElapsed += frameTimerInterval
            guard spriteFrameElapsed >= spriteFrameInterval else { return }
            while spriteFrameElapsed >= spriteFrameInterval {
                spriteFrameElapsed -= spriteFrameInterval
                frameIndex += 1
            }
            renderCurrentFrame()
        } else if let frame = animatedRenderer?.nextFrame(deltaTime: frameTimerInterval) {
            withoutImplicitLayerAnimations {
                imageView.image = frame
                imageView.isHidden = false
                defaultPixelPet.isHidden = true
            }
        }
    }

    private func renderCurrentFrame() {
        guard let renderer = animationRenderer,
              let frame = renderer.desktopFrame(for: currentAction, frameIndex: frameIndex) ?? renderer.stillFrame() else {
            return
        }
        withoutImplicitLayerAnimations {
            imageView.image = frame
            imageView.isHidden = false
            defaultPixelPet.isHidden = true
        }
    }

    private func startBreathingAnimation() {
        petContainer.layer?.removeAnimation(forKey: "pet-action")
        petContainer.layer?.removeAnimation(forKey: "pet-breathing")
        guard usesProceduralActionAnimation else { return }
        let animation = CABasicAnimation(keyPath: "transform.scale")
        animation.fromValue = 0.995
        animation.toValue = 1.012
        animation.duration = 1.9
        animation.autoreverses = true
        animation.repeatCount = .infinity
        animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        petContainer.layer?.add(animation, forKey: "pet-breathing")
    }

    private func applyActionAnimation(_ action: CodexPetAction) {
        petContainer.layer?.removeAnimation(forKey: "pet-action")
        petContainer.layer?.removeAnimation(forKey: "pet-breathing")
        imageView.layer?.transform = CATransform3DIdentity

        if animationRenderer == nil, action == .runningLeft {
            imageView.layer?.transform = CATransform3DMakeScale(-1, 1, 1)
        }

        guard usesProceduralActionAnimation else { return }

        switch action {
        case .idle:
            startBreathingAnimation()
        case .waiting, .review:
            let animation = CABasicAnimation(keyPath: "transform.scale")
            animation.fromValue = action == .review ? 0.995 : 0.98
            animation.toValue = action == .review ? 1.018 : 1.01
            animation.duration = action == .review ? 1.8 : 3.0
            animation.autoreverses = true
            animation.repeatCount = .infinity
            animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            petContainer.layer?.add(animation, forKey: "pet-action")
        case .jumping:
            let animation = CAKeyframeAnimation(keyPath: "transform.translation.y")
            animation.values = [0, 14, 0]
            animation.keyTimes = [0, 0.5, 1]
            animation.duration = 0.9
            animation.repeatCount = 1
            animation.timingFunction = CAMediaTimingFunction(name: .easeOut)
            petContainer.layer?.add(animation, forKey: "pet-action")
        case .waving:
            let animation = CAKeyframeAnimation(keyPath: "transform.rotation.z")
            animation.values = [-0.055, 0.065, -0.045, 0.04, 0]
            animation.duration = 1.1
            animation.repeatCount = 1
            animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            petContainer.layer?.add(animation, forKey: "pet-action")
        case .failed:
            let animation = CAKeyframeAnimation(keyPath: "transform.translation.x")
            animation.values = [0, -5, 5, -3, 3, 0]
            animation.duration = 0.65
            animation.repeatCount = 2
            petContainer.layer?.add(animation, forKey: "pet-action")
        case .running, .runningRight, .runningLeft:
            let animation = CAKeyframeAnimation(keyPath: "transform.translation.y")
            animation.values = [0, 2, 0, 1, 0]
            animation.duration = 0.9
            animation.repeatCount = .infinity
            animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            petContainer.layer?.add(animation, forKey: "pet-action")
        }
    }

    private func clearVideo() {
        if let playerLayer {
            playerLayer.removeFromSuperlayer()
        }
        player?.pause()
        player = nil
        playerLayer = nil
        NotificationCenter.default.removeObserver(self, name: .AVPlayerItemDidPlayToEndTime, object: nil)
    }

    private func withoutImplicitLayerAnimations(_ updates: () -> Void) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        updates()
        CATransaction.commit()
    }

    @objc private func videoDidFinish(_ notification: Notification) {
        guard let item = notification.object as? AVPlayerItem else { return }
        DispatchQueue.main.async { [weak self, weak item] in
            guard let self, let item, self.player?.currentItem === item else { return }
            item.seek(to: .zero, completionHandler: nil)
            if !self.petContainer.isHidden, self.window?.isVisible != false { self.player?.play() }
        }
    }

    @objc private func knownTapped() {
        delegate?.markKnown()
    }

    @objc private func unknownTapped() {
        delegate?.markUnknown()
    }

    @objc private func hardTapped() { delegate?.markHard() }
    @objc private func revealTapped() { delegate?.revealVocabularyAnswer() }

    @objc private func skipTapped() {
        delegate?.skipWord()
    }

}


final class DefaultPixelPetView: NSView {
    override var isOpaque: Bool { false }

    override func draw(_ dirtyRect: NSRect) {
        let unit = min(bounds.width, bounds.height) / 11
        let origin = CGPoint(
            x: bounds.midX - unit * 5.5,
            y: bounds.midY - unit * 5.5
        )

        func rect(_ x: Int, _ y: Int, _ w: Int, _ h: Int, _ color: NSColor) {
            color.setFill()
            NSRect(
                x: origin.x + CGFloat(x) * unit,
                y: origin.y + CGFloat(y) * unit,
                width: CGFloat(w) * unit,
                height: CGFloat(h) * unit
            ).fill()
        }

        rect(2, 8, 2, 2, .systemMint)
        rect(7, 8, 2, 2, .systemMint)
        rect(1, 3, 9, 6, .systemMint)
        rect(2, 2, 7, 1, .systemTeal)
        rect(3, 6, 1, 1, .black.withAlphaComponent(0.82))
        rect(7, 6, 1, 1, .black.withAlphaComponent(0.82))
        rect(5, 4, 2, 1, .systemPink)
        rect(2, 1, 2, 1, .systemTeal)
        rect(7, 1, 2, 1, .systemTeal)
        rect(1, 4, 1, 2, .systemTeal)
        rect(9, 4, 1, 2, .systemTeal)
        rect(4, 7, 1, 1, .white.withAlphaComponent(0.9))
        rect(8, 7, 1, 1, .white.withAlphaComponent(0.9))
    }
}
