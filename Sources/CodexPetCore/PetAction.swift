import Foundation

public enum CodexPetAction: String, Codable, CaseIterable, Equatable, Identifiable {
    case idle
    case runningRight
    case runningLeft
    case waving
    case jumping
    case failed
    case waiting
    case running
    case review

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .idle: return "Idle"
        case .runningRight: return "Running Right"
        case .runningLeft: return "Running Left"
        case .waving: return "Waving"
        case .jumping: return "Jumping"
        case .failed: return "Failed"
        case .waiting: return "Waiting"
        case .running: return "Running"
        case .review: return "Review"
        }
    }

    public var chineseName: String {
        switch self {
        case .idle: return "待机"
        case .runningRight: return "右跑"
        case .runningLeft: return "左跑"
        case .waving: return "挥手"
        case .jumping: return "跳跃"
        case .failed: return "失败"
        case .waiting: return "等待"
        case .running: return "执行中"
        case .review: return "审查"
        }
    }

    public var rowIndex: Int {
        switch self {
        case .idle: return 0
        case .runningRight: return 1
        case .runningLeft: return 2
        case .waving: return 3
        case .jumping: return 4
        case .failed: return 5
        case .waiting: return 6
        case .running: return 7
        case .review: return 8
        }
    }

    public static func normalized(_ value: String) -> CodexPetAction? {
        let normalized = value
            .lowercased()
            .replacingOccurrences(of: "_", with: "")
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: " ", with: "")

        switch normalized {
        case "idle": return .idle
        case "runningright", "runright", "right": return .runningRight
        case "runningleft", "runleft", "left": return .runningLeft
        case "waving", "wave": return .waving
        case "jumping", "jump": return .jumping
        case "failed", "fail", "error": return .failed
        case "waiting", "wait": return .waiting
        case "running", "run", "progress": return .running
        case "review", "reviewing": return .review
        default: return nil
        }
    }
}

public extension AgentStatus {
    var petAction: CodexPetAction {
        switch self {
        case .running: return .running
        case .review: return .review
        case .done: return .waving
        case .failed: return .failed
        case .waiting: return .waiting
        case .message: return .idle
        }
    }
}
