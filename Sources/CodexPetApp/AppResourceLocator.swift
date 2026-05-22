import Foundation

enum AppResourceLocator {
    private static let resourceBundleName = "CodexDesktopPet_CodexPetApp.bundle"

    static func resourceBundleDirectories() -> [URL] {
        var candidates: [URL] = []

        if let resourceURL = Bundle.main.resourceURL {
            candidates.append(resourceURL.appendingPathComponent(resourceBundleName, isDirectory: true))
        }

        candidates.append(Bundle.main.bundleURL.appendingPathComponent(resourceBundleName, isDirectory: true))
        candidates.append(Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent(resourceBundleName, isDirectory: true))

        var seen = Set<String>()
        return candidates.filter { directory in
            guard FileManager.default.fileExists(atPath: directory.path), !seen.contains(directory.path) else {
                return false
            }
            seen.insert(directory.path)
            return true
        }
    }

    static func file(named name: String, extension fileExtension: String) -> URL? {
        let fileName = "\(name).\(fileExtension)"
        let directResources = Bundle.main.resourceURL.map {
            $0.appendingPathComponent(fileName, isDirectory: false)
        }
        let bundledResources = resourceBundleDirectories().map {
            $0.appendingPathComponent(fileName, isDirectory: false)
        }
        return ([directResources].compactMap { $0 } + bundledResources).first {
            FileManager.default.fileExists(atPath: $0.path)
        }
    }
}
