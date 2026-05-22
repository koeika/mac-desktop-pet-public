import AppKit
import CodexPetCore

enum PhotoArchivePetBuilder {
    static let framesPerAction = 8
    private static let frameSize = NSSize(width: 220, height: 220)

    static func buildPackage(
        name: String,
        imageURLs: [URL],
        destination: URL
    ) throws -> PetPackageInspection {
        guard imageURLs.count >= 2 else {
            throw NSError(
                domain: "CodexDesktopPet",
                code: 52,
                userInfo: [NSLocalizedDescriptionKey: "图片 zip 至少需要 2 张图片才能合成为动图宠物。"]
            )
        }

        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)

        let frames = try imageURLs.map { try PhotoFrame(image: processedFrameImage(from: $0)) }
        let sprite = try makeSpritesheet(frames: PhotoFrameCatalog(frames: frames))
        let spriteURL = destination.appendingPathComponent("spritesheet.png")
        guard let spriteData = pngData(from: sprite) else {
            throw NSError(domain: "CodexDesktopPet", code: 53, userInfo: [NSLocalizedDescriptionKey: "生成 spritesheet 失败。"])
        }
        try spriteData.write(to: spriteURL, options: [.atomic])

        let manifest = CodexPetPackageManifest(
            id: CodexPetPackageInstaller.sanitizedIdentifier(name),
            displayName: name,
            description: "由照片压缩包自动合成的 9 动作桌宠。",
            spritesheetPath: "spritesheet.png",
            previewPath: nil,
            kind: "photoArchive",
            framesPerAction: framesPerAction
        )
        try JSONFileStore.save(manifest, to: destination.appendingPathComponent("pet.json"))

        return PetPackageInspection(
            packageDirectory: destination,
            manifest: manifest,
            spriteFileName: "spritesheet.png",
            previewFileName: nil,
            supportsNativeActions: true,
            framesPerAction: framesPerAction
        )
    }

    private static func processedFrameImage(from url: URL) throws -> NSImage {
        if let data = try? PetImageProcessor.processImage(at: url),
           let image = NSImage(data: data) {
            return image
        }
        guard let image = NSImage(contentsOf: url) else {
            throw NSError(domain: "CodexDesktopPet", code: 54, userInfo: [NSLocalizedDescriptionKey: "无法读取 \(url.lastPathComponent)。"])
        }
        return image
    }

    private struct PhotoFrame {
        var image: NSImage
        var aspectRatio: CGFloat

        init(image: NSImage) {
            self.image = image
            aspectRatio = image.size.width / max(image.size.height, 1)
        }
    }

    private struct PhotoFrameCatalog {
        var neutral: PhotoFrame
        var alternateNeutral: PhotoFrame
        var wide: PhotoFrame
        var low: PhotoFrame

        init(frames: [PhotoFrame]) {
            let sortedByAspect = frames.sorted { $0.aspectRatio < $1.aspectRatio }
            neutral = sortedByAspect.first ?? frames[0]
            alternateNeutral = sortedByAspect.dropFirst().first ?? neutral
            wide = sortedByAspect.last ?? neutral
            low = sortedByAspect.reversed().dropFirst().first ?? wide
        }
    }

    private static func makeSpritesheet(frames: PhotoFrameCatalog) throws -> NSImage {
        let spriteSize = NSSize(
            width: frameSize.width * CGFloat(framesPerAction),
            height: frameSize.height * CGFloat(CodexPetAction.allCases.count)
        )
        let sheet = NSImage(size: spriteSize)
        sheet.lockFocus()
        NSColor.clear.setFill()
        NSRect(origin: .zero, size: spriteSize).fill()

        for action in CodexPetAction.allCases {
            for column in 0..<framesPerAction {
                let source = sourceFrame(for: action, frames: frames)
                let rect = NSRect(
                    x: CGFloat(column) * frameSize.width,
                    y: CGFloat(CodexPetAction.allCases.count - 1 - action.rowIndex) * frameSize.height,
                    width: frameSize.width,
                    height: frameSize.height
                )
                draw(source, action: action, column: column, in: rect)
            }
        }

        sheet.unlockFocus()
        return sheet
    }

    private static func sourceFrame(for action: CodexPetAction, frames: PhotoFrameCatalog) -> NSImage {
        switch action {
        case .runningRight, .runningLeft, .running:
            return frames.wide.image
        case .jumping:
            return frames.alternateNeutral.image
        case .failed:
            return frames.low.image
        case .waiting, .review:
            return frames.alternateNeutral.image
        default:
            return frames.neutral.image
        }
    }

    private static func draw(_ image: NSImage, action: CodexPetAction, column: Int, in rect: NSRect) {
        let progress = Double(column) / Double(max(1, framesPerAction - 1))
        let wave = sin(progress * Double.pi * 2)
        var scale = 0.82 + CGFloat(0.025 * wave)
        var xOffset: CGFloat = 0
        var yOffset: CGFloat = 0
        var rotation: CGFloat = 0
        var flip = false

        switch action {
        case .idle:
            yOffset = CGFloat(3 * wave)
        case .runningRight:
            scale = 0.74
            xOffset = CGFloat((progress - 0.5) * 22)
            yOffset = CGFloat(abs(wave) * 7)
        case .runningLeft:
            scale = 0.74
            xOffset = CGFloat((0.5 - progress) * 22)
            yOffset = CGFloat(abs(wave) * 7)
            flip = true
        case .waving:
            rotation = CGFloat(0.08 * wave)
            yOffset = CGFloat(2 * wave)
        case .jumping:
            scale = 0.78
            yOffset = CGFloat(sin(progress * Double.pi) * 42)
            rotation = CGFloat(0.06 * wave)
        case .failed:
            scale = 0.76
            rotation = CGFloat(-0.11 + 0.04 * wave)
            yOffset = -12
        case .waiting:
            scale = 0.80 + CGFloat(0.018 * wave)
            rotation = CGFloat(0.03 * wave)
        case .running:
            scale = 0.72
            yOffset = CGFloat(abs(wave) * 5) - 8
        case .review:
            scale = 0.78 + CGFloat(0.012 * wave)
            rotation = CGFloat(0.04 * wave)
        }

        let drawSize = fittedSize(image.size, in: rect.size, scale: scale)
        let drawRect = NSRect(
            x: rect.midX - drawSize.width / 2 + xOffset,
            y: rect.minY + 18 + yOffset,
            width: drawSize.width,
            height: drawSize.height
        )

        NSGraphicsContext.saveGraphicsState()
        let transform = NSAffineTransform()
        transform.translateX(by: drawRect.midX, yBy: drawRect.midY)
        if flip {
            transform.scaleX(by: -1, yBy: 1)
        }
        transform.rotate(byRadians: rotation)
        transform.translateX(by: -drawRect.midX, yBy: -drawRect.midY)
        transform.concat()
        image.draw(in: drawRect, from: .zero, operation: .sourceOver, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()
    }

    private static func fittedSize(_ source: NSSize, in target: NSSize, scale: CGFloat) -> NSSize {
        let ratio = min(target.width / max(source.width, 1), target.height / max(source.height, 1)) * scale
        return NSSize(width: source.width * ratio, height: source.height * ratio)
    }

    private static func pngData(from image: NSImage) -> Data? {
        var rect = NSRect(origin: .zero, size: image.size)
        guard let cgImage = image.cgImage(forProposedRect: &rect, context: nil, hints: nil) else { return nil }
        let rep = NSBitmapImageRep(cgImage: cgImage)
        return rep.representation(using: .png, properties: [:])
    }
}
