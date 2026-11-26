import AppKit
import CodexPetCore

final class CompanionProgressStackView: NSView {
    struct Identity: Equatable {
        let source: String
        let threadId: String?
    }

    struct RowSnapshot {
        let id: String
        let identity: Identity
        let receivedAt: Date
        let expiresAt: Date
        let frame: NSRect
        let titleFrame: NSRect
        let subtitleFrame: NSRect
        let title: String
        let subtitle: String
        let accessibilityLabel: String
        let theme: AppVisualTheme
    }

    struct Snapshot {
        let rows: [RowSnapshot]
        let priorityDeadline: Date?
        let scheduledExpiry: Date?
        var eventIDs: [String] { rows.map(\.id) }
        var identities: [Identity] { rows.map(\.identity) }
        var rowFrames: [NSRect] { rows.map(\.frame) }
    }

    private struct Entry {
        let event: ProgressEvent
        let receivedAt: Date
        let expiresAt: Date
        var identity: Identity { Identity(source: event.source, threadId: event.threadId) }
    }

    var theme: AppVisualTheme = .comic {
        didSet { refreshRows() }
    }
    var onChange: (() -> Void)?
    var hasVisibleEvents: Bool { !entries.isEmpty }
    var priorityDeadline: Date? { entries.map(\.expiresAt).max() }

    private var entries: [Entry] = []
    private var rows: [CompanionProgressRowView] = []
    private var expiryTimer: Timer?
    private var scheduledExpiry: Date?
    private static let rowHeight: CGFloat = 72
    private static let maximumWidth: CGFloat = 352

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setAccessibilityElement(false)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setAccessibilityElement(false)
    }

    deinit { expiryTimer?.invalidate() }

    // This informational overlay leaves the parent's drag and click gestures intact.
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func receive(_ event: ProgressEvent, now: Date = Date()) {
        let identity = Identity(source: event.source, threadId: event.threadId)
        entries.removeAll { $0.expiresAt <= now || $0.identity == identity }
        let duration: TimeInterval = event.status == .done || event.progress == 100 ? 12 : 8
        entries.insert(Entry(event: event, receivedAt: now, expiresAt: now.addingTimeInterval(duration)), at: 0)
        if entries.count > 3 { entries.removeLast(entries.count - 3) }
        didChange()
    }

    func clear() {
        let changed = !entries.isEmpty
        entries.removeAll()
        refreshRows()
        scheduleExpiry()
        if changed { onChange?() }
    }

    func expire(now: Date = Date()) {
        let count = entries.count
        entries.removeAll { $0.expiresAt <= now }
        if entries.count != count {
            didChange()
        } else {
            scheduleExpiry()
        }
    }

    func idealSize(maxWidth: CGFloat) -> NSSize {
        let width = maxWidth.isNaN ? 0 : max(0, min(Self.maximumWidth, maxWidth))
        return NSSize(width: width, height: CGFloat(entries.count) * Self.rowHeight)
    }

    override func layout() {
        super.layout()
        let width = idealSize(maxWidth: bounds.width).width
        for (index, row) in rows.enumerated() {
            row.frame = NSRect(x: bounds.minX + (bounds.width - width) / 2,
                y: bounds.maxY - CGFloat(index + 1) * Self.rowHeight,
                width: width, height: Self.rowHeight)
            row.isHidden = width < 16
        }
    }

    var snapshot: Snapshot {
        layoutSubtreeIfNeeded()
        let snapshots = zip(entries, rows).map { entry, row in
            RowSnapshot(id: entry.event.id, identity: entry.identity,
                receivedAt: entry.receivedAt, expiresAt: entry.expiresAt, frame: row.frame,
                titleFrame: row.convert(row.titleLabel.frame, to: self),
                subtitleFrame: row.convert(row.subtitleLabel.frame, to: self),
                title: row.titleLabel.stringValue, subtitle: row.subtitleLabel.stringValue,
                accessibilityLabel: row.taskAccessibilityLabel, theme: row.theme)
        }
        return Snapshot(rows: snapshots, priorityDeadline: priorityDeadline, scheduledExpiry: scheduledExpiry)
    }

    private func didChange() {
        refreshRows()
        scheduleExpiry()
        onChange?()
    }

    private func refreshRows() {
        while rows.count > entries.count { rows.removeLast().removeFromSuperview() }
        while rows.count < entries.count {
            let row = CompanionProgressRowView(frame: .zero)
            rows.append(row)
            addSubview(row)
        }
        for (entry, row) in zip(entries, rows) { row.configure(event: entry.event, theme: theme) }
        needsLayout = true
    }

    private func scheduleExpiry() {
        expiryTimer?.invalidate()
        expiryTimer = nil
        scheduledExpiry = entries.map(\.expiresAt).min()
        guard let deadline = scheduledExpiry else { return }
        // Wake only for the earliest live row; common mode also covers native dragging.
        let timer = Timer(fire: deadline, interval: 0, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.expire() }
        }
        expiryTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }
}

private final class CompanionProgressRowView: CompanionSurfaceView {
    let titleLabel = NSTextField(labelWithString: "")
    let subtitleLabel = NSTextField(labelWithString: "")
    private let statusImage = NSImageView()
    private let percentageLabel = NSTextField(labelWithString: "")
    private(set) var taskAccessibilityLabel = ""

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configureLabels()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureLabels()
    }

    private func configureLabels() {
        style = .notification
        titleLabel.font = .systemFont(ofSize: 12.5, weight: .semibold)
        subtitleLabel.font = .systemFont(ofSize: 11.5)
        percentageLabel.font = .monospacedDigitSystemFont(ofSize: 10.5, weight: .medium)
        percentageLabel.alignment = .right
        for label in [titleLabel, subtitleLabel, percentageLabel] {
            label.maximumNumberOfLines = 1
            label.lineBreakMode = .byTruncatingTail
            label.cell?.wraps = false
            label.cell?.isScrollable = false
            label.isSelectable = false
            label.setAccessibilityElement(false)
            addSubview(label)
        }
        statusImage.imageScaling = .scaleProportionallyDown
        statusImage.setAccessibilityElement(false)
        addSubview(statusImage)
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
    }

    func configure(event: ProgressEvent, theme: AppVisualTheme) {
        self.theme = theme
        let source = singleLine(event.source, fallback: "Task")
        titleLabel.stringValue = singleLine(event.stage, fallback: event.status.rawValue.capitalized)
        let message = singleLine(event.message, fallback: "")
        subtitleLabel.stringValue = message.isEmpty ? source : "\(source) · \(message)"
        titleLabel.toolTip = event.stage.isEmpty ? titleLabel.stringValue : event.stage
        subtitleLabel.toolTip = message.isEmpty ? source : "\(event.source) · \(event.message)"
        percentageLabel.stringValue = event.progress.map { "\(max(0, min(100, $0)))%" } ?? ""
        titleLabel.textColor = theme.inkNSColor
        subtitleLabel.textColor = theme.inkNSColor.withAlphaComponent(0.64)
        percentageLabel.textColor = theme.accentNSColor
        let symbol: String
        switch event.status {
        case .running: symbol = "arrow.clockwise"
        case .review: symbol = "eye"
        case .done: symbol = "checkmark.circle"
        case .failed: symbol = "exclamationmark.circle"
        case .waiting: symbol = "clock"
        case .message: symbol = "text.bubble"
        }
        statusImage.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
            ?? NSImage(systemSymbolName: "arrow.clockwise", accessibilityDescription: nil)
        statusImage.contentTintColor = event.status == .failed ? .systemRed : theme.accentNSColor
        let task = event.threadId.map { "\(source), task \($0)" } ?? source
        taskAccessibilityLabel = "\(task), \(titleLabel.stringValue), \(message), \(event.status.rawValue)"
        if !percentageLabel.stringValue.isEmpty { taskAccessibilityLabel += ", \(percentageLabel.stringValue)" }
        setAccessibilityLabel(taskAccessibilityLabel)
        toolTip = taskAccessibilityLabel
        needsLayout = true
    }

    override func layout() {
        super.layout()
        let showSymbol = bounds.width >= 160
        let showPercentage = bounds.width >= 200 && !percentageLabel.stringValue.isEmpty
        let left: CGFloat = showSymbol ? 42 : 22
        let right = max(left, bounds.width - 22)
        statusImage.isHidden = !showSymbol
        statusImage.frame = NSRect(x: 22, y: 40, width: 12, height: 12)
        percentageLabel.isHidden = !showPercentage
        percentageLabel.frame = NSRect(x: max(left, right - 36), y: 37, width: min(36, max(0, right - left)), height: 17)
        titleLabel.frame = NSRect(x: min(left, bounds.width), y: 37,
            width: max(0, right - left - (showPercentage ? 44 : 0)), height: 17)
        subtitleLabel.frame = NSRect(x: min(left, bounds.width), y: 19,
            width: max(0, right - left), height: 16)
        titleLabel.isHidden = titleLabel.frame.width == 0
        subtitleLabel.isHidden = subtitleLabel.frame.width == 0
    }

    private func singleLine(_ text: String, fallback: String) -> String {
        let line = text.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
        return line.isEmpty ? fallback : line
    }
}
