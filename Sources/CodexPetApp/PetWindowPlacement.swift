import AppKit

enum PetWindowPlacement {
    static func frame(savedOrigin: CGPoint?, screens: [NSRect], main: NSRect) -> NSRect {
        let screen = savedOrigin.flatMap { point -> NSRect? in
            let previous = NSRect(origin: point, size: NSSize(width: 460, height: 500))
            func area(_ frame: NSRect) -> CGFloat {
                let overlap = frame.intersection(previous)
                return overlap.isNull ? 0 : overlap.width * overlap.height
            }
            guard let best = screens.max(by: { area($0) < area($1) }), area(best) > 0 else { return nil }
            return best
        } ?? main
        let size = NSSize(width: min(460, max(1, screen.width - 16)), height: min(700, max(1, screen.height - 24)))
        let preferred = savedOrigin ?? NSPoint(x: screen.maxX - size.width - 42, y: screen.minY + 60)
        let origin = NSPoint(x: min(max(preferred.x, screen.minX + 8), screen.maxX - size.width - 8),
                             y: min(max(preferred.y, screen.minY + 8), screen.maxY - size.height - 8))
        return NSRect(origin: origin, size: size)
    }
}
