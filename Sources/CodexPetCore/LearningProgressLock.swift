import Foundation
import Darwin

public final class LearningProgressLock {
    private let descriptor: Int32

    public init(root: URL) throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let fd = Darwin.open(root.appendingPathComponent("learning-progress.lock").path, O_CREAT | O_RDWR, 0o600)
        guard fd >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        guard flock(fd, LOCK_EX | LOCK_NB) == 0 else {
            Darwin.close(fd)
            throw NSError(domain: "LearningProgressLock", code: 1,
                userInfo: [NSLocalizedDescriptionKey: "学习数据正在使用中，请先退出正在运行的桌宠，再执行维护。"])
        }
        descriptor = fd
    }

    deinit { flock(descriptor, LOCK_UN); Darwin.close(descriptor) }
}
