import Foundation

/// Converts blocks and collections to and from markdown files with a small
/// YAML-style frontmatter. Every value is a JSON literal (valid YAML), and the
/// parser also accepts plain unquoted values so files can be edited by hand.
nonisolated enum BlockMarkdown {
    // MARK: Blocks

    static func render(_ block: Block) -> String {
        var fields: [(String, String)] = [
            ("id", block.id.uuidString),
            ("kind", block.kind.rawValue),
            ("title", literal(block.title)),
        ]
        if let url = block.url { fields.append(("url", literal(url.absoluteString))) }
        if let domain = block.sourceDomain { fields.append(("source", literal(domain))) }
        fields.append(("created", block.createdAt.formatted(.iso8601)))
        if let surfaced = block.lastSurfacedAt { fields.append(("surfaced", surfaced.formatted(.iso8601))) }
        if let asset = block.assetFilename { fields.append(("image", literal(asset))) }
        fields.append(("tags", literal(block.tags)))
        return join(fields: fields, body: block.notes)
    }

    static func parse(_ text: String) -> Block? {
        let (fields, body) = split(text)
        let url = fields["url"].flatMap { URL(string: string($0)) }
        let kind = fields["kind"].flatMap { BlockKind(rawValue: string($0)) } ?? (url == nil ? .text : .link)
        var block = Block(kind: kind)
        if let id = fields["id"].flatMap({ UUID(uuidString: string($0)) }) { block.id = id }
        block.title = fields["title"].map(string) ?? ""
        block.url = url
        block.sourceDomain = fields["source"].map(string)
        if let created = fields["created"].flatMap({ try? Date($0, strategy: .iso8601) }) { block.createdAt = created }
        block.lastSurfacedAt = fields["surfaced"].flatMap { try? Date($0, strategy: .iso8601) }
        block.assetFilename = fields["image"].map(string)
        block.tags = fields["tags"].map(stringList) ?? []
        block.notes = body
        return block
    }

    // MARK: Collections

    static func render(_ collection: BlockCollection) -> String {
        join(fields: [
            ("id", collection.id.uuidString),
            ("name", literal(collection.name)),
            ("blocks", literal(collection.blockIDs.map(\.uuidString))),
        ], body: collection.blurb)
    }

    static func parseCollection(_ text: String) -> BlockCollection? {
        let (fields, body) = split(text)
        guard let name = fields["name"].map(string) else { return nil }
        var collection = BlockCollection(name: name, blurb: body)
        if let id = fields["id"].flatMap({ UUID(uuidString: string($0)) }) { collection.id = id }
        collection.blockIDs = (fields["blocks"].map(stringList) ?? []).compactMap { UUID(uuidString: $0) }
        return collection
    }

    // MARK: Frontmatter

    static func join(fields: [(String, String)], body: String) -> String {
        let head = fields.map { "\($0.0): \($0.1)" }.joined(separator: "\n")
        return "---\n\(head)\n---\n\n\(body)"
    }

    /// Splits a file into frontmatter fields (raw values) and the markdown body.
    static func split(_ text: String) -> (fields: [String: String], body: String) {
        let text = text.replacingOccurrences(of: "\r\n", with: "\n")
        guard text.hasPrefix("---\n"),
              let end = text.range(of: "\n---", range: text.index(text.startIndex, offsetBy: 3)..<text.endIndex)
        else { return ([:], text) }

        var fields: [String: String] = [:]
        for line in text[text.index(text.startIndex, offsetBy: 4)..<end.lowerBound].split(separator: "\n") {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let key = line[..<colon].trimmingCharacters(in: .whitespaces)
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            fields[key] = value
        }
        var body = String(text[end.upperBound...])
        if let newline = body.firstIndex(of: "\n") { body = String(body[body.index(after: newline)...]) } else { body = "" }
        while body.hasPrefix("\n") { body.removeFirst() }
        return (fields, body)
    }

    // MARK: Values

    private static func literal<T: Encodable>(_ value: T) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .withoutEscapingSlashes
        guard let data = try? encoder.encode(value) else { return "\"\"" }
        return String(decoding: data, as: UTF8.self)
    }

    /// Reads a quoted JSON string, or falls back to the raw text.
    private static func string(_ raw: String) -> String {
        if raw.hasPrefix("\""), let value = try? JSONDecoder().decode(String.self, from: Data(raw.utf8)) {
            return value
        }
        return raw
    }

    /// Reads `["a", "b"]`, or a hand-written `[a, b]` / `a, b`.
    private static func stringList(_ raw: String) -> [String] {
        if let list = try? JSONDecoder().decode([String].self, from: Data(raw.utf8)) { return list }
        return raw.trimmingCharacters(in: CharacterSet(charactersIn: "[] "))
            .split(separator: ",")
            .map { string($0.trimmingCharacters(in: .whitespaces)) }
            .filter { !$0.isEmpty }
    }
}
