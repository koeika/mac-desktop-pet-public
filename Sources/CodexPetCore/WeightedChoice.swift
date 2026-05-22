import Foundation

public enum WeightedChoice {
    public static func pickIndex(weights: [Double], random: Double = Double.random(in: 0..<1)) -> Int? {
        let normalized = weights.map { max(0, $0) }
        let total = normalized.reduce(0, +)
        guard total > 0 else { return nil }

        var cursor = min(max(random, 0), 0.999_999) * total
        for (index, weight) in normalized.enumerated() where weight > 0 {
            cursor -= weight
            if cursor <= 0 {
                return index
            }
        }
        return normalized.lastIndex(where: { $0 > 0 })
    }
}

