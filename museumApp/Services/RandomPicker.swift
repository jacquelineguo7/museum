import Foundation

/// Picks a block at random, favouring ones you haven't seen in a while.
nonisolated enum RandomPicker {
    /// Blocks never surfaced get the maximum weight; others weigh one point per day since last seen.
    static let maxWeight = 365.0

    static func weight(for block: Block, now: Date) -> Double {
        guard let last = block.lastSurfacedAt else { return maxWeight }
        let days = now.timeIntervalSince(last) / 86_400
        return min(max(days, 1), maxWeight)
    }

    /// - Parameter excluding: a block to avoid repeating (ignored if it's the only choice).
    static func pick<G: RandomNumberGenerator>(
        from blocks: [Block],
        excluding: Block.ID? = nil,
        now: Date = .now,
        using generator: inout G
    ) -> Block? {
        var candidates = blocks.filter { $0.id != excluding }
        if candidates.isEmpty { candidates = blocks }
        guard !candidates.isEmpty else { return nil }

        let total = candidates.reduce(0) { $0 + weight(for: $1, now: now) }
        var target = Double.random(in: 0..<total, using: &generator)
        for block in candidates {
            target -= weight(for: block, now: now)
            if target < 0 { return block }
        }
        return candidates.last
    }

    static func pick(from blocks: [Block], excluding: Block.ID? = nil) -> Block? {
        var generator = SystemRandomNumberGenerator()
        return pick(from: blocks, excluding: excluding, using: &generator)
    }
}
