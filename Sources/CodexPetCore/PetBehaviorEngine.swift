import CoreGraphics
import Foundation

public struct PetMotionState: Equatable {
    public var origin: CGPoint
    public var action: CodexPetAction

    public init(origin: CGPoint, action: CodexPetAction) {
        self.origin = origin
        self.action = action
    }
}

public struct PetBehaviorEngine {
    private enum Mode {
        case idle(remaining: TimeInterval)
        case moving(start: CGPoint, target: CGPoint, duration: TimeInterval, elapsed: TimeInterval)
        case performing(action: CodexPetAction, remaining: TimeInterval)
    }

    public private(set) var origin: CGPoint
    private var mode: Mode

    public init(origin: CGPoint = .zero) {
        self.origin = origin
        self.mode = .idle(remaining: 4.0)
    }

    public mutating func snap(to origin: CGPoint) {
        self.origin = origin
        self.mode = .idle(remaining: 2.8)
    }

    public mutating func tick(
        deltaTime: TimeInterval,
        bounds: CGRect,
        petSize: CGSize,
        preferredAction: CodexPetAction? = nil,
        speedMultiplier: Double = 0.20,
        random: () -> Double = { Double.random(in: 0..<1) }
    ) -> PetMotionState {
        let clampedBounds = CGRect(
            x: bounds.minX,
            y: bounds.minY,
            width: max(1, bounds.width - petSize.width),
            height: max(1, bounds.height - petSize.height)
        )
        origin = clamped(origin, in: clampedBounds)

        var naturalAction: CodexPetAction = .idle

        switch mode {
        case .idle(let remaining):
            let nextRemaining = remaining - deltaTime
            if nextRemaining > 0 {
                mode = .idle(remaining: nextRemaining)
                naturalAction = .idle
            } else {
                chooseNextMode(bounds: clampedBounds, speedMultiplier: speedMultiplier, random: random)
                return tick(
                    deltaTime: 0,
                    bounds: bounds,
                    petSize: petSize,
                    preferredAction: preferredAction,
                    speedMultiplier: speedMultiplier,
                    random: random
                )
            }

        case .performing(let action, let remaining):
            let nextRemaining = remaining - deltaTime
            if nextRemaining > 0 {
                mode = .performing(action: action, remaining: nextRemaining)
                naturalAction = action
            } else {
                mode = .idle(remaining: randomRange(4.0, 10.0, random))
                naturalAction = .idle
            }

        case .moving(let start, let target, let duration, let elapsed):
            let nextElapsed = min(duration, elapsed + deltaTime)
            let progress = duration <= 0 ? 1 : nextElapsed / duration
            let eased = smoothStep(progress)
            origin = CGPoint(
                x: start.x + (target.x - start.x) * eased,
                y: start.y + (target.y - start.y) * eased
            )
            origin = clamped(origin, in: clampedBounds)

            if nextElapsed >= duration {
                mode = .idle(remaining: randomRange(3.8, 10.5, random))
                naturalAction = .idle
            } else {
                mode = .moving(start: start, target: target, duration: duration, elapsed: nextElapsed)
                if abs(target.x - start.x) < 8 {
                    naturalAction = .running
                } else {
                    naturalAction = target.x > start.x ? .runningRight : .runningLeft
                }
            }
        }

        return PetMotionState(origin: origin, action: preferredAction ?? naturalAction)
    }

    private mutating func chooseNextMode(bounds: CGRect, speedMultiplier: Double, random: () -> Double) {
        let roll = random()
        if roll < 0.58 {
            mode = .idle(remaining: randomRange(4.0, 11.0, random))
            return
        }
        if roll < 0.65 {
            mode = .performing(action: .waiting, remaining: randomRange(3.0, 6.5, random))
            return
        }
        if roll < 0.69 {
            mode = .performing(action: .waving, remaining: randomRange(1.6, 3.0, random))
            return
        }
        if roll < 0.71 {
            mode = .performing(action: .jumping, remaining: randomRange(1.0, 1.8, random))
            return
        }

        let angle = random() * Double.pi * 2
        let stepDistance = randomRange(36, 170, random)
        let target = CGPoint(
            x: origin.x + CGFloat(cos(angle) * stepDistance),
            y: origin.y + CGFloat(sin(angle) * stepDistance)
        )
        let clampedTarget = clamped(target, in: bounds)
        let distance = hypot(clampedTarget.x - origin.x, clampedTarget.y - origin.y)
        guard distance >= 12 else {
            mode = .idle(remaining: randomRange(4.0, 11.0, random))
            return
        }
        let speedScale = min(max(speedMultiplier, 0.1), 1.4)
        let speed = randomRange(42, 88, random) * speedScale
        let duration = max(1.6, min(45, TimeInterval(distance / CGFloat(speed))))
        mode = .moving(start: origin, target: clampedTarget, duration: duration, elapsed: 0)
    }

    private func clamped(_ point: CGPoint, in bounds: CGRect) -> CGPoint {
        CGPoint(
            x: min(max(point.x, bounds.minX), bounds.maxX),
            y: min(max(point.y, bounds.minY), bounds.maxY)
        )
    }

    private func randomRange(_ minValue: Double, _ maxValue: Double, _ random: () -> Double) -> Double {
        minValue + (maxValue - minValue) * min(max(random(), 0), 0.999_999)
    }

    private func smoothStep(_ value: Double) -> CGFloat {
        let t = min(max(value, 0), 1)
        return CGFloat(t * t * (3 - 2 * t))
    }
}
