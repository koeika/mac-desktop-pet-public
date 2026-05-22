import AppKit
import CoreImage
import Vision

enum PetImageProcessor {
    static func processImage(at url: URL) throws -> Data {
        guard let image = NSImage(contentsOf: url),
              let cgImage = image.cgImageValue else {
            throw NSError(domain: "CodexDesktopPet", code: 1, userInfo: [NSLocalizedDescriptionKey: "Cannot read image"])
        }

        if let cutout = try? foregroundCutout(from: cgImage),
           let data = pngData(from: cutout) {
            return data
        }

        guard let fallback = roundedSticker(from: image),
              let data = pngData(from: fallback) else {
            throw NSError(domain: "CodexDesktopPet", code: 2, userInfo: [NSLocalizedDescriptionKey: "Cannot process image"])
        }
        return data
    }

    private static func foregroundCutout(from cgImage: CGImage) throws -> CGImage {
        let request = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage)
        try handler.perform([request])
        guard let observation = request.results?.first else {
            throw NSError(domain: "CodexDesktopPet", code: 3)
        }
        let maskBuffer = try observation.generateScaledMaskForImage(
            forInstances: observation.allInstances,
            from: handler
        )
        let source = CIImage(cgImage: cgImage)
        let mask = CIImage(cvPixelBuffer: maskBuffer)
        let clear = CIImage(color: .clear).cropped(to: source.extent)
        let output = source.applyingFilter("CIBlendWithMask", parameters: [
            kCIInputBackgroundImageKey: clear,
            kCIInputMaskImageKey: mask
        ])
        let scaled = resize(output, maxSide: 512)
        let context = CIContext(options: [.useSoftwareRenderer: false])
        guard let result = context.createCGImage(scaled, from: scaled.extent) else {
            throw NSError(domain: "CodexDesktopPet", code: 4)
        }
        return result
    }

    private static func roundedSticker(from image: NSImage) -> CGImage? {
        let side: CGFloat = 512
        let canvas = NSImage(size: NSSize(width: side, height: side))
        canvas.lockFocus()
        NSColor.clear.setFill()
        NSRect(x: 0, y: 0, width: side, height: side).fill()

        let path = NSBezierPath(ovalIn: NSRect(x: 16, y: 16, width: side - 32, height: side - 32))
        path.addClip()
        let sourceSize = image.size
        let scale = max(side / sourceSize.width, side / sourceSize.height)
        let drawSize = NSSize(width: sourceSize.width * scale, height: sourceSize.height * scale)
        let drawRect = NSRect(
            x: (side - drawSize.width) / 2,
            y: (side - drawSize.height) / 2,
            width: drawSize.width,
            height: drawSize.height
        )
        image.draw(in: drawRect)
        canvas.unlockFocus()
        return canvas.cgImageValue
    }

    private static func resize(_ image: CIImage, maxSide: CGFloat) -> CIImage {
        let maxDimension = max(image.extent.width, image.extent.height)
        guard maxDimension > maxSide else { return image }
        let scale = maxSide / maxDimension
        return image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
    }

    private static func pngData(from cgImage: CGImage) -> Data? {
        let rep = NSBitmapImageRep(cgImage: cgImage)
        return rep.representation(using: .png, properties: [:])
    }
}

private extension NSImage {
    var cgImageValue: CGImage? {
        var rect = NSRect(origin: .zero, size: size)
        return cgImage(forProposedRect: &rect, context: nil, hints: nil)
    }
}

