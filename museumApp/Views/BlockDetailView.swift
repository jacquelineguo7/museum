import SwiftUI

/// The artifact on top, your notes underneath. Edits are saved when the sheet closes.
struct BlockDetailView: View {
    let block: Block
    let onWander: () -> Void

    @Environment(LibraryModel.self) private var library
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme

    @State private var draft: Block
    @State private var tagsText: String
    @State private var isEditingNotes: Bool
    @State private var isConfirmingDelete = false
    @State private var wasDeleted = false
    @State private var prompt = Self.prompts.randomElement() ?? ""
    @FocusState private var notesFocused: Bool

    private static let prompts = [
        "What made you stop scrolling?",
        "What would you steal from this?",
        "What feeling does it give you?",
        "Why does this matter to you right now?",
        "What does it remind you of?",
    ]

    init(block: Block, onWander: @escaping () -> Void = {}) {
        self.block = block
        self.onWander = onWander
        _draft = State(initialValue: block)
        _tagsText = State(initialValue: block.tags.joined(separator: ", "))
        // Blocks still waiting for a "why" open ready to write.
        _isEditingNotes = State(initialValue: !block.isReflected)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            ScrollView { artifact.padding(20).frame(maxWidth: .infinity) }
            Divider()
            notes
        }
        .frame(minWidth: 640, idealWidth: 760, minHeight: 580, idealHeight: 680)
        .background(Color.paper(colorScheme))
        .onAppear { notesFocused = isEditingNotes }
        .onDisappear(perform: save)
        .confirmationDialog("Delete this block?", isPresented: $isConfirmingDelete) {
            Button("Move to Trash", role: .destructive) {
                wasDeleted = true
                Task {
                    await library.delete(block)
                    dismiss()
                }
            }
        } message: {
            Text("Its folder is moved to the Trash, so you can still get it back.")
        }
    }

    // MARK: Header

    private var header: some View {
        HStack {
            TextField("Title", text: $draft.title)
                .textFieldStyle(.plain)
                .font(.system(.title3, design: .serif))
            Menu("Collections", systemImage: "rectangle.stack") {
                if library.collections.isEmpty {
                    Text("No collections yet")
                }
                ForEach(library.collections) { collection in
                    Toggle(collection.name, isOn: Binding(
                        get: { collection.blockIDs.contains(block.id) },
                        set: { _ in Task { await library.toggle(block, in: collection) } }
                    ))
                }
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            Button("Wander", systemImage: "dice") {
                save()
                onWander()
            }
            Button("Delete", systemImage: "trash") { isConfirmingDelete = true }
            Button("Done") { dismiss() }
                .keyboardShortcut(.defaultAction)
        }
        .labelStyle(.iconOnly)
        .padding(12)
    }

    // MARK: Artifact

    @ViewBuilder
    private var artifact: some View {
        switch draft.kind {
        case .image:
            LocalImage(url: library.assetURL(for: draft), maxPixelSize: 2400)
        case .quote:
            Text("“\(draft.title)”")
                .font(.system(.largeTitle, design: .serif))
                .multilineTextAlignment(.leading)
                .padding(.vertical, 20)
        case .link, .post:
            VStack(alignment: .leading, spacing: 10) {
                if library.assetURL(for: draft) != nil {
                    LocalImage(url: library.assetURL(for: draft))
                }
                if let domain = draft.sourceDomain {
                    Text(domain.uppercased()).font(.caption.weight(.medium)).foregroundStyle(.secondary)
                }
                if let url = draft.url {
                    Link(url.absoluteString, destination: url).lineLimit(2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        case .text, .list, .color, .type, .file:
            Text(draft.title)
                .font(.system(.title2, design: .serif))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: Notes

    private var notes: some View {
        VStack(alignment: .leading, spacing: 10) {
            if isEditingNotes {
                ZStack(alignment: .topLeading) {
                    TextEditor(text: $draft.notes)
                        .font(.system(.body, design: .serif))
                        .scrollContentBackground(.hidden)
                        .focused($notesFocused)
                        .frame(minHeight: 110, maxHeight: 200)
                    if draft.notes.isEmpty {
                        Text(prompt)
                            .font(.system(.body, design: .serif))
                            .italic()
                            .foregroundStyle(.tertiary)
                            .padding(.leading, 5)
                            .allowsHitTesting(false)
                    }
                }
            } else {
                // Collapsed to a few lines so the artifact stays the focus.
                Button {
                    isEditingNotes = true
                    notesFocused = true
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(draft.notes)
                            .font(.system(.body, design: .serif))
                            .lineLimit(4)
                            .multilineTextAlignment(.leading)
                        Text("Edit notes").font(.caption).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
            }

            HStack {
                Image(systemName: "tag").foregroundStyle(.secondary)
                TextField("Tags, separated by commas", text: $tagsText)
                    .textFieldStyle(.plain)
            }
            .font(.callout)
        }
        .padding(16)
    }

    // MARK: Saving

    private func save() {
        guard !wasDeleted else { return }
        var updated = draft
        updated.tags = tagsText.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard updated != block else { return }
        Task { await library.update(updated) }
    }
}
