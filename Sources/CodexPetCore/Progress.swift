import Foundation

public enum AgentStatus: String, Codable, CaseIterable, Equatable {
    case running
    case review
    case done
    case failed
    case waiting
    case message
}

public struct ProgressEvent: Codable, Identifiable, Equatable {
    public var id: String
    public var source: String
    public var stage: String
    public var message: String
    public var progress: Int?
    public var status: AgentStatus
    public var threadId: String?
    public var timestamp: Date

    public init(
        id: String = UUID().uuidString,
        source: String,
        stage: String,
        message: String,
        progress: Int? = nil,
        status: AgentStatus = .running,
        threadId: String? = nil,
        timestamp: Date = Date()
    ) {
        self.id = id
        self.source = source.isEmpty ? "unknown" : source
        self.stage = stage.isEmpty ? status.rawValue : stage
        self.message = message
        if let progress {
            self.progress = max(0, min(100, progress))
        } else {
            self.progress = nil
        }
        self.status = status
        self.threadId = threadId
        self.timestamp = timestamp
    }
}

public struct AgentState: Codable, Equatable {
    public var current: ProgressEvent?
    public var events: [ProgressEvent]

    public init(current: ProgressEvent? = nil, events: [ProgressEvent] = []) {
        self.current = current
        self.events = events
    }
}

public final class ProgressStateStore {
    private let lock = NSLock()
    private var storedState = AgentState()
    private let maxEvents: Int

    public init(maxEvents: Int = 80) {
        self.maxEvents = maxEvents
    }

    public var state: AgentState {
        lock.lock()
        defer { lock.unlock() }
        return storedState
    }

    @discardableResult
    public func apply(_ event: ProgressEvent) -> AgentState {
        lock.lock()
        defer { lock.unlock() }

        storedState.current = event
        if let threadId = event.threadId,
           let index = storedState.events.firstIndex(where: { $0.threadId == threadId }) {
            storedState.events[index] = event
        } else {
            storedState.events.insert(event, at: 0)
        }

        if storedState.events.count > maxEvents {
            storedState.events.removeLast(storedState.events.count - maxEvents)
        }
        return storedState
    }
}

public struct ProgressEventPayload: Codable {
    public var source: String?
    public var stage: String?
    public var message: String?
    public var progress: Int?
    public var status: AgentStatus?
    public var threadId: String?
    public var timestamp: Date?

    public init(
        source: String? = nil,
        stage: String? = nil,
        message: String? = nil,
        progress: Int? = nil,
        status: AgentStatus? = nil,
        threadId: String? = nil,
        timestamp: Date? = nil
    ) {
        self.source = source
        self.stage = stage
        self.message = message
        self.progress = progress
        self.status = status
        self.threadId = threadId
        self.timestamp = timestamp
    }

    public func toEvent(defaultStatus: AgentStatus) -> ProgressEvent {
        let resolvedProgress = progress.map { max(0, min(100, $0)) }
        let resolvedStatus: AgentStatus
        if let status {
            resolvedStatus = status
        } else if resolvedProgress == 100 {
            resolvedStatus = .done
        } else {
            resolvedStatus = defaultStatus
        }

        return ProgressEvent(
            source: source ?? "unknown",
            stage: stage ?? resolvedStatus.rawValue,
            message: message ?? "",
            progress: resolvedProgress,
            status: resolvedStatus,
            threadId: threadId,
            timestamp: timestamp ?? Date()
        )
    }
}

