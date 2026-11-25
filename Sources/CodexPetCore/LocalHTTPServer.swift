import Foundation
import Network

public final class LocalHTTPServer {
    private let port: UInt16
    private let queue = DispatchQueue(label: "codex-desktop-pet.http")
    private var listener: NWListener?
    private let stateProvider: () -> AgentState
    private let eventHandler: (ProgressEvent) -> Void
    private let vocabularyToken: String?
    private let vocabularyHandler: ((String, Data) throws -> Data)?
    private let lookupHandler: ((Data) async throws -> Data)?

    public init(
        port: UInt16 = 4789,
        stateProvider: @escaping () -> AgentState,
        eventHandler: @escaping (ProgressEvent) -> Void,
        vocabularyToken: String? = nil,
        vocabularyHandler: ((String, Data) throws -> Data)? = nil,
        lookupHandler: ((Data) async throws -> Data)? = nil
    ) {
        self.port = port
        self.stateProvider = stateProvider
        self.eventHandler = eventHandler
        self.vocabularyToken = vocabularyToken
        self.vocabularyHandler = vocabularyHandler
        self.lookupHandler = lookupHandler
    }

    public func start() throws {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(
            host: NWEndpoint.Host("127.0.0.1"),
            port: NWEndpoint.Port(rawValue: port)!
        )
        let listener = try NWListener(using: parameters)
        listener.newConnectionHandler = { [weak self] connection in
            guard let self else { return }
            connection.start(queue: self.queue)
            self.receive(on: connection, buffer: Data())
        }
        listener.start(queue: queue)
        self.listener = listener
    }

    public func stop() {
        listener?.cancel()
        listener = nil
    }

    private func receive(on connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            var nextBuffer = buffer
            if let data {
                nextBuffer.append(data)
            }
            guard nextBuffer.count <= 128 * 1024 else {
                self.respond(status: 413, body: ErrorResponse(ok: false, error: "Request too large"), on: connection)
                return
            }
            if let request = HTTPRequest(data: nextBuffer), request.isComplete || isComplete || error != nil {
                self.handle(request, connection: connection)
                return
            }
            if isComplete || error != nil {
                self.respond(status: 400, body: ErrorResponse(ok: false, error: "Bad request"), on: connection)
                return
            }
            self.receive(on: connection, buffer: nextBuffer)
        }
    }

    private func handle(_ request: HTTPRequest, connection: NWConnection) {
        if request.method == "OPTIONS" {
            respond(status: 204, rawBody: Data(), on: connection)
            return
        }

        if request.path == "/v1/vocabulary" || request.path == "/v1/vocabulary/lookup" {
            guard let token = vocabularyToken, !token.isEmpty,
                  request.headers["authorization"] == "Bearer \(token)" else {
                respond(status: 401, body: ErrorResponse(ok: false, error: "请在 Chrome 扩展中填写桌宠配对码。"), on: connection)
                return
            }
            if request.path == "/v1/vocabulary/lookup" {
                guard request.method == "POST", let lookupHandler else {
                    respond(status: 404, body: ErrorResponse(ok: false, error: "Not found"), on: connection)
                    return
                }
                Task {
                    do {
                        let data = try await lookupHandler(request.body)
                        self.respond(status: 200, rawBody: data, on: connection)
                    } catch {
                        self.respond(status: error is CaptureError || error is DecodingError ? 400 : 500,
                            body: ErrorResponse(ok: false, error: error.localizedDescription), on: connection)
                    }
                }
                return
            }
            guard ["GET", "POST"].contains(request.method), let vocabularyHandler else {
                respond(status: 404, body: ErrorResponse(ok: false, error: "Not found"), on: connection)
                return
            }
            do {
                respond(status: request.method == "POST" ? 201 : 200,
                    rawBody: try vocabularyHandler(request.method, request.body), on: connection)
            } catch {
                respond(status: error is CaptureError || error is DecodingError ? 400 : 500,
                    body: ErrorResponse(ok: false, error: error.localizedDescription), on: connection)
            }
            return
        }

        switch (request.method, request.path) {
        case ("GET", "/v1/state"):
            respond(status: 200, body: StateResponse(ok: true, state: stateProvider()), on: connection)
        case ("POST", "/v1/progress"):
            handleEventPost(request, connection: connection, defaultStatus: .running)
        case ("POST", "/v1/message"):
            handleEventPost(request, connection: connection, defaultStatus: .message)
        default:
            respond(status: 404, body: ErrorResponse(ok: false, error: "Not found"), on: connection)
        }
    }

    private func handleEventPost(_ request: HTTPRequest, connection: NWConnection, defaultStatus: AgentStatus) {
        do {
            let payload = try JSONFileStore.decoder.decode(ProgressEventPayload.self, from: request.body)
            let event = payload.toEvent(defaultStatus: defaultStatus)
            eventHandler(event)
            respond(status: 201, body: EventResponse(ok: true, event: event), on: connection)
        } catch {
            respond(status: 400, body: ErrorResponse(ok: false, error: error.localizedDescription), on: connection)
        }
    }

    private func respond<T: Encodable>(status: Int, body: T, on connection: NWConnection) {
        do {
            let bodyData = try JSONFileStore.encoder.encode(body)
            respond(status: status, rawBody: bodyData, on: connection)
        } catch {
            respond(status: 500, rawBody: Data("{\"ok\":false}".utf8), on: connection)
        }
    }

    private func respond(status: Int, rawBody: Data, on connection: NWConnection) {
        let reason = HTTPStatus.reason(for: status)
        var header = "HTTP/1.1 \(status) \(reason)\r\n"
        header += "Content-Type: application/json; charset=utf-8\r\n"
        header += "Access-Control-Allow-Origin: *\r\n"
        header += "Access-Control-Allow-Methods: GET, POST, OPTIONS\r\n"
        header += "Access-Control-Allow-Headers: content-type, authorization\r\n"
        header += "Content-Length: \(rawBody.count)\r\n"
        header += "Connection: close\r\n\r\n"
        var response = Data(header.utf8)
        response.append(rawBody)
        connection.send(content: response, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }
}

private struct StateResponse: Codable {
    var ok: Bool
    var state: AgentState
}

private struct EventResponse: Codable {
    var ok: Bool
    var event: ProgressEvent
}

private struct ErrorResponse: Codable {
    var ok: Bool
    var error: String
}

private struct HTTPRequest {
    var method: String
    var path: String
    var body: Data
    var isComplete: Bool
    var headers: [String: String] = [:]

    init?(data: Data) {
        guard let delimiter = data.range(of: Data("\r\n\r\n".utf8)) else { return nil }
        let headerData = data[..<delimiter.lowerBound]
        guard let headerText = String(data: headerData, encoding: .utf8) else { return nil }
        let lines = headerText.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else { return nil }
        let parts = requestLine.split(separator: " ")
        guard parts.count >= 2 else { return nil }
        method = String(parts[0]).uppercased()
        path = String(parts[1]).split(separator: "?").first.map(String.init) ?? "/"

        var contentLength = 0
        for line in lines.dropFirst() {
            let pieces = line.split(separator: ":", maxSplits: 1).map(String.init)
            if pieces.count == 2, pieces[0].lowercased() == "content-length" {
                guard let length = Int(pieces[1].trimmingCharacters(in: .whitespacesAndNewlines)),
                      length >= 0, length <= 128 * 1024 else { return nil }
                contentLength = length
            }
            if pieces.count == 2 { headers[pieces[0].lowercased()] = pieces[1].trimmingCharacters(in: .whitespacesAndNewlines) }
        }

        let bodyStart = delimiter.upperBound
        let availableBody = data[bodyStart...]
        isComplete = availableBody.count >= contentLength
        body = Data(availableBody.prefix(contentLength))
    }
}

private enum HTTPStatus {
    static func reason(for status: Int) -> String {
        switch status {
        case 200: return "OK"
        case 201: return "Created"
        case 204: return "No Content"
        case 400: return "Bad Request"
        case 401: return "Unauthorized"
        case 413: return "Payload Too Large"
        case 404: return "Not Found"
        case 500: return "Internal Server Error"
        default: return "OK"
        }
    }
}
