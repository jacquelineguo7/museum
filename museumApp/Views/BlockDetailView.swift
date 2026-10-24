import SwiftUI

/// Opens a block. Shows the read-only preview (artifact first, your notes underneath),
/// and swaps to the `BlockEditor` form when you edit. Blocks still waiting in the
/// Inbox open straight into the editor so you can say why you saved them.
struct BlockDetailView: View {
    let block: Block
    let onWander: () -> Void

    @Environment(LibraryModel.self) private var library
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    @State private var isEditing: Bool
    @State private var notesExpanded = false
    @State private var isConfirmingDelete = false

    init(block: Block, onWander: @escaping () -> Void = {}) {
        self.block = block
        self.onWander = onWander
        _isEditing = State(initialValue: !block.isReflected)
    }

    /// The latest saved version, so the preview updates after an edit.
    private var current: Block {
        library.blocks.first { $0.id == block.id } ?? block
    }

    var body: some View {
        Group {
            if isEditing {
                BlockEditor(existing: current, onFinish: { isEditing = false })
            } else {
                preview
            }
        }
        .confirmationDialog("Delete this block?", isPresented: $isConfirmingDelete) {
            Button("Move to Trash", role: .destructive) {
                Task {
                    await library.delete(current)
                    dismiss()
                }
            }
        } message: {
            Text("Its folder is moved to the Trash, so you can still get it back.")
        }
    }

    // MARK: Preview

    private var preview: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    artifact
                    notes
                    footer
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(minWidth: 640, idealWidth: 760, minHeight: 580, idealHeight: 680)
        .background(Color.paper(colorScheme))
    }

    private var toolbar: some View {
        HStack(spacing: 14) {
            Text(current.title)
                .font(.system(.headline, design: .serif))
                .lineLimit(1)
            Spacer()
            Menu("Collections", systemImage: "rectangle.stack") {
                if library.collections.isEmpty { Text("No collections yet") }
                ForEach(library.collections) { collection in
                    Toggle(collection.name, isOn: Binding(
                        get: { collection.blockIDs.contains(block.id) },
                        set: { _ in Task { await library.toggle(block, in: collection) } }
                    ))
                }
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            Button("Edit", systemImage: "pencil") { isEditing = true }
            Button("Wander", systemImage: "dice", action: onWander)
            Button("Delete", systemImage: "trash") { isConfirmingDelete = true }
            Button("Done") { dismiss() }
                .keyboardShortcut(.defaultAction)
        }
        .labelStyle(.iconOnly)
        .padding(12)
    }

    @ViewBuilder
    private var artifact: some View {
        let imageURL = library.assetURL(for: current)
        switch current.kind {
        case .image:
            LocalImage(url: imageURL, maxPixelSize: 2400)
        case .quote:
            Text("“\(current.title)”")
                .font(.system(.largeTitle, design: .serif))
                .padding(.vertical, 12)
        case .link, .post:
            VStack(alignment: .leading, spacing: 10) {
                if imageURL != nil { LocalImage(url: imageURL) }
                if let domain = current.sourceDomain {
                    Text(domain.uppercased()).font(.caption.weight(.medium)).foregroundStyle(.secondary)
                }
                Text(current.title).font(.system(.title2, design: .serif))
                if let url = current.url {
                    Link(url.absoluteString, destination: url).font(.callout).lineLimit(2)
                }
            }
        case .text, .list, .color, .type, .file:
            Text(current.title).font(.system(.title2, design: .serif))
        }
    }

    @ViewBuilder
    private var notes: some View {
        let text = current.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty {
            Button("Add a note about why this matters…", systemImage: "square.and.pencil") { isEditing = true }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
        } else {
            // Collapsed to a few lines so the artifact stays the focus.
            let isLong = text.count > 240 || text.filter(\.isNewline).count >= 4
            VStack(alignment: .leading, spacing: 6) {
                Text(text)
                    .font(.system(.body, design: .serif))
                    .lineLimit(notesExpanded ? nil : 4)
                    .textSelection(.enabled)
                if isLong {
                    Button(notesExpanded ? "Show less" : "Show more") { notesExpanded.toggle() }
                        .buttonStyle(.plain)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private var footer: some View {
        if !current.tags.isEmpty {
            Text(current.tags.map { "#\($0)" }.joined(separator: "  "))
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }
}
