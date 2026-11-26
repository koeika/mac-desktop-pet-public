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
        case moving(start: CGPoint, target: CGPoint, duration: TimeInterval, elapsed: TimeInterval, referenceMultiplier: Double)
        case performing(action: CodexPetAction, remaining: TimeInterval)
    }

    public private(set) var origin: CGPoint
    private var mode: Mode

    public init(origin: CGPoint = .zero) {
        self.origin = origin
        self.mode = .idle(remaining: 30)
    }

    public mutating func snap(to origin: CGPoint) {
        self.origin = origin
        self.mode = .idle(remaining: 20)
    }

    public mutating func tick(
        deltaTime: TimeInterval,
        bounds: CGRect,
        petSize: CGSize,
        preferredAction: CodexPetAction? = nil,
        speedMultiplier: Double = 0.10,
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
                mode = .idle(remaining: randomRange(25, 65, random))
                naturalAction = .idle
            }

        case .moving(let start, let target, let duration, let elapsed, let referenceMultiplier):
            // Scale future time, not completed progress, so live changes never teleport the pet.
            let rate = normalizedSpeed(speedMultiplier) / referenceMultiplier
            let nextElapsed = min(duration, elapsed + max(0, deltaTime) * rate)
            let progress = duration <= 0 ? 1 : nextElapsed / duration
            let eased = smoothStep(progress)
            origin = CGPoint(
                x: start.x + (target.x - start.x) * eased,
                y: start.y + (target.y - start.y) * eased
            )
            origin = clamped(origin, in: clampedBounds)

            if nextElapsed >= duration {
                mode = .idle(remaining: randomRange(30, 80, random))
                naturalAction = .idle
            } else {
                mode = .moving(start: start, target: target, duration: duration, elapsed: nextElapsed, referenceMultiplier: referenceMultiplier)
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
        if roll < 0.55 {
            mode = .idle(remaining: randomRange(25, 65, random))
            return
        }
        if roll < 0.72 {
            mode = .performing(action: .waiting, remaining: randomRange(10, 20, random))
            return
        }
        if roll < 0.86 {
            mode = .performing(action: .review, remaining: randomRange(8, 16, random))
            return
        }
        if roll < 0.90 {
            mode = .performing(action: .waving, remaining: randomRange(2, 3, random))
            return
        }

        let angle = random() * Double.pi * 2
        let multiplier = normalizedSpeed(speedMultiplier)
        let speed = randomRange(18, 30, random) * multiplier
        let stepDistance = speed * randomRange(4, 8, random)
        let target = CGPoint(
            x: origin.x + CGFloat(cos(angle) * stepDistance),
            y: origin.y + CGFloat(sin(angle) * stepDistance)
        )
        let clampedTarget = clamped(target, in: bounds)
        let distance = hypot(clampedTarget.x - origin.x, clampedTarget.y - origin.y)
        guard distance >= 2 else {
            mode = .idle(remaining: randomRange(25, 65, random))
            return
        }
        let duration = max(0.5, TimeInterval(distance / CGFloat(speed)))
        mode = .moving(start: origin, target: clampedTarget, duration: duration, elapsed: 0, referenceMultiplier: multiplier)
    }

    private func normalizedSpeed(_ value: Double) -> Double {
        value.isFinite ? min(max(value, 0.05), 1.4) : 0.10
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
