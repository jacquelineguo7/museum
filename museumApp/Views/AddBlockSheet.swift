import SwiftUI
import UniformTypeIdentifiers

/// Quick capture. Whatever you add lands in the Inbox until you write a note about it.
struct AddBlockSheet: View {
    @Environment(LibraryModel.self) private var library
    @Environment(\.dismiss) private var dismiss

    @State private var text = ""
    @State private var imageURL: URL?
    @State private var isChoosingImage = false

    private var canSave: Bool {
        imageURL != nil || !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Save to Inbox").font(.headline)

            TextField("Paste a link, quote or thought", text: $text, axis: .vertical)
                .lineLimit(3...8)
                .textFieldStyle(.roundedBorder)

            HStack {
                Button("Choose Image…", systemImage: "photo") { isChoosingImage = true }
                if let imageURL {
                    Text(imageURL.lastPathComponent).foregroundStyle(.secondary).lineLimit(1)
                }
            }

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canSave)
            }
        }
        .padding(20)
        .frame(width: 440)
        .fileImporter(isPresented: $isChoosingImage, allowedContentTypes: [.image]) { result in
            if case .success(let url) = result { imageURL = url }
        }
    }

    private func save() {
        let input = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let imageURL = imageURL
        Task {
            if let imageURL {
                let didAccess = imageURL.startAccessingSecurityScopedResource()
                defer { if didAccess { imageURL.stopAccessingSecurityScopedResource() } }
                if let data = try? Data(contentsOf: imageURL) {
                    let title = input.isEmpty ? imageURL.deletingPathExtension().lastPathComponent : input
                    await library.add(Block(kind: .image, title: title), imageData: data, imageExtension: imageURL.pathExtension.lowercased())
                } else {
                    library.errorMessage = "Couldn't read that image."
                    return
                }
            } else {
                await library.add(Self.makeBlock(from: input))
            }
            dismiss()
        }
    }

    /// Guesses what kind of block the pasted text should be.
    static func makeBlock(from input: String) -> Block {
        if !input.contains(where: \.isWhitespace),
           let url = URL(string: input), let scheme = url.scheme?.lowercased(),
           ["http", "https"].contains(scheme), let host = url.host() {
            let domain = host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
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
