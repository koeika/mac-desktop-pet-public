import Foundation
#if canImport(XCTest)
import XCTest
#endif
@testable import CodexPetCore

final class CaptureHTTPTests: XCTestCase {
    func testAuthenticatedCapturePersistsAndRejectsInvalidWrites() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("notebook.json")
        let port = UInt16.random(in: 23000...42000)
        let token = UUID().uuidString
        let server = LocalHTTPServer(port: port, stateProvider: { AgentState() }, eventHandler: { _ in },
            vocabularyToken: token, vocabularyHandler: { method, data in
                var notebook = JSONFileStore.load(PersonalVocabulary.self, from: file, fallback: PersonalVocabulary())
                if method == "POST" {
                    try notebook.capture(JSONFileStore.decoder.decode(CapturePayload.self, from: data))
                    try JSONFileStore.save(notebook, to: file)
                }
                return try JSONFileStore.encoder.encode(notebook)
            })
        try server.start()
        defer { server.stop() }
        let base = URL(string: "http://127.0.0.1:\(port)")!
        for _ in 0..<30 {
            if (try? await URLSession.shared.data(from: base.appendingPathComponent("v1/state"))) != nil { break }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        func request(_ method: String, _ body: String? = nil, authorized: Bool = true) -> URLRequest {
            var req = URLRequest(url: base.appendingPathComponent("v1/vocabulary"))
            req.httpMethod = method
            if authorized { req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
            req.httpBody = body.map { Data($0.utf8) }
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            return req
        }
        let (_, unauthorized) = try await URLSession.shared.data(for: request("POST", #"{"term":"inherently"}"#, authorized: false))
        XCTAssertEqual((unauthorized as? HTTPURLResponse)?.statusCode, 401)
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
        let (_, saved) = try await URLSession.shared.data(for: request("POST", #"{"term":"inherently","meaning":"本质上"}"#))
        XCTAssertEqual((saved as? HTTPURLResponse)?.statusCode, 201)
        let (data, fetched) = try await URLSession.shared.data(for: request("GET"))
        XCTAssertEqual((fetched as? HTTPURLResponse)?.statusCode, 200)
        XCTAssertEqual(try JSONFileStore.decoder.decode(PersonalVocabulary.self, from: data).words.count, 1)
        XCTAssertEqual(JSONFileStore.load(PersonalVocabulary.self, from: file, fallback: PersonalVocabulary()).words.first?.content.meaning, "本质上")
        let (_, invalid) = try await URLSession.shared.data(for: request("POST", #"{"term":""}"#))
        XCTAssertEqual((invalid as? HTTPURLResponse)?.statusCode, 400)
        XCTAssertEqual(JSONFileStore.load(PersonalVocabulary.self, from: file, fallback: PersonalVocabulary()).words.count, 1)
    }
}
