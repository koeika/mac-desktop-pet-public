import CodexPetCore
import Foundation

@main
struct PetCTL {
    static func main() async {
        let cli = CLI(arguments: Array(CommandLine.arguments.dropFirst()))
        do {
            try await cli.run()
        } catch {
            FileHandle.standardError.write(Data("petctl: \(error.localizedDescription)\n".utf8))
            exit(1)
        }
    }
}

private struct CLI {
    var arguments: [String]

    func run() async throws {
        guard let command = arguments.first else {
            printHelp()
            return
        }

        switch command {
        case "progress":
            try await post(path: "/v1/progress", payload: payload(defaultStatus: .running))
        case "done":
            var event = payload(defaultStatus: .done)
            event.status = .done
            event.progress = 100
            if event.stage == nil { event.stage = "done" }
            try await post(path: "/v1/progress", payload: event)
        case "message":
            try await post(path: "/v1/message", payload: payload(defaultStatus: .message))
        case "state":
            try await getState()
        case "help", "--help", "-h":
            printHelp()
        default:
            throw CLIError.message("Unknown command: \(command)")
        }
    }

    private func payload(defaultStatus: AgentStatus) -> ProgressEventPayload {
        ProgressEventPayload(
            source: value(for: "--source") ?? "manual",
            stage: value(for: "--stage"),
            message: value(for: "--message") ?? positionalMessage ?? "",
            progress: value(for: "--progress").flatMap(Int.init),
            status: value(for: "--status").flatMap(AgentStatus.init(rawValue:)) ?? defaultStatus,
            threadId: value(for: "--thread-id"),
            timestamp: Date()
        )
    }

    private var positionalMessage: String? {
        let values = arguments.dropFirst().filter { !$0.hasPrefix("--") }
        return values.isEmpty ? nil : values.joined(separator: " ")
    }

    private func value(for flag: String) -> String? {
        guard let index = arguments.firstIndex(of: flag),
              arguments.indices.contains(index + 1) else {
            return nil
        }
        return arguments[index + 1]
    }

    private var baseURL: URL {
        if let explicit = value(for: "--server"), let url = URL(string: explicit) {
            return url
        }
        if let env = ProcessInfo.processInfo.environment["PET_SERVER_URL"], let url = URL(string: env) {
            return url
        }
        return URL(string: "http://127.0.0.1:4789")!
    }

    private func post(path: String, payload: ProgressEventPayload) async throws {
        let url = baseURL.appendingPathComponent(path.trimmingCharacters(in: CharacterSet(charactersIn: "/")))
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "content-type")
        let data = try JSONFileStore.encoder.encode(payload)
        let (responseData, response) = try await URLSession.shared.upload(for: request, from: data)
        try validate(response: response, data: responseData)
        if let text = String(data: responseData, encoding: .utf8) {
            print(text)
        }
    }

    private func getState() async throws {
        let url = baseURL.appendingPathComponent("v1/state")
        let (data, response) = try await URLSession.shared.data(from: url)
        try validate(response: response, data: data)
        if let text = String(data: data, encoding: .utf8) {
            print(text)
        }
    }

    private func validate(response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw CLIError.message("HTTP \(http.statusCode) \(body)")
        }
    }

    private func printHelp() {
        print("""
        petctl - send local AI progress to Codex Desktop Pet

        Usage:
          petctl progress --source codex --stage "实现功能" --message "正在修改文件" --progress 60
          petctl done --source codex --message "任务完成"
          petctl message --source cursor --message "等待用户确认"
          petctl state

        Options:
          --server http://127.0.0.1:4789
          --source codex|claude|cursor|manual
          --stage text
          --message text
          --progress 0...100
          --status running|review|done|failed|waiting|message
          --thread-id stable-task-id
        """)
    }
}

private enum CLIError: LocalizedError {
    case message(String)

    var errorDescription: String? {
        switch self {
        case .message(let message):
            return message
        }
    }
}

