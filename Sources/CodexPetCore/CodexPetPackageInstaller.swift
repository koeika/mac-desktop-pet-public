import Foundation

public struct CodexPetPackageManifest: Codable, Equatable {
    public var id: String
    public var displayName: String?
    public var name: String?
    public var description: String?
    public var spritesheetPath: String?
    public var previewPath: String?
    public var kind: String?
    public var framesPerAction: Int?

    public init(
        id: String,
        displayName: String? = nil,
        name: String? = nil,
        description: String? = nil,
        spritesheetPath: String? = nil,
        previewPath: String? = nil,
        kind: String? = nil,
        framesPerAction: Int? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.name = name
        self.description = description
        self.spritesheetPath = spritesheetPath
        self.previewPath = previewPath
        self.kind = kind
        self.framesPerAction = framesPerAction
    }

    public var resolvedDisplayName: String {
        displayName ?? name ?? id
    }

    public var resolvedFramesPerAction: Int {
        max(1, min(64, framesPerAction ?? 8))
    }
}

public struct PetPackageInspection: Equatable {
    public var packageDirectory: URL
    public var manifest: CodexPetPackageManifest
    public var spriteFileName: String
    public var previewFileName: String?
    public var supportsNativeActions: Bool
    public var framesPerAction: Int

    public init(
        packageDirectory: URL,
        manifest: CodexPetPackageManifest,
        spriteFileName: String,
        previewFileName: String?,
        supportsNativeActions: Bool,
        framesPerAction: Int
    ) {
        self.packageDirectory = packageDirectory
        self.manifest = manifest
        self.spriteFileName = spriteFileName
        self.previewFileName = previewFileName
        self.supportsNativeActions = supportsNativeActions
        self.framesPerAction = framesPerAction
    }
}

public struct CodexPetRemoteReference: Equatable {
    public var input: String
    public var id: String?
    public var directZipURL: URL?
    public var metadataURL: URL?
    public var fallbackZipURL: URL?

    public init(
        input: String,
        id: String? = nil,
        directZipURL: URL? = nil,
        metadataURL: URL? = nil,
        fallbackZipURL: URL? = nil
    ) {
        self.input = input
        self.id = id
        self.directZipURL = directZipURL
        self.metadataURL = metadataURL
        self.fallbackZipURL = fallbackZipURL
    }
}

public enum CodexPetPackageInstaller {
    public static func remoteReference(for rawInput: String) throws -> CodexPetRemoteReference {
        let input = rawInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !input.isEmpty, let url = URL(string: input) else {
            throw error("请输入有效的宠物链接。", code: 100)
        }

        if url.pathExtension.lowercased() == "zip" {
            return CodexPetRemoteReference(input: input, directZipURL: url)
        }

        guard let host = url.host?.lowercased() else {
            throw error("无法识别这个链接的域名。", code: 101)
        }

        if host.contains("codexpets.net"), let id = galleryID(from: url) {
            return CodexPetRemoteReference(
                input: input,
                id: id,
                fallbackZipURL: URL(string: "https://codexpets.net/api/gallery-pets/\(id)/download")
            )
        }

        if host.contains("codex-pets.net"), let id = hashPetID(from: url) ?? pathPetID(from: url) {
            return CodexPetRemoteReference(
                input: input,
                id: id,
                metadataURL: URL(string: "https://codex-pets.net/api/pets/\(id)"),
                fallbackZipURL: URL(string: "https://codex-pets.net/api/pets/\(id)/download")
            )
        }

        throw error("暂不支持这个宠物站点。请粘贴 codex-pets.net、codexpets.net 或直接 .zip 链接。", code: 102)
    }

    public static func downloadURL(fromMetadata data: Data, baseURL: URL) -> URL? {
        guard let object = try? JSONSerialization.jsonObject(with: data) else { return nil }
        return firstDownloadURL(in: object, baseURL: baseURL)
    }

    public static func inspectPackage(at directory: URL) throws -> PetPackageInspection {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw error("请选择包含 pet.json 的宠物文件夹。", code: 110)
        }

        let manifestURL = directory.appendingPathComponent("pet.json")
        guard FileManager.default.fileExists(atPath: manifestURL.path) else {
            throw error("宠物包缺少 pet.json。", code: 111)
        }

        let manifestData = try Data(contentsOf: manifestURL)
        let manifest = try JSONFileStore.decoder.decode(CodexPetPackageManifest.self, from: manifestData)
        let spriteFileName = try spriteFileName(in: directory, preferred: manifest.spritesheetPath)
        let previewFileName = previewFileName(in: directory, preferred: manifest.previewPath)
        return PetPackageInspection(
            packageDirectory: directory,
            manifest: manifest,
            spriteFileName: spriteFileName,
            previewFileName: previewFileName,
            supportsNativeActions: true,
            framesPerAction: manifest.resolvedFramesPerAction
        )
    }

    public static func extractZip(_ zipURL: URL, to destinationDirectory: URL) throws -> URL {
        try FileManager.default.createDirectory(at: destinationDirectory, withIntermediateDirectories: true)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-q", zipURL.path, "-d", destinationDirectory.path]
        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw error("解压 zip 失败，请确认这是有效的 Codex pet 包。", code: 120)
        }

        return try findPackageDirectory(in: destinationDirectory)
    }

    public static func sanitizedIdentifier(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let scalars = value.unicodeScalars.map { scalar -> Character in
            allowed.contains(scalar) ? Character(scalar) : "-"
        }
        let collapsed = String(scalars)
            .split(separator: "-")
            .joined(separator: "-")
            .trimmingCharacters(in: CharacterSet(charactersIn: "-_"))
        return collapsed.isEmpty ? UUID().uuidString : collapsed
    }

    private static func galleryID(from url: URL) -> String? {
        let pieces = url.pathComponents.filter { $0 != "/" }
        guard let index = pieces.firstIndex(of: "gallery"), pieces.indices.contains(index + 1) else {
            return nil
        }
        return sanitizedIdentifier(pieces[index + 1])
    }

    private static func hashPetID(from url: URL) -> String? {
        guard let fragment = url.fragment else { return nil }
        let pieces = fragment.split(separator: "/").map(String.init)
        guard let index = pieces.firstIndex(of: "pets"), pieces.indices.contains(index + 1) else {
            return nil
        }
        return sanitizedIdentifier(pieces[index + 1])
    }

    private static func pathPetID(from url: URL) -> String? {
        let pieces = url.pathComponents.filter { $0 != "/" }
        guard let index = pieces.firstIndex(of: "pets"), pieces.indices.contains(index + 1) else {
            return nil
        }
        return sanitizedIdentifier(pieces[index + 1])
    }

    private static func spriteFileName(in directory: URL, preferred: String?) throws -> String {
        if let preferred,
           fileExists(directory.appendingPathComponent(preferred)),
           ["webp", "png"].contains(URL(fileURLWithPath: preferred).pathExtension.lowercased()) {
            return preferred
        }

        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        if let sprite = files.first(where: { ["spritesheet.webp", "spritesheet.png"].contains($0.lastPathComponent.lowercased()) }) {
            return sprite.lastPathComponent
        }
        if let image = files.first(where: { ["webp", "png"].contains($0.pathExtension.lowercased()) }) {
            return image.lastPathComponent
        }
        throw error("宠物包缺少 spritesheet.webp 或 spritesheet.png。", code: 112)
    }

    private static func previewFileName(in directory: URL, preferred: String?) -> String? {
        if let preferred, fileExists(directory.appendingPathComponent(preferred)) {
            return preferred
        }
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        return files.first(where: { ["preview.png", "preview.webp"].contains($0.lastPathComponent.lowercased()) })?.lastPathComponent
    }

    private static func findPackageDirectory(in root: URL) throws -> URL {
        if fileExists(root.appendingPathComponent("pet.json")) {
            return root
        }

        let children = (try? FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        for child in children {
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: child.path, isDirectory: &isDirectory), isDirectory.boolValue,
               fileExists(child.appendingPathComponent("pet.json")) {
                return child
            }
        }

        throw error("解压后没有找到包含 pet.json 的文件夹。", code: 121)
    }

    private static func firstDownloadURL(in value: Any, baseURL: URL) -> URL? {
        if let dictionary = value as? [String: Any] {
            let keys = [
                "downloadUrl",
                "downloadURL",
                "download_url",
                "packageUrl",
                "packageURL",
                "package_url",
                "url"
            ]
            for key in keys {
                if let raw = dictionary[key] as? String,
                   let resolved = resolvedURL(raw, baseURL: baseURL),
                   resolved.pathExtension.lowercased() == "zip" || raw.contains("/download") {
                    return resolved
                }
            }
            for child in dictionary.values {
                if let resolved = firstDownloadURL(in: child, baseURL: baseURL) {
                    return resolved
                }
            }
        }

        if let array = value as? [Any] {
            for child in array {
                if let resolved = firstDownloadURL(in: child, baseURL: baseURL) {
                    return resolved
                }
            }
        }

        return nil
    }

    private static func resolvedURL(_ raw: String, baseURL: URL) -> URL? {
        if let absolute = URL(string: raw), absolute.scheme != nil {
            return absolute
        }
        return URL(string: raw, relativeTo: baseURL)?.absoluteURL
    }

    private static func fileExists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    private static func error(_ message: String, code: Int) -> NSError {
        NSError(domain: "CodexDesktopPet", code: code, userInfo: [NSLocalizedDescriptionKey: message])
    }
}
