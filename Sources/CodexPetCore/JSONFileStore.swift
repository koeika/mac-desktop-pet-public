import Foundation

public enum JSONFileStore {
    public static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    public static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    public static func load<T: Decodable>(_ type: T.Type, from url: URL, fallback: T) -> T {
        guard let data = try? Data(contentsOf: url) else { return fallback }
        return (try? decoder.decode(T.self, from: data)) ?? fallback
    }

    public static func save<T: Encodable>(_ value: T, to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try encoder.encode(value)
        try data.write(to: url, options: [.atomic])
    }

    public static func applicationSupportDirectory(appName: String = "CodexDesktopPet") throws -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let url = base.appendingPathComponent(appName, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

