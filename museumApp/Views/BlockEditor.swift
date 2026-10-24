import SwiftUI
import ImageIO
import UniformTypeIdentifiers

/// The form for saving something new or editing a block later. Deliberately looks
/// like a form, unlike the editorial preview in `BlockDetailView`.
///
/// Leave the note empty and the block waits in the Inbox to be reflected on later.
struct BlockEditor: View {
    /// The block being edited, or nil when saving something new.
    let existing: Block?
    /// Called after saving or cancelling an edit. (New blocks just dismiss the sheet.)
    var onFinish: () -> Void = {}

    @Environment(LibraryModel.self) private var library
    @Environment(\.dismiss) private var dismiss

    @State private var content: String   // pasted link, quote or thought (new blocks)
    @State private var title: String     // title, or the text itself for quotes and thoughts (edits)
    @State private var urlText: String
    @State private var notes: String
    @State private var tagsText: String
    @State private var pendingImage: CapturedImage?
    @State private var isChoosingImage = false
    @State private var prompt = Self.prompts.randomElement() ?? ""
    @FocusState private var focus: Field?

    private enum Field { case content, notes }

    private static let prompts = [
        "What made you stop scrolling?",
        "What would you steal from this?",
        "What feeling does it give you?",
        "Why does this matter to you right now?",
        "What does it remind you of?",
    ]

    /// - Parameter captured: something dropped onto the window, to prefill a new entry with.
    init(existing: Block? = nil, captured: CapturedContent? = nil, onFinish: @escaping () -> Void = {}) {
        self.existing = existing
        self.onFinish = onFinish
        switch captured {
        case .text(let text): _content = State(initialValue: text)
        case .image(let image): _content = State(initialValue: ""); _pendingImage = State(initialValue: image)
        case nil: _content = State(initialValue: "")
        }
        _title = State(initialValue: existing?.title ?? "")
        _urlText = State(initialValue: existing?.url?.absoluteString ?? "")
        _notes = State(initialValue: existing?.notes ?? "")
        _tagsText = State(initialValue: existing?.tags.joined(separator: ", ") ?? "")
    }

    private var hasNote: Bool {
        !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !(existing?.annotations.isEmpty ?? true)
    }

    private var canSave: Bool {
        if existing != nil { return true }
        return pendingImage != nil || !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section(existing == nil ? "What are you saving?" : "Details") {
                    if let existing {
                        detailFields(for: existing)
                    } else {
                        newFields
                    }
                }

                Section {
                    ZStack(alignment: .topLeading) {
                        TextEditor(text: $notes)
                            .font(.system(.body, design: .serif))
                            .scrollContentBackground(.hidden)
                            .focused($focus, equals: .notes)
                            .frame(minHeight: 120)
                        if notes.isEmpty {
                            Text(prompt)
                                .font(.system(.body, design: .serif))
                                .italic()
                                .foregroundStyle(.tertiary)
                                .padding(.leading, 5)
                                .allowsHitTesting(false)
                        }
                    }
                } header: {
                    Text("Why does this matter?")
                } footer: {
                    Text("Leave this empty to keep it in your Inbox and come back to it later.")
                }

                Section("Tags") {
                    TextField("Tags", text: $tagsText, prompt: Text("typography, swiss, grids"))
                        .labelsHidden()
                }
            }
            .formStyle(.grouped)

            Divider()
            HStack {
                if !hasNote {
                    Label("Will go to Inbox", systemImage: "tray")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Cancel", role: .cancel, action: cancel)
                    .keyboardShortcut(.cancelAction)
                Button(hasNote ? "Save" : "Save to Inbox", action: save)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canSave)
            }
            .padding(12)
        }
        .frame(minWidth: 500, idealWidth: 540, minHeight: 540)
        .onAppear { focus = existing == nil ? .content : .notes }
        .fileImporter(isPresented: $isChoosingImage, allowedContentTypes: [.image]) { result in
            if case .success(let url) = result { loadImage(from: url) }
        }
    }

    // MARK: Fields

    @ViewBuilder
    private var newFields: some View {
        TextField("Link, quote or thought", text: $content, prompt: Text("Paste a link, quote or thought"), axis: .vertical)
            .lineLimit(2...6)
            .focused($focus, equals: .content)
        if let pendingImage {
            HStack(alignment: .top) {
                if let thumbnail = Self.thumbnail(from: pendingImage.data) {
                    thumbnail.resizable().scaledToFit().frame(maxHeight: 120).clipShape(RoundedRectangle(cornerRadius: 6))
                }
                Spacer()
                Button("Remove Image", systemImage: "xmark.circle.fill") { self.pendingImage = nil }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
            }
        } else {
            Button("Choose Image…", systemImage: "photo") { isChoosingImage = true }
        }
    }

    @ViewBuilder
    private func detailFields(for block: Block) -> some View {
        switch block.kind {
        case .link, .post:
            TextField("Title", text: $title)
            TextField("URL", text: $urlText)
        case .image, .file:
            TextField("Title", text: $title)
        case .quote, .text, .list, .color, .type:
            TextField("Text", text: $title, axis: .vertical).lineLimit(2...8)
        }
    }

    // MARK: Actions

    private var parsedTags: [String] {
        tagsText.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    private func cancel() {
        existing == nil ? dismiss() : onFinish()
    }

    private func save() {
        Task {
            if let existing {
                await library.update(updated(existing))
                onFinish()
            } else if await addNew() {
                dismiss()
            }
        }
    }

    private func updated(_ block: Block) -> Block {
        var block = block
        block.title = title
        block.notes = notes
        block.tags = parsedTags
        if block.kind == .link || block.kind == .post {
            let url = URL(string: urlText.trimmingCharacters(in: .whitespacesAndNewlines))
            block.url = url
            block.sourceDomain = url?.host().map(Self.stripWWW)
        }
        return block
    }

    private func addNew() async -> Bool {
        let input = content.trimmingCharacters(in: .whitespacesAndNewlines)
        if let pendingImage {
            var block = Block(kind: .image, title: input.isEmpty ? pendingImage.name : input)
            block.notes = notes
            block.tags = parsedTags
            await library.add(block, imageData: pendingImage.data, imageExtension: pendingImage.fileExtension)
        } else {
            var block = Self.makeBlock(from: input)
            block.notes = notes
            block.tags = parsedTags
            await library.add(block)
        }
        return true
    }

    private func loadImage(from url: URL) {
        let didAccess = url.startAccessingSecurityScopedResource()
        defer { if didAccess { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else {
            library.errorMessage = "Couldn't read that image."
            return
        }
        pendingImage = CapturedImage(data: data, name: url.deletingPathExtension().lastPathComponent, fileExtension: url.pathExtension.lowercased())
    }

    private static func thumbnail(from data: Data) -> Image? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 480,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary).map { Image(decorative: $0, scale: 1) }
    }

    private nonisolated static func stripWWW(_ host: String) -> String {
        host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    /// Guesses what kind of block the pasted text should be.
    static func makeBlock(from input: String) -> Block {
        if !input.contains(where: \.isWhitespace),
           let url = URL(string: input), let scheme = url.scheme?.lowercased(),
           ["http", "https"].contains(scheme), let host = url.host() {
            let domain = stripWWW(host)
            return Block(kind: .link, title: domain, url: url, sourceDomain: domain)
        }
        let quotes: [(Character, Character)] = [("“", "”"), ("\"", "\""), ("«", "»")]
        if let first = input.first, let last = input.last, input.count > 2,
           quotes.contains(where: { $0.0 == first && $0.1 == last }) {
            return Block(kind: .quote, title: String(input.dropFirst().dropLast()))
        }
        return Block(kind: .text, title: input)
    }
}
