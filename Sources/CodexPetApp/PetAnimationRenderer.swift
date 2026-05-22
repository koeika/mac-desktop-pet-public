import AppKit
import CodexPetCore
import ImageIO
import UniformTypeIdentifiers

final class PetAnimationRenderer {
    let spriteURL: URL
    let framesPerAction: Int
    private let sprite: CGImage
    private let rowCount = CodexPetAction.allCases.count
    private let visibleColumnsByRow: [[Int]]

    init?(spriteURL: URL, framesPerAction: Int = 8) {
        guard let image = NSImage(contentsOf: spriteURL),
              let cgImage = image.cgImageForPet else {
            return nil
        }
        self.spriteURL = spriteURL
        self.framesPerAction = max(1, framesPerAction)
        self.sprite = cgImage
        self.visibleColumnsByRow = Self.visibleColumnsByRow(
            sprite: cgImage,
            rowCount: rowCount,
            framesPerAction: self.framesPerAction
        )
    }

    func frame(for action: CodexPetAction, frameIndex: Int) -> NSImage? {
        let columnCount = max(1, framesPerAction)
        let frameWidth = max(1, sprite.width / columnCount)
        let frameHeight = max(1, sprite.height / rowCount)
        let requestedRow = min(action.rowIndex, rowCount - 1)
        let row = visibleColumnsByRow[requestedRow].isEmpty ? 0 : requestedRow
        let visibleColumns = visibleColumnsByRow[row]
        let column = if visibleColumns.isEmpty {
            abs(frameIndex) % columnCount
        } else {
            visibleColumns[abs(frameIndex) % visibleColumns.count]
        }
        let rect = CGRect(
            x: column * frameWidth,
            y: row * frameHeight,
            width: frameWidth,
            height: frameHeight
        )
        guard let cropped = sprite.cropping(to: rect) else { return nil }
        return NSImage(cgImage: cropped, size: NSSize(width: frameWidth, height: frameHeight))
    }

    func stillFrame(for action: CodexPetAction = .idle) -> NSImage? {
        frame(for: action, frameIndex: 0)
    }

    private static func visibleColumnsByRow(sprite: CGImage, rowCount: Int, framesPerAction: Int) -> [[Int]] {
        let columnCount = max(1, framesPerAction)
        let frameWidth = max(1, sprite.width / columnCount)
        let frameHeight = max(1, sprite.height / rowCount)
        return (0..<rowCount).map { row in
            (0..<columnCount).filter { column in
                let rect = CGRect(
                    x: column * frameWidth,
                    y: row * frameHeight,
                    width: frameWidth,
                    height: frameHeight
                )
                guard let cropped = sprite.cropping(to: rect) else { return false }
                return hasVisiblePixels(cropped)
            }
        }
    }

    private static func hasVisiblePixels(_ image: CGImage) -> Bool {
        let width = 24
        let height = 24
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        var pixels = [UInt8](repeating: 0, count: height * bytesPerRow)
        let drewImage = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else {
                return false
            }
            context.interpolationQuality = .none
            context.clear(CGRect(x: 0, y: 0, width: width, height: height))
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard drewImage else { return true }
        return stride(from: 3, to: pixels.count, by: bytesPerPixel).contains { pixels[$0] > 8 }
    }
}

extension NSImage {
    var cgImageForPet: CGImage? {
        var rect = NSRect(origin: .zero, size: size)
        return cgImage(forProposedRect: &rect, context: nil, hints: nil)
    }
}

final class AnimatedPetRenderer {
    struct Frame {
        var image: NSImage
        var duration: TimeInterval
    }

    private let frames: [Frame]
    private var frameIndex = 0
    private var elapsed: TimeInterval = 0

    init?(url: URL) {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            return nil
        }
        let count = CGImageSourceGetCount(source)
        guard count > 1 else { return nil }

        var parsedFrames: [Frame] = []
        for index in 0..<count {
            guard let cgImage = CGImageSourceCreateImageAtIndex(source, index, nil) else { continue }
            let duration = Self.frameDuration(source: source, index: index)
            parsedFrames.append(Frame(
                image: NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height)),
                duration: duration
            ))
        }

        guard !parsedFrames.isEmpty else { return nil }
        frames = parsedFrames
    }

    var stillFrame: NSImage? {
        frames.first?.image
    }

    func nextFrame(deltaTime: TimeInterval) -> NSImage? {
        guard !frames.isEmpty else { return nil }
        elapsed += deltaTime
        while elapsed >= frames[frameIndex].duration {
            elapsed -= frames[frameIndex].duration
            frameIndex = (frameIndex + 1) % frames.count
        }
        return frames[frameIndex].image
    }

    static func isAnimatedImage(_ url: URL) -> Bool {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            return false
        }
        return CGImageSourceGetCount(source) > 1
    }

    private static func frameDuration(source: CGImageSource, index: Int) -> TimeInterval {
        let defaultDuration = 0.1
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any] else {
            return defaultDuration
        }

        if let gif = properties[kCGImagePropertyGIFDictionary] as? [CFString: Any] {
            return sanitizedDuration(
                gif[kCGImagePropertyGIFUnclampedDelayTime] as? Double
                    ?? gif[kCGImagePropertyGIFDelayTime] as? Double
                    ?? defaultDuration
            )
        }

        if let png = properties[kCGImagePropertyPNGDictionary] as? [CFString: Any] {
            return sanitizedDuration(
                png[kCGImagePropertyAPNGUnclampedDelayTime] as? Double
                    ?? png[kCGImagePropertyAPNGDelayTime] as? Double
                    ?? defaultDuration
            )
        }

        return defaultDuration
    }

    private static func sanitizedDuration(_ duration: Double) -> TimeInterval {
        let value = duration.isFinite ? duration : 0.1
        return max(0.04, min(1.2, value))
    }
}
