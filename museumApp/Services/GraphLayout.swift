import Foundation
import CoreGraphics

nonisolated struct GraphEdge: Hashable, Sendable {
    enum Kind: Sendable { case link, shared }

    let a: Block.ID
    let b: Block.ID
    let kind: Kind

    /// Edges are undirected, so the pair is stored in a fixed order.
    init(_ first: Block.ID, _ second: Block.ID, kind: Kind) {
        (a, b) = first.uuidString < second.uuidString ? (first, second) : (second, first)
        self.kind = kind
    }
}

/// What the graph shows: every reflected block, joined by `[[links]]` (strong)
/// and by sharing a tag, a website or a collection (weak).
nonisolated struct GraphData: Equatable, Sendable {
    var nodes: [Block.ID] = []
    var edges: [GraphEdge] = []

    /// Groups bigger than this would draw a hairball, so they're skipped.
    private static let maxSharedGroup = 8

    init() {}

    init(blocks: [Block], links: LinkIndex, collections: [BlockCollection]) {
        nodes = blocks.map(\.id).sorted { $0.uuidString < $1.uuidString }
        let present = Set(nodes)

        var found = Set<GraphEdge>()
        var linked = Set<[Block.ID]>()
        for (from, targets) in links.outgoing where present.contains(from) {
            for to in targets where present.contains(to) {
                let edge = GraphEdge(from, to, kind: .link)
                found.insert(edge)
                linked.insert([edge.a, edge.b])
            }
        }

        var groups: [[Block.ID]] = []
        for (_, ids) in Dictionary(grouping: blocks.flatMap { block in block.tags.map { (WikiLinks.key(for: $0), block.id) } }, by: \.0) {
            groups.append(ids.map(\.1))
        }
        for (_, ids) in Dictionary(grouping: blocks.compactMap { block in block.sourceDomain.map { ($0, block.id) } }, by: \.0) {
            groups.append(ids.map(\.1))
        }
        for collection in collections {
            groups.append(collection.blockIDs.filter(present.contains))
        }
        for group in groups where group.count > 1 && group.count <= Self.maxSharedGroup {
            for (index, first) in group.enumerated() {
                for second in group[(index + 1)...] where first != second {
                    let edge = GraphEdge(first, second, kind: .shared)
                    if !linked.contains([edge.a, edge.b]) { found.insert(edge) }
                }
            }
        }
        edges = found.sorted { ($0.a.uuidString, $0.b.uuidString) < ($1.a.uuidString, $1.b.uuidString) }
    }
}

/// Force-directed layout (Fruchterman–Reingold). Returns positions in the unit square.
nonisolated enum GraphLayout {
    @concurrent
    static func compute(_ data: GraphData) async -> [Block.ID: CGPoint] {
        layout(data)
    }

    static func layout(_ data: GraphData, iterations: Int = 300) -> [Block.ID: CGPoint] {
        let count = data.nodes.count
        guard count > 0 else { return [:] }
        guard count > 1 else { return [data.nodes[0]: CGPoint(x: 0.5, y: 0.5)] }

        let index = Dictionary(uniqueKeysWithValues: data.nodes.enumerated().map { ($1, $0) })
        let springs = data.edges.compactMap { edge -> (Int, Int, Double)? in
            guard let a = index[edge.a], let b = index[edge.b] else { return nil }
            return (a, b, edge.kind == .link ? 1 : 0.35)
        }

        // Start on a circle, so the result is the same every time for the same data.
        var x = (0..<count).map { 0.5 + 0.4 * cos(Double($0) / Double(count) * 2 * .pi) }
        var y = (0..<count).map { 0.5 + 0.4 * sin(Double($0) / Double(count) * 2 * .pi) }

        let k = 0.8 / Double(count).squareRoot()
        for step in 0..<iterations {
            let temperature = 0.1 * (1 - Double(step) / Double(iterations)) + 0.002
            var dx = [Double](repeating: 0, count: count)
            var dy = [Double](repeating: 0, count: count)

            for i in 0..<count {
                for j in (i + 1)..<count {
                    var ex = x[i] - x[j], ey = y[i] - y[j]
                    var distance = (ex * ex + ey * ey).squareRoot()
                    if distance < 0.001 { ex = 0.001 * Double(i + 1); ey = 0.001; distance = 0.001 }
                    let push = k * k / distance
                    dx[i] += ex / distance * push; dy[i] += ey / distance * push
                    dx[j] -= ex / distance * push; dy[j] -= ey / distance * push
                }
            }
            for (a, b, weight) in springs {
                let ex = x[a] - x[b], ey = y[a] - y[b]
                let distance = max((ex * ex + ey * ey).squareRoot(), 0.001)
                let pull = distance * distance / k * weight
                dx[a] -= ex / distance * pull; dy[a] -= ey / distance * pull
                dx[b] += ex / distance * pull; dy[b] += ey / distance * pull
            }
            for i in 0..<count {
                // A little gravity keeps unconnected blocks from drifting away.
                dx[i] -= (x[i] - 0.5) * 0.3 * k
                dy[i] -= (y[i] - 0.5) * 0.3 * k
                let length = max((dx[i] * dx[i] + dy[i] * dy[i]).squareRoot(), 0.0001)
                let move = min(length, temperature)
                x[i] += dx[i] / length * move
                y[i] += dy[i] / length * move
            }
        }

        // Scale to fill the unit square (keeping proportions), with a margin.
        let (minX, maxX) = (x.min() ?? 0, x.max() ?? 1)
        let (minY, maxY) = (y.min() ?? 0, y.max() ?? 1)
        let span = max(maxX - minX, maxY - minY, 0.0001)
        var result: [Block.ID: CGPoint] = [:]
        for (id, i) in index {
            result[id] = CGPoint(
                x: 0.5 + (x[i] - (minX + maxX) / 2) / span * 0.9,
                y: 0.5 + (y[i] - (minY + maxY) / 2) / span * 0.9
            )
        }
        return result
    }
}
