import Foundation
import FoundationModels

@Generable
nonisolated struct TagSuggestions {
    @Guide(description: "Short lowercase topic tags of one or two words, such as 'typography' or 'calm interfaces'", .count(2...5))
    var tags: [String]
}

@Generable
nonisolated struct ConnectionSuggestion {
    @Guide(description: "The id of the related entry, copied exactly from the list")
    var id: String
    @Guide(description: "One short sentence naming the specific idea, technique or theme the two entries share")
    var reason: String
    @Guide(description: "How strong the connection is: 1 = vague or only loosely related, 5 = clearly about the same specific idea", .range(1...5))
    var strength: Int
}

@Generable
nonisolated struct ConnectionSuggestions {
    @Guide(description: "Entries that genuinely relate to this one. Leave empty if none really do.", .maximumCount(3))
    var related: [ConnectionSuggestion]
}

/// An existing block the on-device model thinks relates to another one.
struct RelatedSuggestion: Identifiable {
    var block: Block
    var reason: String
    var id: Block.ID { block.id }
}

/// Suggestions from Apple Intelligence's on-device model. Nothing leaves the Mac,
/// and nothing is applied until you accept it. It never writes your "why".
enum Intelligence {
    enum Status {
        case ready
        case unavailable(String)

        var isReady: Bool {
            if case .ready = self { true } else { false }
        }
    }

    static var status: Status {
        switch SystemLanguageModel.default.availability {
        case .available:
            .ready
        case .unavailable(.deviceNotEligible):
            .unavailable("This Mac doesn't support Apple Intelligence.")
        case .unavailable(.appleIntelligenceNotEnabled):
            .unavailable("Turn on Apple Intelligence in System Settings to get suggestions.")
        case .unavailable(.modelNotReady):
            .unavailable("The on-device model is still downloading. Try again soon.")
        case .unavailable:
            .unavailable("Apple Intelligence isn't available right now.")
        }
    }

    // MARK: Tags

    /// Suggests tags for an entry, reusing tags from the library where they fit.
    static func suggestTags(for block: Block, knownTags: [String]) async throws -> [String] {
        let session = LanguageModelSession(instructions: """
            You help someone organize a personal library of things that inspire them. \
            Suggest short, specific topic tags for the entry. Prefer reusing the existing tags \
            when they fit, and only add a new tag when none do.
            """)
        var prompt = "Entry:\n\(describe(block))"
        if !knownTags.isEmpty {
            prompt += "\n\nExisting tags in the library: \(knownTags.prefix(40).joined(separator: ", "))"
        }
        let response = try await session.respond(to: prompt, generating: TagSuggestions.self)

        let existing = Set(block.tags.map { $0.lowercased() })
        var seen = existing
        return response.content.tags
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "#"))).lowercased() }
            .filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    // MARK: Connections

    /// Finds entries in the library that relate to this one, with a one-line reason each.
    static func suggestConnections(for block: Block, among others: [Block]) async throws -> [RelatedSuggestion] {
        // The on-device model has a small context window, so only consider the newest entries.
        let candidates = others
            .filter { $0.id != block.id && $0.isReflected }
            .sorted { $0.createdAt > $1.createdAt }
            .prefix(25)
        guard !candidates.isEmpty else { return [] }

        let list = candidates.map { candidate in
            let tags = candidate.tags.isEmpty ? "" : " | tags: \(candidate.tags.joined(separator: ", "))"
            return "\(shortID(candidate)) | \(candidate.title.prefix(60))\(tags) | \(candidate.notes.prefix(100).replacingOccurrences(of: "\n", with: " "))"
        }.joined(separator: "\n")

        let session = LanguageModelSession(instructions: """
            You help someone find connections between things they have saved. \
            Pick entries from the list that share a real idea, theme, technique or feeling with the new entry. \
            Most entries will have no connection at all, and returning none is the right answer then. \
            Never connect entries just because both are about design, creativity or inspiration in general.
            """)
        let prompt = "New entry:\n\(describe(block))\n\nOther entries (id | title | tags | note):\n\(list)"
        let response = try await session.respond(to: prompt, generating: ConnectionSuggestions.self)

        return response.content.related.compactMap { suggestion in
            // The model tends to over-connect, so keep only the strong ones.
            guard suggestion.strength >= 5,
                  let match = candidates.first(where: { shortID($0) == suggestion.id.trimmingCharacters(in: .whitespaces) }) else { return nil }
            return RelatedSuggestion(block: match, reason: suggestion.reason)
        }
    }

    // MARK: Helpers

    private static func shortID(_ block: Block) -> String {
        String(block.id.uuidString.prefix(8)).lowercased()
    }

    private static func describe(_ block: Block) -> String {
        var lines = ["Kind: \(block.kind.rawValue)", "Title: \(block.title)"]
        if let domain = block.sourceDomain { lines.append("Site: \(domain)") }
        if !block.tags.isEmpty { lines.append("Tags: \(block.tags.joined(separator: ", "))") }
        let notes = block.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        if !notes.isEmpty { lines.append("Why it was saved: \(notes.prefix(600))") }
        return lines.joined(separator: "\n")
    }
}
