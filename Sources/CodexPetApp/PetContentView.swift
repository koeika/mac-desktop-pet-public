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
    private(set) var visualTheme: AppVisualTheme = .comic

    func applyTheme(_ theme: AppVisualTheme) {
        guard visualTheme != theme else { return }
        visualTheme = theme
        bubbleView.theme = theme
        titleLabel.textColor = theme.inkNSColor
        kickerLabel.textColor = theme == .storybook ? theme.accentNSColor : NSColor(calibratedWhite: 0.38, alpha: 1)
        let text = NSMutableAttributedString(attributedString: bodyLabel.attributedStringValue)
        text.addAttribute(.foregroundColor, value: theme.inkNSColor, range: NSRange(location: 0, length: text.length))
        bodyLabel.attributedStringValue = text
        styleActionButton(knownButton, background: theme.accentNSColor, foreground: .white)
        styleActionButton(revealButton, background: theme.accentNSColor, foreground: .white)
        let neutral = theme == .comic ? NSColor(calibratedWhite: 0.92, alpha: 1) : theme.washNSColor
        styleActionButton(unknownButton, background: neutral, foreground: theme.inkNSColor)
        styleActionButton(hardButton, background: theme == .comic ? neutral : NSColor(calibratedRed: 1, green: 0.90, blue: 0.85, alpha: 1), foreground: theme.inkNSColor)
        styleActionButton(skipButton, background: theme == .comic ? NSColor(calibratedWhite: 0.96, alpha: 1) : NSColor(calibratedRed: 0.93, green: 0.96, blue: 0.99, alpha: 1), foreground: .darkGray)
    }

    private let bubbleView = SpeechBubbleBackgroundView()
    private let kickerLabel = NSTextField(labelWithString: "")
    private let titleLabel = NSTextField(labelWithString: "")
    private let bodyLabel = NSTextField(wrappingLabelWithString: "")
    private let bodyScroll = NSScrollView()
    private let bodyDocument = PetTextDocument()
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
        !bubbleView.isHidden
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    var bubbleLayoutSnapshot: (bubble: NSRect, controls: [NSRect]) {
        (bubbleView.frame, [revealButton, unknownButton, hardButton, knownButton, skipButton]
            .filter { !$0.isHidden }.map(\.frame))
    }

    func showVocabularyCard(kicker: String, title: String, prompt: String, answer: String,
                            revealed: Bool, footer: String, known: String, unknown: String, hard: String) {
        let key = kicker + "|" + title
        let previousSize = vocabularyLayoutKey == key ? lockedVocabularySize : nil
        showMessage(kicker: kicker, title: title, body: revealed ? answer : prompt,
                    showActions: true, footer: footer, animated: false)
        vocabularyLayoutKey = key
        lockedVocabularySize = previousSize
        sizingBody = answer
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
        bubbleHideTimer?.invalidate()
        sizingBody = nil
        vocabularyLayoutKey = nil
        lockedVocabularySize = nil
        bubbleRevision += 1
        let cleanKicker = kicker.trimmingCharacters(in: .whitespacesAndNewlines)
        kickerLabel.stringValue = cleanKicker
        kickerLabel.isHidden = cleanKicker.isEmpty
        titleLabel.stringValue = title
        titleLabel.font = presentation == .compact
            ? .systemFont(ofSize: 22, weight: .black)
            : .systemFont(ofSize: 26, weight: .bold)
        setBodyText(body, alignment: bodyAlignment, presentation: presentation)
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

    func hideBubble(animated: Bool) {
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
            guard self?.bubbleRevision == revision else { return }
            self?.bubbleView.isHidden = true
            self?.bubbleView.alphaValue = 0
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
        player.play()
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
        dragStartPoint = window?.convertPoint(toScreen: event.locationInWindow)
        dragWindowOrigin = window?.frame.origin
        clickStartedOnPet = petContainer.frame.contains(event.locationInWindow)
        didDrag = false
    }

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
            didDrag = false
        }
        guard clickStartedOnPet,
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
        if petContainer.frame.contains(point) {
            return self
        }
        return nil
    }

    private func setup() {
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor

        bubbleView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(bubbleView)

        kickerLabel.font = .systemFont(ofSize: 14, weight: .heavy)
        kickerLabel.textColor = NSColor(calibratedWhite: 0.38, alpha: 1)
        kickerLabel.alignment = .center
        kickerLabel.lineBreakMode = .byTruncatingTail
        titleLabel.font = .systemFont(ofSize: 29, weight: .black)
        titleLabel.textColor = NSColor(calibratedWhite: 0.13, alpha: 1)
        titleLabel.alignment = .center
        titleLabel.lineBreakMode = .byTruncatingTail
        bodyLabel.maximumNumberOfLines = 0
        footerLabel.font = .monospacedSystemFont(ofSize: 16, weight: .bold)
        footerLabel.textColor = NSColor(calibratedWhite: 0.56, alpha: 1)
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
        styleActionButton(unknownButton, background: NSColor(calibratedWhite: 0.92, alpha: 1), foreground: .black)
        styleActionButton(skipButton, background: NSColor(calibratedWhite: 0.96, alpha: 1), foreground: .darkGray)
        styleActionButton(hardButton, background: NSColor(calibratedWhite: 0.92, alpha: 1), foreground: .black)
        styleActionButton(revealButton, background: NSColor(calibratedWhite: 0.08, alpha: 1), foreground: .white)

        bodyScroll.drawsBackground = false
        bodyScroll.hasVerticalScroller = true
        bodyScroll.autohidesScrollers = true
        bodyScroll.borderType = .noBorder
        bodyScroll.scrollerStyle = .overlay
        bodyDocument.addSubview(bodyLabel)
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
        imageView.layer?.shadowOpacity = 0.24
        imageView.layer?.shadowRadius = 18
        imageView.layer?.shadowOffset = CGSize(width: 0, height: -5)
        petContainer.addSubview(imageView)

        defaultPixelPet.translatesAutoresizingMaskIntoConstraints = false
        petContainer.addSubview(defaultPixelPet)

        NSLayoutConstraint.activate([
            petContainer.centerXAnchor.constraint(equalTo: centerXAnchor),
            petContainer.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -14),
            petContainer.widthAnchor.constraint(equalToConstant: 150),
            petContainer.heightAnchor.constraint(equalToConstant: 150),

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
            defaultPixelPet.widthAnchor.constraint(equalToConstant: 154),
            defaultPixelPet.heightAnchor.constraint(equalToConstant: 154)
        ])

        hideBubble(animated: false)
    }

    private func styleActionButton(_ button: NSButton, background: NSColor, foreground: NSColor) {
        button.bezelStyle = .regularSquare
        button.isBordered = false
        button.controlSize = .regular
        button.font = .systemFont(ofSize: 13, weight: .bold)
        button.contentTintColor = foreground
        button.wantsLayer = true
        button.layer?.backgroundColor = background.cgColor
        button.layer?.cornerRadius = 16
        button.layer?.masksToBounds = true
        button.focusRingType = .none
    }

    override func layout() {
        super.layout()
        playerLayer?.frame = videoView.bounds
        let hasControls = !skipButton.isHidden
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
        bubbleView.frame = NSRect(x: (bounds.width - width) / 2, y: 164, width: width, height: height)
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
              let frame = renderer.frame(for: currentAction, frameIndex: frameIndex) ?? renderer.stillFrame() else {
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
        animation.fromValue = 0.985
        animation.toValue = 1.025
        animation.duration = 1.7
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
        item.seek(to: .zero, completionHandler: nil)
        player?.play()
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

final class SpeechBubbleBackgroundView: NSView {
    var theme: AppVisualTheme = .comic {
        didSet { needsDisplay = true }
    }
    private enum PixelBubbleStyle: CaseIterable {
        case angular
        case rounded
        case pill
        case lavender
    }

    private var style: PixelBubbleStyle = .angular

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    override var isOpaque: Bool { false }

    func randomizeStyle() {
        style = .rounded
        needsDisplay = true
    }

    private func setup() {
        wantsLayer = true
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOpacity = 0.05
        layer?.shadowRadius = 3
        layer?.shadowOffset = CGSize(width: 0, height: -2)
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.saveGState()
        context.setShouldAntialias(true)
        defer { context.restoreGState() }

        let rect = bounds.insetBy(dx: 6, dy: 18).offsetBy(dx: 0, dy: 10)
        switch style {
        case .angular:
            drawBubble(path: pixelRectPath(in: rect, step: 8), rect: rect, fill: .white, tailWidth: 38, tailOffset: 0)
        case .rounded:
            let path = theme == .storybook ? storybookPath(in: rect) : NSBezierPath(roundedRect: rect, xRadius: 14, yRadius: 14)
            drawBubble(path: path, rect: rect, fill: .white, tailWidth: 24, tailOffset: 0)
        case .pill:
            drawBubble(path: NSBezierPath(roundedRect: rect, xRadius: min(rect.height * 0.42, 44), yRadius: min(rect.height * 0.42, 44)), rect: rect, fill: .white, tailWidth: 36, tailOffset: -rect.width * 0.24)
        case .lavender:
            drawBubble(
                path: pixelRoundedPath(in: rect, step: 12),
                rect: rect,
                fill: NSColor(calibratedRed: 0.78, green: 0.82, blue: 1.0, alpha: 0.98),
                tailWidth: 38,
                tailOffset: rect.width * 0.12
            )
        }
    }

    private var strokeColor: NSColor {
        theme == .comic ? NSColor(calibratedWhite: 0.06, alpha: 0.95) : theme.accentNSColor
    }

    private func drawBubble(path: NSBezierPath, rect: NSRect, fill: NSColor, tailWidth: CGFloat, tailOffset: CGFloat) {
        let tail = bottomTail(rect: rect, width: tailWidth, offset: tailOffset)

        fill.setFill()
        path.fill()
        tail.fill()

        strokeColor.setStroke()
        path.lineWidth = theme == .comic ? 2 : 1.5
        path.stroke()

        fill.setFill()
        tail.fill()
        let tailStroke = bottomTailStroke(rect: rect, width: tailWidth, offset: tailOffset)
        strokeColor.setStroke()
        tailStroke.lineWidth = theme == .comic ? 2 : 1.5
        tailStroke.stroke()
    }

    private func storybookPath(in rect: NSRect) -> NSBezierPath {
        let path = NSBezierPath()
        let r: CGFloat = 17
        path.move(to: NSPoint(x: rect.minX + r, y: rect.minY))
        path.curve(to: NSPoint(x: rect.maxX - r, y: rect.minY + 0.5),
                   controlPoint1: NSPoint(x: rect.midX - 35, y: rect.minY - 0.8),
                   controlPoint2: NSPoint(x: rect.midX + 35, y: rect.minY + 1))
        path.curve(to: NSPoint(x: rect.maxX, y: rect.minY + r),
                   controlPoint1: NSPoint(x: rect.maxX - 5, y: rect.minY), controlPoint2: NSPoint(x: rect.maxX, y: rect.minY + 5))
        path.line(to: NSPoint(x: rect.maxX - 0.5, y: rect.maxY - r))
        path.curve(to: NSPoint(x: rect.maxX - r, y: rect.maxY),
                   controlPoint1: NSPoint(x: rect.maxX, y: rect.maxY - 5), controlPoint2: NSPoint(x: rect.maxX - 5, y: rect.maxY))
        path.curve(to: NSPoint(x: rect.minX + r, y: rect.maxY - 0.5),
                   controlPoint1: NSPoint(x: rect.midX + 35, y: rect.maxY + 0.8),
                   controlPoint2: NSPoint(x: rect.midX - 35, y: rect.maxY - 1))
        path.curve(to: NSPoint(x: rect.minX, y: rect.maxY - r),
                   controlPoint1: NSPoint(x: rect.minX + 5, y: rect.maxY), controlPoint2: NSPoint(x: rect.minX, y: rect.maxY - 5))
        path.line(to: NSPoint(x: rect.minX + 0.5, y: rect.minY + r))
        path.curve(to: NSPoint(x: rect.minX + r, y: rect.minY),
                   controlPoint1: NSPoint(x: rect.minX, y: rect.minY + 5), controlPoint2: NSPoint(x: rect.minX + 5, y: rect.minY))
        path.close()
        return path
    }

    private func drawPixelShadow(path: NSBezierPath, tail: NSBezierPath) {
        let shadowTransform = AffineTransform(translationByX: 5, byY: -5)
        guard let shadowPath = path.copy() as? NSBezierPath,
              let shadowTail = tail.copy() as? NSBezierPath else { return }
        shadowPath.transform(using: shadowTransform)
        shadowTail.transform(using: shadowTransform)
        NSColor.black.withAlphaComponent(0.18).setFill()
        shadowPath.fill()
        shadowTail.fill()
    }

    private func pixelRectPath(in rect: NSRect, step: CGFloat) -> NSBezierPath {
        let path = NSBezierPath()
        path.move(to: NSPoint(x: rect.minX + step, y: rect.minY))
        path.line(to: NSPoint(x: rect.maxX - step, y: rect.minY))
        path.line(to: NSPoint(x: rect.maxX, y: rect.minY + step))
        path.line(to: NSPoint(x: rect.maxX, y: rect.maxY - step))
        path.line(to: NSPoint(x: rect.maxX - step, y: rect.maxY))
        path.line(to: NSPoint(x: rect.minX + step, y: rect.maxY))
        path.line(to: NSPoint(x: rect.minX, y: rect.maxY - step))
        path.line(to: NSPoint(x: rect.minX, y: rect.minY + step))
        path.close()
        return path
    }

    private func pixelRoundedPath(in rect: NSRect, step: CGFloat) -> NSBezierPath {
        let path = NSBezierPath()
        path.move(to: NSPoint(x: rect.minX + step * 2, y: rect.minY))
        path.line(to: NSPoint(x: rect.maxX - step * 2, y: rect.minY))
        path.line(to: NSPoint(x: rect.maxX - step, y: rect.minY + step))
        path.line(to: NSPoint(x: rect.maxX, y: rect.minY + step * 2))
        path.line(to: NSPoint(x: rect.maxX, y: rect.maxY - step * 2))
        path.line(to: NSPoint(x: rect.maxX - step, y: rect.maxY - step))
        path.line(to: NSPoint(x: rect.maxX - step * 2, y: rect.maxY))
        path.line(to: NSPoint(x: rect.minX + step * 2, y: rect.maxY))
        path.line(to: NSPoint(x: rect.minX + step, y: rect.maxY - step))
        path.line(to: NSPoint(x: rect.minX, y: rect.maxY - step * 2))
        path.line(to: NSPoint(x: rect.minX, y: rect.minY + step * 2))
        path.line(to: NSPoint(x: rect.minX + step, y: rect.minY + step))
        path.close()
        return path
    }

    private func bottomTail(rect: NSRect, width: CGFloat, offset: CGFloat) -> NSBezierPath {
        let centerX = min(max(rect.midX + offset, rect.minX + width), rect.maxX - width)
        let path = NSBezierPath()
        path.move(to: NSPoint(x: centerX - width / 2, y: rect.minY + 1))
        path.line(to: NSPoint(x: centerX, y: bounds.minY + 4))
        path.line(to: NSPoint(x: centerX + width / 2, y: rect.minY + 1))
        path.close()
        return path
    }

    private func bottomTailStroke(rect: NSRect, width: CGFloat, offset: CGFloat) -> NSBezierPath {
        let centerX = min(max(rect.midX + offset, rect.minX + width), rect.maxX - width)
        let path = NSBezierPath()
        path.move(to: NSPoint(x: centerX - width / 2, y: rect.minY + 1))
        path.line(to: NSPoint(x: centerX, y: bounds.minY + 4))
        path.line(to: NSPoint(x: centerX + width / 2, y: rect.minY + 1))
        return path
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
