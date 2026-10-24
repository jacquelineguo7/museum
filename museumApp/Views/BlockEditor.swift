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
    @State private var annotations: [Annotation]
    @State private var tool: AnnotationTool?
    @State private var showMarks = true
    @State private var notesSelection: TextSelection?
    @State private var isPickingLink = false
    @State private var linkTypedAsBrackets = false
    @State private var suggestedTags: [String] = []
    @State private var isSuggesting = false
    @State private var suggestionMessage: String?
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
        _annotations = State(initialValue: existing?.annotations ?? [])
    }

    private var hasNote: Bool {
        !notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !annotations.isEmpty
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

                marksSection

                Section {
                    ZStack(alignment: .topLeading) {
                        TextEditor(text: $notes, selection: $notesSelection)
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
                    HStack {
                        Text("Why does this matter?")
                        Spacer()
                        Button("Link", systemImage: "link") { isPickingLink = true }
                            .keyboardShortcut("k")
                            .help("Link to another block (⌘K, or type [[)")
                            .popover(isPresented: $isPickingLink, arrowEdge: .bottom) {
                                LinkPicker(excluding: existing?.id, onPick: insertLink)
                            }
                    }
                } footer: {
                    Text("Leave this empty to keep it in your Inbox and come back to it later.")
                }

                Section {
                    HStack {
                        TextField("Tags", text: $tagsText, prompt: Text("typography, swiss, grids"))
                            .labelsHidden()
                        Button(isSuggesting ? "Thinking…" : "Suggest", systemImage: "sparkles", action: suggestTags)
                            .disabled(isSuggesting || !canSave)
                    }
                    if !suggestedTags.isEmpty {
                        // Tap a suggestion to add it.
                        HStack {
                            ForEach(suggestedTags, id: \.self) { tag in
                                Button("+ \(tag)") { accept(tag) }
                                    .buttonStyle(.link)
                            }
                        }
                    }
                } header: {
                    Text("Tags")
                } footer: {
                    if let suggestionMessage { Text(suggestionMessage) }
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
        // Typing [[ at the end of the note opens the link picker.
        .onChange(of: notes) { _, text in
            if text.hasSuffix("[["), !isPickingLink {
                linkTypedAsBrackets = true
                isPickingLink = true
            }
        }
        .onChange(of: isPickingLink) { _, isShowing in
            if !isShowing { linkTypedAsBrackets = false; focus = .notes }
        }
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
                Button("Remove Image", systemImage: "xmark.circle.fill") { self.pendingImage = nil; annotations = []; tool = nil }
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

    // MARK: Marks on the image

    /// The saved image for an existing block, if it has one.
    private var existingImageURL: URL? {
        existing.flatMap { library.assetURL(for: $0) }
    }

    private var canMarkImage: Bool {
        pendingImage != nil || existingImageURL != nil
    }

    @ViewBuilder
    private var marksSection: some View {
        if canMarkImage {
            Section {
                AnnotatedImage(
                    url: pendingImage == nil ? existingImageURL : nil,
                    data: pendingImage?.data,
                    annotations: annotations,
                    tool: tool,
                    showMarks: showMarks,
                    onAddColor: { hex, point in
                        annotations.append(Annotation(payload: .color(hex: hex, name: nil, at: point)))
                    },
                    onAddLasso: { points in
                        annotations.append(Annotation(payload: .lasso(points: points)))
                    }
                )
                .frame(maxHeight: 380)
                .frame(maxWidth: .infinity)

                Picker("Tool", selection: $tool) {
                    Text("None").tag(AnnotationTool?.none)
                    ForEach(AnnotationTool.allCases) { Text($0.rawValue).tag(Optional($0)) }
                }
                .pickerStyle(.segmented)
                Toggle("Show marks", isOn: $showMarks)

                ForEach(annotations) { annotation in
                    markRow(annotation)
                }
            } header: {
                Text("Mark up the image")
            } footer: {
                switch tool {
                case .pin: Text("Click the image to save the color under your pointer.")
                case .lasso: Text("Drag around part of the image to outline it.")
                case nil: Text("Pick a tool, then click or drag on the image.")
                }
            }
        }
    }

    @ViewBuilder
    private func markRow(_ annotation: Annotation) -> some View {
        HStack {
            switch annotation.payload {
            case .color(let hex, _, _):
                Circle().fill(Color(hex: hex) ?? .clear).frame(width: 16, height: 16)
                    .overlay(Circle().strokeBorder(.secondary.opacity(0.4)))
                Text(hex).monospaced()
                TextField("Name", text: colorName(for: annotation.id), prompt: Text("Name this shade"))
                    .labelsHidden()
            case .lasso:
                Image(systemName: "lasso")
                Text("Region \(lassoNumber(of: annotation))")
                Spacer()
            case .highlight(let quote):
                Image(systemName: "highlighter")
                Text(quote).lineLimit(1)
                Spacer()
            case .typeface(let fontName, _):
                Image(systemName: "textformat")
                Text(fontName)
                Spacer()
            }
            Button("Remove Mark", systemImage: "trash") { annotations.removeAll { $0.id == annotation.id } }
                .labelStyle(.iconOnly)
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
        }
    }

    private func lassoNumber(of annotation: Annotation) -> Int {
        let lassos = annotations.filter { if case .lasso = $0.payload { true } else { false } }
        return (lassos.firstIndex { $0.id == annotation.id } ?? 0) + 1
    }

    private func colorName(for id: Annotation.ID) -> Binding<String> {
        Binding(
            get: {
                if case .color(_, let name, _)? = annotations.first(where: { $0.id == id })?.payload { name ?? "" } else { "" }
            },
            set: { newName in
                guard let index = annotations.firstIndex(where: { $0.id == id }),
                      case .color(let hex, _, let point) = annotations[index].payload else { return }
                annotations[index].payload = .color(hex: hex, name: newName.isEmpty ? nil : newName, at: point)
            }
        )
    }

    // MARK: Actions

    private var parsedTags: [String] {
        tagsText.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    /// The entry as it currently stands in the form, for asking the model about it.
    private var draftBlock: Block {
        if let existing { return updated(existing) }
        let input = content.trimmingCharacters(in: .whitespacesAndNewlines)
        var block = pendingImage.map { Block(kind: .image, title: input.isEmpty ? $0.name : input) } ?? Self.makeBlock(from: input)
        block.notes = notes
        block.annotations = annotations
        block.tags = parsedTags
        return block
    }

    private func suggestTags() {
        if case .unavailable(let reason) = Intelligence.status {
            suggestionMessage = reason
            return
        }
        isSuggesting = true
        suggestionMessage = nil
        let block = draftBlock
        Task {
            defer { isSuggesting = false }
            do {
                suggestedTags = try await Intelligence.suggestTags(for: block, knownTags: library.knownTags)
                if suggestedTags.isEmpty { suggestionMessage = "No new tag suggestions." }
            } catch {
                suggestionMessage = "Couldn't get suggestions: \(error.localizedDescription)"
            }
        }
    }

    private func accept(_ tag: String) {
        var tags = parsedTags
        if !tags.contains(tag) { tags.append(tag) }
        tagsText = tags.joined(separator: ", ")
        suggestedTags.removeAll { $0 == tag }
    }

    /// Inserts `[[Title]]` where you were typing: replacing a typed `[[`, at the cursor, or at the end.
    private func insertLink(to target: Block) {
        let link = "[[\(WikiLinks.linkText(for: target.title))]]"
        if linkTypedAsBrackets, notes.hasSuffix("[[") {
            notes.removeLast(2)
            notes += link
        } else if let selection = notesSelection, case .selection(let range) = selection.indices, range.upperBound <= notes.endIndex {
            notes.replaceSubrange(range, with: link)
        } else {
            if let last = notes.last, !last.isWhitespace { notes += " " }
            notes += link
        }
        isPickingLink = false
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
        block.annotations = annotations
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
            block.annotations = annotations
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
