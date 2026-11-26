import AppKit
import CodexPetCore

enum CompanionStyle: String, CaseIterable {
    case original, ink, color

    var title: String {
        switch self {
        case .original: return "写实原版"
        case .ink: return "黑白手绘"
        case .color: return "彩色漫画"
        }
    }
    func matches(_ id: String) -> Bool {
        switch self {
        case .original: return id == "whisky" || id == "cling"
        case .ink: return id.hasSuffix("-ink")
        case .color: return id.hasSuffix("-color")
        }
    }
}

extension AppDataStore {
    static let companionIDs = ["whisky", "cling", "whisky-ink", "cling-ink", "whisky-color", "cling-color"]

    static func companionID(for pet: PetAsset) -> String? {
        [pet.packageSourceID, pet.id, pet.packageDirectoryName].compactMap { $0 }
            .first { companionIDs.contains($0) }
    }

    var companionPreviewPets: [PetAsset] {
        let enabled = enabledPets()
        return Self.companionIDs.compactMap { id in
            enabled.first { Self.companionID(for: $0) == id }
        }
    }

    var selectedCompanionStyle: CompanionStyle? {
        let ids = companionPreviewPets.compactMap { Self.companionID(for: $0) }
        guard !ids.isEmpty else { return nil }
        return CompanionStyle.allCases.first { style in ids.allSatisfy(style.matches) }
    }

    // The receipt remembers deletions, while existing IDs retain all user preferences.
    func installBundledPetsIfNeeded(restoring requested: Set<String> = []) throws {
        try commitBundledPets(restoring: requested, selecting: nil)
    }

    private func commitBundledPets(restoring requested: Set<String>, selecting style: CompanionStyle?) throws {
        let receiptURL = rootURL.appendingPathComponent("bundled-pets.json")
        let receiptData = try readLocalFileIfPresent(at: receiptURL)
        var installed = try receiptData.map { try JSONFileStore.decoder.decode([String].self, from: $0) } ?? []
        let previousInstalled = installed
        var updated = pets
        var copied: [URL] = []
        var staging: URL?
        do {
            for id in Self.companionIDs where !installed.contains(id) || requested.contains(id) {
                if !updated.contains(where: { Self.companionID(for: $0) == id }) {
                    guard let manifestURL = AppResourceLocator.file(named: "Pets/\(id)/pet", extension: "json") else {
                        if requested.contains(id) {
                            throw NSError(domain: "CodexDesktopPet", code: 37, userInfo: [NSLocalizedDescriptionKey: "找不到内置素材 \(id)，未切换样式。"])
                        }
                        continue
                    }
                    let source = manifestURL.deletingLastPathComponent()
                    let inspection = try CodexPetPackageInstaller.inspectPackage(at: source)
                    let destination = packagesURL.appendingPathComponent(id)
                    // Never replace a preexisting unregistered asset directory.
                    guard !FileManager.default.fileExists(atPath: destination.path) else {
                        if requested.contains(id) {
                            throw NSError(domain: "CodexDesktopPet", code: 36, userInfo: [NSLocalizedDescriptionKey: "存在未登记的 \(id) 素材目录，请从本地宠物包入口导入，避免覆盖素材。"])
                        }
                        continue
                    }
                    let stagingDirectory: URL
                    if let directory = staging {
                        stagingDirectory = directory
                    } else {
                        let directory = packagesURL.appendingPathComponent(".bundled-install-\(UUID().uuidString)")
                        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
                        staging = directory
                        stagingDirectory = directory
                    }
                    let temporary = stagingDirectory.appendingPathComponent(id)
                    try FileManager.default.copyItem(at: source, to: temporary)
                    try FileManager.default.moveItem(at: temporary, to: destination)
                    copied.append(destination)
                    updated.append(PetAsset(
                        id: id, name: inspection.manifest.resolvedDisplayName, kind: .codexPackage,
                        packageDirectoryName: id, spriteFileName: inspection.spriteFileName,
                        packageSourceID: id,
                        packageSourceURL: "https://codex-pets.net/#/pets/\(id.replacingOccurrences(of: "-ink", with: "").replacingOccurrences(of: "-color", with: ""))",
                        supportsNativeActions: true, actionFrameCount: inspection.framesPerAction,
                        isEnabled: id.hasSuffix("-ink")
                    ))
                }
                if !installed.contains(id) { installed.append(id) }
            }
            if let style {
                for index in updated.indices {
                    guard let id = Self.companionID(for: updated[index]) else { continue }
                    updated[index].isEnabled = style.matches(id)
                }
            }
            if let directory = staging {
                try FileManager.default.removeItem(at: directory)
                staging = nil
            }
            var writes: [(url: URL, data: Data)] = []
            if updated != pets { writes.append((petsManifestURL, try JSONFileStore.encoder.encode(updated))) }
            if installed != previousInstalled || receiptData == nil {
                writes.append((receiptURL, try JSONFileStore.encoder.encode(installed)))
            }
            try commitLocalFiles(writes)
        } catch {
            var cleanupErrors: [String] = []
            for directory in Array(copied.reversed()) + (staging.map { [$0] } ?? []) {
                do { try FileManager.default.removeItem(at: directory) }
                catch { cleanupErrors.append(error.localizedDescription) }
            }
            if !cleanupErrors.isEmpty {
                throw NSError(domain: "CodexDesktopPet", code: 38, userInfo: [
                    NSLocalizedDescriptionKey: "\(error.localizedDescription)；清理本次新增素材失败：\(cleanupErrors.joined(separator: "; "))",
                    NSUnderlyingErrorKey: error
                ])
            }
            throw error
        }
        if updated != pets {
            objectWillChange.send()
            pets = updated
        }
    }

    func selectCompanionStyle(ink: Bool) throws {
        try selectCompanionStyle(ink ? .ink : .original)
    }

    func selectCompanionStyle(_ style: CompanionStyle) throws {
        try commitBundledPets(restoring: Set(Self.companionIDs.filter(style.matches)), selecting: style)
    }
}
