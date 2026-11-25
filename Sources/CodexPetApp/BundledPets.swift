import AppKit
import CodexPetCore

enum CompanionStyle: String, CaseIterable {
    case original, ink, color
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

    // The receipt remembers deletions, while existing IDs retain all user preferences.
    func installBundledPetsIfNeeded(restoring requested: Set<String> = []) throws {
        let receiptURL = rootURL.appendingPathComponent("bundled-pets.json")
        var installed = JSONFileStore.load([String].self, from: receiptURL, fallback: [])
        var changed = false
        for id in Self.companionIDs where !installed.contains(id) || requested.contains(id) {
            if !pets.contains(where: { Self.companionID(for: $0) == id }) {
                guard let manifestURL = AppResourceLocator.file(named: "Pets/\(id)/pet", extension: "json") else { continue }
                let source = manifestURL.deletingLastPathComponent()
                let inspection = try CodexPetPackageInstaller.inspectPackage(at: source)
                let destination = packagesURL.appendingPathComponent(id)
                // Do not overwrite an unregistered user-owned package directory.
                guard !FileManager.default.fileExists(atPath: destination.path) else {
                    if requested.contains(id) {
                        throw NSError(domain: "CodexDesktopPet", code: 36, userInfo: [NSLocalizedDescriptionKey: "存在未登记的 \(id) 素材目录，请从本地宠物包入口导入，避免覆盖素材。"])
                    }
                    continue
                }
                try FileManager.default.copyItem(at: source, to: destination)
                pets.append(PetAsset(
                    id: id, name: inspection.manifest.resolvedDisplayName, kind: .codexPackage,
                    packageDirectoryName: id, spriteFileName: inspection.spriteFileName,
                    packageSourceID: id,
                    packageSourceURL: "https://codex-pets.net/#/pets/\(id.replacingOccurrences(of: "-ink", with: "").replacingOccurrences(of: "-color", with: ""))",
                    supportsNativeActions: true, actionFrameCount: inspection.framesPerAction,
                    isEnabled: id.hasSuffix("-ink")
                ))
                changed = true
            }
            if !installed.contains(id) { installed.append(id) }
        }
        if changed { try JSONFileStore.save(pets, to: petsManifestURL) }
        try JSONFileStore.save(installed, to: receiptURL)
    }

    func selectCompanionStyle(ink: Bool) throws {
        try selectCompanionStyle(ink ? .ink : .original)
    }

    func selectCompanionStyle(_ style: CompanionStyle) throws {
        try installBundledPetsIfNeeded(restoring: Set(Self.companionIDs.filter(style.matches)))
        objectWillChange.send()
        for index in pets.indices {
            guard let id = Self.companionID(for: pets[index]) else { continue }
            pets[index].isEnabled = style.matches(id)
        }
        try JSONFileStore.save(pets, to: petsManifestURL)
    }
}
