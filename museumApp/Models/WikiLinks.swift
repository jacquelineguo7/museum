import Foundation

/// `[[Title]]` links between blocks, written inside notes. `[[Title|label]]` shows `label` instead.
nonisolated enum WikiLinks {
    struct Match {
        var range: Range<String.Index>
        /// The block title being linked to.
        var target: String
        /// What to show in place of the link.
        var label: String
    }

    static func matches(in text: String) -> [Match] {
        guard let regex = try? Regex(#"\[\[([^\[\]|\n]+?)(?:\|([^\[\]\n]*))?\]\]"#) else { return [] }
        return text.matches(of: regex).compactMap { match in
            guard let target = match.output[1].substring?.trimmingCharacters(in: .whitespaces), !target.isEmpty else { return nil }
            let label = match.output[2].substring.map { $0.trimmingCharacters(in: .whitespaces) }
            return Match(range: match.range, target: target, label: label.flatMap { $0.isEmpty ? nil : $0 } ?? target)
        }
    }

    /// How a title is written inside `[[ ]]`: brackets and bars would break the link, so they become spaces.
    static func linkText(for title: String) -> String {
        title.map { "[]|\n".contains($0) ? " " : $0 }
            .reduce(into: "") { $0.append($1) }
            .trimmingCharacters(in: .whitespaces)
    }

    static func key(for title: String) -> String {
        linkText(for: title).lowercased()
    }
}

/// Who links to whom, built from the `[[links]]` in every block's notes.
nonisolated struct LinkIndex: Sendable {
    private(set) var outgoing: [Block.ID: [Block.ID]] = [:]
    private(set) var backlinks: [Block.ID: [Block.ID]] = [:]
    private var idsByTitle: [String: Block.ID] = [:]

    init(blocks: [Block] = []) {
        // If two blocks share a title, links go to the oldest one.
        for block in blocks.sorted(by: { $0.createdAt < $1.createdAt }) where !block.title.isEmpty {
            let key = WikiLinks.key(for: block.title)
            if idsByTitle[key] == nil { idsByTitle[key] = block.id }
        }
        for block in blocks {
            var seen = Set<Block.ID>()
            for match in WikiLinks.matches(in: block.notes) {
                guard let target = blockID(titled: match.target), target != block.id, seen.insert(target).inserted else { continue }
                outgoing[block.id, default: []].append(target)
                backlinks[target, default: []].append(block.id)
            }
        }
    }

    func blockID(titled title: String) -> Block.ID? {
        idsByTitle[WikiLinks.key(for: title)]
    }
}
