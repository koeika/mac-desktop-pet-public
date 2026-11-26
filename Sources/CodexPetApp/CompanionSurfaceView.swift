import AppKit

enum CompanionVisualMetrics {
    static let petSize: CGFloat = 128
    static let petBottom: CGFloat = 14
    static let bubbleAnchor: CGFloat = petSize + petBottom + 4
    static let wordMaxWidth: CGFloat = 384
    static let contentInset: CGFloat = 24
}

class CompanionSurfaceView: NSView {
    enum Style { case notification, feedback, vocabulary }
    var style: Style = .vocabulary { didSet { needsLayout = true } }
    var theme: AppVisualTheme = .comic { didSet { needsLayout = true } }
    private let material = NSVisualEffectView()
    private let tint = NSView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configure()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configure()
    }

    override var isOpaque: Bool { false }

    private func configure() {
        wantsLayer = true
        appearance = NSAppearance(named: .aqua)
        material.material = .popover
        material.blendingMode = .behindWindow
        material.state = .active
        material.wantsLayer = true
        tint.wantsLayer = true
        addSubview(material)
        addSubview(tint)
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOpacity = 0.10
        layer?.shadowRadius = 14
        layer?.shadowOffset = NSSize(width: 0, height: -4)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(accessibilityChanged),
            name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil)
    }

    @objc private func accessibilityChanged() { needsLayout = true }

    deinit { NSWorkspace.shared.notificationCenter.removeObserver(self) }

    override func layout() {
        super.layout()
        let rect = bounds.insetBy(dx: 8, dy: 8)
        let radius: CGFloat = style == .vocabulary ? 14 : min(26, rect.height / 2)
        material.frame = rect
        tint.frame = rect
        material.layer?.cornerRadius = radius
        material.layer?.masksToBounds = true
        let reduceTransparency = NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
        material.isHidden = reduceTransparency
        tint.layer?.cornerRadius = radius
        tint.layer?.backgroundColor = NSColor.white.withAlphaComponent(reduceTransparency ? 1 : style == .vocabulary ? 0.90 : 0.75).cgColor
        let edge = theme == .comic ? NSColor.black.withAlphaComponent(0.07) : theme.accentNSColor.withAlphaComponent(0.10)
        tint.layer?.borderColor = edge.cgColor
        tint.layer?.borderWidth = 0.7
        layer?.shadowPath = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
    }
}

final class SpeechBubbleBackgroundView: CompanionSurfaceView {
    func randomizeStyle() { needsLayout = true }
}
