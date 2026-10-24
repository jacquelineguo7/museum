import SwiftUI

enum AnnotationTool: String, CaseIterable, Identifiable {
    case pin = "Pin a color"
    case lasso = "Lasso"

    var id: String { rawValue }
}

/// An image with its marks drawn right on top: a colored dot where a shade was picked,
/// and a numbered outline around each lassoed region. Positions are stored as fractions of
/// the image, so the marks stay put at any size.
///
/// Pass a `tool` to make it interactive: click to pin a color, or drag to lasso a region.
struct AnnotatedImage: View {
    var url: URL?
    var data: Data?
    var annotations: [Annotation]
    var tool: AnnotationTool?
    var showMarks = true
    var maxPixelSize = 2400
    var onAddColor: (String, NormalizedPoint) -> Void = { _, _ in }
    var onAddLasso: ([NormalizedPoint]) -> Void = { _ in }

    @State private var image: CGImage?
    @State private var stroke: [NormalizedPoint] = []

    var body: some View {
        Group {
            if let image {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .scaledToFit()
                    // While annotating, marks always show so you can see what you're adding to.
                    .overlay { if showMarks || tool != nil { marks(for: image) } }
            } else {
                Rectangle().fill(.quaternary).frame(height: 160)
            }
        }
        .task(id: "\(url?.path ?? "")|\(data?.count ?? 0)") {
            if let url {
                image = await ImageLoading.thumbnail(at: url, maxPixelSize: maxPixelSize)
            } else if let data {
                image = await ImageLoading.thumbnail(from: data, maxPixelSize: maxPixelSize)
            } else {
                image = nil
            }
        }
    }

    // MARK: Marks

    private var lassos: [[NormalizedPoint]] {
        annotations.compactMap { if case .lasso(let points) = $0.payload { points } else { nil } }
    }

    private func marks(for image: CGImage) -> some View {
        GeometryReader { geometry in
            let size = geometry.size
            ZStack {
                Canvas { context, size in
                    func outline(_ points: [NormalizedPoint], closed: Bool) -> Path {
                        Path { path in
                            guard let first = points.first else { return }
                            path.move(to: CGPoint(x: first.x * size.width, y: first.y * size.height))
                            for point in points.dropFirst() { path.addLine(to: CGPoint(x: point.x * size.width, y: point.y * size.height)) }
                            if closed { path.closeSubpath() }
                        }
                    }
                    // A white edge under the colored line keeps it visible on any image.
                    for points in lassos {
                        let path = outline(points, closed: true)
                        context.stroke(path, with: .color(.white), style: StrokeStyle(lineWidth: 4.5, lineCap: .round, lineJoin: .round))
                        context.stroke(path, with: .color(.orange), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                    }
                    if !stroke.isEmpty {
                        let path = outline(stroke, closed: false)
                        context.stroke(path, with: .color(.white), style: StrokeStyle(lineWidth: 4.5, lineCap: .round, lineJoin: .round))
                        context.stroke(path, with: .color(.orange), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round, dash: [5, 4]))
                    }
                }
                .allowsHitTesting(false)

                // Catches clicks and drags while a tool is selected.
                Color.clear
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                guard tool == .lasso else { return }
                                let point = normalized(value.location, in: size)
                                if let last = stroke.last, hypot(last.x - point.x, last.y - point.y) < 0.008 { return }
                                stroke.append(point)
                            }
                            .onEnded { value in
                                switch tool {
                                case .pin:
                                    let point = normalized(value.location, in: size)
                                    if let hex = ImageSampler.hex(at: point, in: image) { onAddColor(hex, point) }
                                case .lasso:
                                    if stroke.count >= 3 { onAddLasso(stroke) }
                                    stroke = []
                                case nil:
                                    break
                                }
                            }
                    )
                    .allowsHitTesting(tool != nil)

                ForEach(Array(lassos.enumerated()), id: \.offset) { index, points in
                    if let first = points.first {
                        Text("\(index + 1)")
                            .font(.caption2.bold())
                            .foregroundStyle(.white)
                            .frame(width: 18, height: 18)
                            .background(.orange, in: Circle())
                            .overlay(Circle().strokeBorder(.white, lineWidth: 1.5))
                            .position(x: first.x * size.width, y: first.y * size.height)
                            .allowsHitTesting(false)
                    }
                }

                ForEach(annotations) { annotation in
                    if case .color(let hex, let name, let point) = annotation.payload, let color = Color(hex: hex) {
                        Circle()
                            .fill(color)
                            .frame(width: 22, height: 22)
                            .overlay(Circle().strokeBorder(.white, lineWidth: 2.5))
                            .shadow(color: .black.opacity(0.4), radius: 2)
                            .position(x: point.x * size.width, y: point.y * size.height)
                            .help([name, hex].compactMap { $0 }.joined(separator: " "))
                            .allowsHitTesting(tool == nil)
                    }
                }
            }
        }
    }

    private func normalized(_ location: CGPoint, in size: CGSize) -> NormalizedPoint {
        NormalizedPoint(
            x: min(max(location.x / max(size.width, 1), 0), 1),
            y: min(max(location.y / max(size.height, 1), 0), 1)
        )
    }
}

extension Color {
    /// Reads "#RRGGBB".
    init?(hex: String) {
        let digits = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard digits.count == 6, let value = UInt32(digits, radix: 16) else { return nil }
        self.init(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }
}
