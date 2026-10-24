import SwiftUI

/// Warm paper tone for the editorial content area.
extension Color {
    static func paper(_ scheme: ColorScheme) -> Color {
        scheme == .dark ? Color(red: 0.14, green: 0.13, blue: 0.12) : Color(red: 0.98, green: 0.96, blue: 0.92)
    }
}

/// One block in the gallery. Each kind has its own look; the first line of the
/// "why" sits underneath like a museum wall label.
struct BlockCard: View {
    let block: Block
    let imageURL: URL?

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            artifact
            if let label = block.wallLabel {
                Text(label)
                    .font(.system(.caption, design: .serif))
                    .italic()
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        // Unreflected blocks look faded until they get a "why".
        .opacity(block.isReflected ? 1 : 0.65)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var artifact: some View {
        switch block.kind {
        case .image:
            LocalImage(url: imageURL)
                .clipShape(RoundedRectangle(cornerRadius: 10))
        case .quote:
            paperCard {
                Text("“\(block.title)”")
                    .font(.system(.title3, design: .serif))
                    .lineLimit(8)
            }
        case .link, .post:
            VStack(alignment: .leading, spacing: 6) {
                if imageURL != nil {
                    LocalImage(url: imageURL).clipShape(RoundedRectangle(cornerRadius: 8))
                }
                if let domain = block.sourceDomain {
                    Text(domain.uppercased())
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                }
                Text(block.title.isEmpty ? (block.url?.absoluteString ?? "Untitled") : block.title)
                    .font(.headline)
                    .lineLimit(3)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.background.secondary, in: RoundedRectangle(cornerRadius: 10))
        case .text:
            paperCard {
                Text(block.title)
                    .font(.system(.body, design: .serif))
                    .lineLimit(10)
            }
        case .list, .color, .type, .file:
            paperCard {
                Label(block.title.isEmpty ? block.kind.rawValue.capitalized : block.title, systemImage: "square.stack")
                    .font(.headline)
            }
        }
    }

    private func paperCard<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.paper(colorScheme), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.quaternary))
    }
}
