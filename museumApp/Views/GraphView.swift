import SwiftUI

/// Every reflected block as a dot. Solid lines are `[[links]]`; faint dashed lines join blocks
/// that share a tag, a website or a collection. Drag to pan, pinch to zoom, click a dot to open it.
struct GraphView: View {
    let onOpen: (Block) -> Void

    @Environment(LibraryModel.self) private var library

    @State private var data = GraphData()
    @State private var positions: [Block.ID: CGPoint] = [:]
    @State private var showShared = true
    @State private var hovered: Block.ID?
    @State private var zoom: CGFloat = 1
    @State private var baseZoom: CGFloat = 1
    @State private var pan: CGSize = .zero
    @State private var basePan: CGSize = .zero

    var body: some View {
        Group {
            if data.nodes.isEmpty {
                EmptyStateView(
                    title: "Nothing to connect yet",
                    systemImage: "point.3.connected.trianglepath.dotted",
                    message: "Blocks appear here once they have a note. Link them by typing [[ in a note, or by giving them the same tags."
                )
            } else {
                GeometryReader { geometry in
                    canvas(in: geometry.size)
                        .contentShape(Rectangle())
                        .gesture(panAndZoom)
                        .onTapGesture { location in
                            if let id = node(at: location, in: geometry.size), let block = library.blocks.first(where: { $0.id == id }) {
                                onOpen(block)
                            }
                        }
                        .onContinuousHover { phase in
                            switch phase {
                            case .active(let location): hovered = node(at: location, in: geometry.size)
                            case .ended: hovered = nil
                            }
                        }
                }
                .overlay(alignment: .topTrailing) { controls }
                .overlay(alignment: .bottomLeading) { legend }
            }
        }
        .task(id: library.revision) {
            let latest = GraphData(blocks: library.library, links: library.linkIndex, collections: library.collections)
            guard latest != data else { return }
            data = latest
            positions = await GraphLayout.compute(latest)
        }
    }

    // MARK: Drawing

    private func screenPoint(_ unit: CGPoint, in size: CGSize) -> CGPoint {
        let side = min(size.width, size.height)
        return CGPoint(
            x: size.width / 2 + (unit.x - 0.5) * side * zoom + pan.width,
            y: size.height / 2 + (unit.y - 0.5) * side * zoom + pan.height
        )
    }

    private func radius(of id: Block.ID) -> CGFloat {
        let degree = (library.linkIndex.outgoing[id]?.count ?? 0) + (library.linkIndex.backlinks[id]?.count ?? 0)
        return 5 + CGFloat(min(degree, 8))
    }

    private func canvas(in size: CGSize) -> some View {
        let blocksByID = Dictionary(uniqueKeysWithValues: library.blocks.map { ($0.id, $0) })
        return Canvas { context, size in
            // Lines first, so dots sit on top.
            for edge in data.edges {
                if edge.kind == .shared && !showShared { continue }
                guard let from = positions[edge.a], let to = positions[edge.b] else { continue }
                var path = Path()
                path.move(to: screenPoint(from, in: size))
                path.addLine(to: screenPoint(to, in: size))
                let touchesHover = hovered == edge.a || hovered == edge.b
                switch edge.kind {
                case .link:
                    context.stroke(path, with: .color(touchesHover ? .accentColor : .primary.opacity(0.5)), lineWidth: touchesHover ? 2 : 1.3)
                case .shared:
                    context.stroke(path, with: .color(touchesHover ? .accentColor.opacity(0.7) : .primary.opacity(0.18)), style: StrokeStyle(lineWidth: 1, dash: [3, 4]))
                }
            }

            let labelAll = data.nodes.count <= 40 || zoom > 1.6
            for id in data.nodes {
                guard let unit = positions[id], let block = blocksByID[id] else { continue }
                let center = screenPoint(unit, in: size)
                let r = radius(of: id)
                let dot = Path(ellipseIn: CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2))
                context.fill(dot, with: .color(Self.color(for: block.kind)))
                if hovered == id {
                    context.stroke(dot, with: .color(.accentColor), lineWidth: 2.5)
                }
                if labelAll || hovered == id {
                    let title = block.title.isEmpty ? block.kind.rawValue : block.title
                    context.draw(
                        Text(title).font(.caption).foregroundStyle(hovered == id ? Color.primary : Color.secondary),
                        at: CGPoint(x: center.x, y: center.y + r + 4),
                        anchor: .top
                    )
                }
            }
        }
    }

    private func node(at location: CGPoint, in size: CGSize) -> Block.ID? {
        var best: (id: Block.ID, distance: CGFloat)?
        for id in data.nodes {
            guard let unit = positions[id] else { continue }
            let point = screenPoint(unit, in: size)
            let distance = hypot(point.x - location.x, point.y - location.y)
            if distance <= radius(of: id) + 6, distance < (best?.distance ?? .infinity) {
                best = (id, distance)
            }
        }
        return best?.id
    }

    // MARK: Gestures and chrome

    private var panAndZoom: some Gesture {
        SimultaneousGesture(
            DragGesture(minimumDistance: 4)
                .onChanged { pan = CGSize(width: basePan.width + $0.translation.width, height: basePan.height + $0.translation.height) }
                .onEnded { _ in basePan = pan },
            MagnifyGesture()
                .onChanged { zoom = min(max(baseZoom * $0.magnification, 0.4), 6) }
                .onEnded { _ in baseZoom = zoom }
        )
    }

    private var controls: some View {
        HStack(spacing: 12) {
            Toggle("Show shared tags and sites", isOn: $showShared)
                .toggleStyle(.checkbox)
            Button("Reset View", systemImage: "arrow.counterclockwise") {
                zoom = 1; baseZoom = 1; pan = .zero; basePan = .zero
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.plain)
        }
        .font(.callout)
        .padding(12)
    }

    private var legend: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("Linked with [[ ]]", systemImage: "line.diagonal")
            Label("Shared tag, site or collection", systemImage: "ellipsis")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(12)
    }

    private static func color(for kind: BlockKind) -> Color {
        switch kind {
        case .image: .orange
        case .link, .post: .blue
        case .quote: .purple
        case .text: .gray
        case .list: .teal
        case .color: .pink
        case .type: .indigo
        case .file: .brown
        }
    }
}
