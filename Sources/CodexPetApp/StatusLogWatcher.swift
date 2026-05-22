import CodexPetCore
import Foundation

final class StatusLogWatcher {
    var paths: [String] = []
    var onEvent: ((ProgressEvent) -> Void)?

    private var offsets: [String: UInt64] = [:]
    private var timer: Timer?

    func start() {
        stop()
        timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.tick()
        }
        RunLoop.main.add(timer!, forMode: .common)
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func tick() {
        for path in paths {
            readNewLines(at: URL(fileURLWithPath: path))
        }
    }

    private func readNewLines(at url: URL) {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return }
        defer { try? handle.close() }

        let previousOffset = offsets[url.path] ?? 0
        let fileSize = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? UInt64) ?? 0
        let offset = previousOffset <= fileSize ? previousOffset : 0
        do {
            try handle.seek(toOffset: offset)
            let data = try handle.readToEnd() ?? Data()
            offsets[url.path] = offset + UInt64(data.count)
            guard let text = String(data: data, encoding: .utf8) else { return }
            text.split(whereSeparator: \.isNewline).forEach { line in
                if let event = parseLine(String(line)) {
                    onEvent?(event)
                }
            }
        } catch {
            offsets[url.path] = fileSize
        }
    }

    private func parseLine(_ line: String) -> ProgressEvent? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        let jsonText: String
        if trimmed.hasPrefix("PET_PROGRESS ") {
            jsonText = String(trimmed.dropFirst("PET_PROGRESS ".count))
        } else if trimmed.hasPrefix("{"), trimmed.contains("\"source\""), trimmed.contains("\"message\"") {
            jsonText = trimmed
        } else {
            return nil
        }

        guard let data = jsonText.data(using: .utf8),
              let payload = try? JSONFileStore.decoder.decode(ProgressEventPayload.self, from: data) else {
            return nil
        }
        return payload.toEvent(defaultStatus: payload.status ?? .running)
    }
}

