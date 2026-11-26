import AppKit
import CodexPetCore

enum CompanionProgressRegression {
    private struct Failure: Error, CustomStringConvertible {
        let description: String
    }

    @MainActor static func run() throws {
        func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
            guard condition() else { throw Failure(description: "progress-stack: \(message)") }
        }

        let now = Date(timeIntervalSince1970: 2_000_000_000)
        let view = CompanionProgressStackView(frame: NSRect(x: 0, y: 0, width: 352, height: 216))
        defer { view.clear() }
        var changes = 0
        view.onChange = { changes += 1 }
        try expect(!view.hasVisibleEvents && view.priorityDeadline == nil, "initial state must be empty")
        try expect(view.idealSize(maxWidth: 600) == NSSize(width: 352, height: 0), "empty size")

        let first = ProgressEvent(id: "first", source: "codex", stage: "Reading", message: "Inspect sources",
            progress: 10, threadId: "shared", timestamp: now.addingTimeInterval(-86_400))
        let original = try JSONFileStore.encoder.encode(first)
        view.receive(first, now: now)
        try expect(view.snapshot.rows[0].expiresAt == now.addingTimeInterval(8), "TTL must use receipt, not event timestamp")
        view.receive(ProgressEvent(id: "other-source", source: "claude", stage: "Review", message: "Check diff",
            status: .review, threadId: "shared"), now: now.addingTimeInterval(1))
        try expect(view.snapshot.identities.count == 2, "same thread across sources must remain distinct")
        let update = ProgressEvent(id: "replacement", source: "codex", stage: "Building", message: "Compile",
            progress: 60, threadId: "shared", timestamp: now.addingTimeInterval(86_400))
        view.receive(update, now: now.addingTimeInterval(2))
        try expect(view.snapshot.eventIDs == ["replacement", "other-source"], "replace must promote to latest without duplication")
        try expect(view.snapshot.rows[0].expiresAt == now.addingTimeInterval(10), "replacement must renew receipt TTL")
        view.receive(ProgressEvent(id: "nil-thread", source: "codex", stage: "Task", message: ""), now: now.addingTimeInterval(3))
        view.receive(ProgressEvent(id: "nil-replacement", source: "codex", stage: "Task", message: "Updated"), now: now.addingTimeInterval(4))
        try expect(view.snapshot.eventIDs == ["nil-replacement", "replacement", "other-source"], "source-only identity must replace separately from named threads")
        view.receive(ProgressEvent(id: "fourth", source: "tool", stage: "Done", message: "Complete", status: .done), now: now.addingTimeInterval(5))
        try expect(view.snapshot.eventIDs == ["fourth", "nil-replacement", "replacement"], "fourth task must evict oldest")
        try expect(view.priorityDeadline == now.addingTimeInterval(17), "priority deadline must be maximum expiry")
        try expect(view.snapshot.scheduledExpiry == now.addingTimeInterval(10), "timer must target earliest expiry")
        let beforeNoOp = changes
        view.expire(now: now.addingTimeInterval(9.99))
        try expect(changes == beforeNoOp, "no-op expiry must not notify")
        view.expire(now: now.addingTimeInterval(10))
        try expect(view.snapshot.eventIDs == ["fourth", "nil-replacement"], "expiry must remove only elapsed rows at the exact boundary")
        view.expire(now: now.addingTimeInterval(12))
        try expect(view.snapshot.eventIDs == ["fourth"], "independent running expiry")
        view.expire(now: now.addingTimeInterval(17))
        try expect(!view.hasVisibleEvents && view.snapshot.scheduledExpiry == nil && view.priorityDeadline == nil, "expiry must stop idle timer")

        for status in AgentStatus.allCases {
            view.receive(ProgressEvent(source: "status", stage: "", message: "", status: status), now: now)
            let duration: TimeInterval = status == .done ? 12 : 8
            try expect(view.priorityDeadline == now.addingTimeInterval(duration), "status TTL: \(status)")
            view.clear()
        }
        view.receive(ProgressEvent(source: "percent", stage: "Upload", message: "", progress: 100), now: now)
        try expect(view.priorityDeadline == now.addingTimeInterval(12), "100 percent must keep completed TTL even with running status")
        view.clear()
        let afterClear = changes
        view.clear()
        try expect(changes == afterClear && view.snapshot.rows.isEmpty, "clear must be idempotent")

        view.receive(ProgressEvent(id: "thread-a", source: "codex", stage: "A", message: "", threadId: "a"), now: now)
        view.receive(ProgressEvent(id: "thread-b", source: "codex", stage: "B", message: "", threadId: "b"), now: now)
        view.receive(ProgressEvent(id: "source-only", source: "codex", stage: "Source", message: ""), now: now)
        try expect(view.snapshot.eventIDs == ["source-only", "thread-b", "thread-a"], "one source may have multiple independent tasks")
        view.receive(ProgressEvent(id: "after-expiry", source: "tool", stage: "New", message: ""), now: now.addingTimeInterval(8))
        try expect(view.snapshot.eventIDs == ["after-expiry"], "receive must discard expired rows before applying the limit")
        view.clear()

        // Backdate receipt to exercise the real one-shot callback without an eight-second wait.
        view.receive(ProgressEvent(source: "timer", stage: "Expiring", message: ""), now: Date().addingTimeInterval(-7.98))
        let timerDeadline = Date().addingTimeInterval(3)
        while view.hasVisibleEvents && Date() < timerDeadline {
            RunLoop.main.run(mode: .default, before: min(timerDeadline, Date().addingTimeInterval(0.02)))
        }
        try expect(!view.hasVisibleEvents && view.snapshot.scheduledExpiry == nil, "common-runloop timer must expire and stop itself")

        let longTitle = String(repeating: "Long task title ", count: 40)
        let longMessage = String(repeating: "Full details remain available in the tooltip. ", count: 40)
        let fixtures = [
            ProgressEvent(id: "long", source: "codex", stage: longTitle, message: longMessage, progress: 75, threadId: "task-long"),
            ProgressEvent(id: "empty", source: "", stage: "", message: " \n\t ", status: .waiting),
            ProgressEvent(id: "complete", source: "tool", stage: "Ready", message: "All checks complete", progress: 100, status: .done)
        ]
        let encodedFixtures = try JSONFileStore.encoder.encode(fixtures)
        for theme in AppVisualTheme.allCases {
            for width: CGFloat in [96, 160, 240, 352, 500] {
                view.clear()
                view.theme = theme
                for event in fixtures { view.receive(event, now: now) }
                let size = view.idealSize(maxWidth: width)
                view.frame = NSRect(origin: .zero, size: size)
                let snapshot = view.snapshot
                try expect(size.width <= width && size.width <= 352 && size.height == 216, "bounded stack dimensions")
                try expect(snapshot.eventIDs == ["complete", "empty", "long"], "latest receipt first")
                for (index, row) in snapshot.rows.enumerated() {
                    try expect(row.frame.height == 72 && view.bounds.contains(row.frame), "row must fit stack")
                    try expect(row.frame.contains(row.titleFrame) && row.frame.contains(row.subtitleFrame), "labels must fit at small widths")
                    try expect(row.titleFrame.minY >= row.subtitleFrame.maxY, "fixed label lines must not overlap")
                    try expect(!row.title.isEmpty && !row.subtitle.isEmpty && row.theme == theme, "empty text fallback and theme propagation")
                    try expect(row.accessibilityLabel.contains(row.identity.source), "accessibility must identify source")
                    if index > 0 {
                        try expect(row.frame.maxY <= snapshot.rows[index - 1].frame.minY, "visible rows must never overlap")
                    }
                }
                try expect(snapshot.rows[2].accessibilityLabel.contains("task-long"), "accessibility must identify thread")
                let labels = view.subviews.flatMap(\.subviews).compactMap { $0 as? NSTextField }
                try expect(labels.contains { $0.toolTip == longTitle }, "truncated title must retain full tooltip")
                try expect(labels.contains { $0.toolTip?.contains(longMessage) == true }, "truncated subtitle must retain full tooltip")
                try expect(view.hitTest(NSPoint(x: size.width / 2, y: 36)) == nil, "informational stack must preserve parent gestures")
                let identityBeforeTheme = snapshot.eventIDs
                view.theme = theme == .comic ? .storybook : .comic
                try expect(view.snapshot.eventIDs == identityBeforeTheme && view.snapshot.rowFrames == snapshot.rowFrames, "theme changes must preserve tasks and geometry")
                view.theme = theme
                try capture(view, theme: theme, width: Int(width))
            }
        }
        try expect(view.idealSize(maxWidth: -1).width == 0 && view.idealSize(maxWidth: .nan).width == 0, "invalid widths must be safe")
        let firstAfter = try JSONFileStore.encoder.encode(first)
        let fixturesAfter = try JSONFileStore.encoder.encode(fixtures)
        try expect(firstAfter == original, "receive must not mutate caller event")
        try expect(fixturesAfter == encodedFixtures, "theme/layout must not mutate fixture data")
        view.clear()
        try expect(view.snapshot.rows.isEmpty && view.snapshot.scheduledExpiry == nil, "clear must remove rows and stop timer")
        print("progress-stack-regression: receipt TTL, source/thread replacement, three-row bound, independent expiry, narrow layout, two themes, tooltips, accessibility, gesture passthrough and immutable inputs passed")
    }

    @MainActor private static func capture(_ view: CompanionProgressStackView, theme: AppVisualTheme, width: Int) throws {
        guard let directory = ProcessInfo.processInfo.environment["WHISKYCLING_REGRESSION_ARTIFACT_DIR"] else { return }
        let window = NSWindow(contentRect: view.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = view
        defer { window.contentView = nil }
        view.layoutSubtreeIfNeeded()
        guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
            throw Failure(description: "progress-stack: cannot allocate capture")
        }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        guard let png = bitmap.representation(using: .png, properties: [:]) else {
            throw Failure(description: "progress-stack: cannot encode capture")
        }
        try png.write(to: URL(fileURLWithPath: directory).appendingPathComponent("progress-stack-\(theme.rawValue)-\(width).png"))
        withExtendedLifetime(window) {}
    }
}
