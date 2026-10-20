import Foundation

public struct MarkdownListItem: Equatable, Sendable {
    public var text: String
    /// Nesting depth (two leading spaces per level).
    public var depth: Int
    /// nil for a plain item; true/false for a checklist item.
    public var checked: Bool?
    /// Zero-based line in the source, so a checkbox tap can edit the right line.
    public var line: Int
    /// The item's number for ordered lists.
    public var number: Int?

    public init(text: String, depth: Int = 0, checked: Bool? = nil, line: Int, number: Int? = nil) {
        self.text = text
        self.depth = depth
        self.checked = checked
        self.line = line
        self.number = number
    }
}

public enum MarkdownBlock: Equatable, Sendable {
    case heading(level: Int, text: String)
    case paragraph(String)
    case list(ordered: Bool, items: [MarkdownListItem])
    case quote(String)
    case code(language: String, text: String)
    case rule
    case table(header: [String], rows: [[String]])
}

/// A small, forgiving Markdown reader for notes: headings, paragraphs, bullet / numbered /
/// checklist items, quotes, fenced code, rules and simple tables. Inline styling (bold, italic,
/// code, links) is left to `AttributedString(markdown:)` in the UI.
public enum Markdown {
    public static func parse(_ source: String) -> [MarkdownBlock] {
        let lines = normalized(source).components(separatedBy: "\n")
        var blocks: [MarkdownBlock] = []
        var paragraph: [String] = []
        var i = 0

        func flushParagraph() {
            if !paragraph.isEmpty {
                blocks.append(.paragraph(paragraph.joined(separator: "\n")))
                paragraph = []
            }
        }

        while i < lines.count {
            let line = lines[i]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.isEmpty { flushParagraph(); i += 1; continue }

            if trimmed.hasPrefix("```") {
                flushParagraph()
                let language = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                var code: [String] = []
                i += 1
                while i < lines.count, !lines[i].trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                    code.append(lines[i])
                    i += 1
                }
                i += 1   // closing fence (or end of text)
                blocks.append(.code(language: language, text: code.joined(separator: "\n")))
                continue
            }

            if let heading = parseHeading(trimmed) {
                flushParagraph()
                blocks.append(.heading(level: heading.level, text: heading.text))
                i += 1
                continue
            }

            if isRule(trimmed) {
                flushParagraph()
                blocks.append(.rule)
                i += 1
                continue
            }

            if trimmed.hasPrefix(">") {
                flushParagraph()
                var quoted: [String] = []
                while i < lines.count {
                    let t = lines[i].trimmingCharacters(in: .whitespaces)
                    guard t.hasPrefix(">") else { break }
                    quoted.append(String(t.dropFirst()).trimmingCharacters(in: .init(charactersIn: " ")))
                    i += 1
                }
                blocks.append(.quote(quoted.joined(separator: "\n")))
                continue
            }

            if trimmed.contains("|"), i + 1 < lines.count, isTableSeparator(lines[i + 1]) {
                flushParagraph()
                let header = tableCells(trimmed)
                i += 2
                var rows: [[String]] = []
                while i < lines.count {
                    let t = lines[i].trimmingCharacters(in: .whitespaces)
                    guard !t.isEmpty, t.contains("|") else { break }
                    rows.append(tableCells(t))
                    i += 1
                }
                blocks.append(.table(header: header, rows: rows))
                continue
            }

            if parseListItem(line, index: i) != nil {
                flushParagraph()
                var items: [MarkdownListItem] = []
                var ordered = false
                while i < lines.count, let item = parseListItem(lines[i], index: i) {
                    if items.isEmpty { ordered = item.number != nil }
                    items.append(item)
                    i += 1
                }
                blocks.append(.list(ordered: ordered, items: items))
                continue
            }

            paragraph.append(trimmed)
            i += 1
        }
        flushParagraph()
        return blocks
    }

    /// Flips `- [ ]` ⇄ `- [x]` on the given source line. Other lines and non-checklist lines are untouched.
    public static func toggleChecklist(in source: String, line: Int) -> String {
        var lines = normalized(source).components(separatedBy: "\n")
        guard lines.indices.contains(line) else { return source }
        let original = lines[line]
        guard let range = original.range(of: #"\[( |x|X)\]"#, options: .regularExpression),
              parseListItem(original, index: line)?.checked != nil else { return source }
        let isChecked = original[range] != "[ ]"
        lines[line] = original.replacingCharacters(in: range, with: isChecked ? "[ ]" : "[x]")
        return lines.joined(separator: "\n")
    }

    /// Turns `[[Page title]]` into a link the preview can intercept.
    public static func expandWikiLinks(_ text: String) -> String {
        guard text.contains("[[") else { return text }
        var result = text
        let pattern = #"\[\[([^\[\]\n]+)\]\]"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).reversed()
        for match in matches {
            guard let whole = Range(match.range, in: result), let inner = Range(match.range(at: 1), in: result) else { continue }
            let title = String(result[inner]).trimmingCharacters(in: .whitespaces)
            let encoded = title.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? title
            result.replaceSubrange(whole, with: "[\(title)](\(wikiLinkScheme)://page/\(encoded))")
        }
        return result
    }

    public static let wikiLinkScheme = "kukit-note"

    /// The page title inside a `kukit-note://page/<title>` link, if it is one.
    public static func wikiLinkTitle(from url: URL) -> String? {
        guard url.scheme == wikiLinkScheme else { return nil }
        return url.pathComponents.dropFirst().joined(separator: "/").removingPercentEncoding
    }

    /// Titles referenced as `[[Title]]`, in order, without duplicates.
    public static func wikiLinkTitles(in text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: #"\[\[([^\[\]\n]+)\]\]"#) else { return [] }
        var seen = Set<String>()
        var titles: [String] = []
        for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            guard let range = Range(match.range(at: 1), in: text) else { continue }
            let title = String(text[range]).trimmingCharacters(in: .whitespaces)
            if !title.isEmpty, seen.insert(title.lowercased()).inserted { titles.append(title) }
        }
        return titles
    }

    /// A one-line preview of a note body for lists and search results.
    public static func snippet(_ source: String, maxLength: Int = 120) -> String {
        var text = ""
        for block in parse(source) {
            switch block {
            case .heading(_, let t), .paragraph(let t), .quote(let t): text += t + " "
            case .list(_, let items): text += items.map(\.text).joined(separator: " ") + " "
            case .code(_, let t): text += t + " "
            case .table(let header, let rows): text += (header + rows.flatMap { $0 }).joined(separator: " ") + " "
            case .rule: break
            }
            if text.count >= maxLength { break }
        }
        let flat = text.replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "**", with: "").replacingOccurrences(of: "`", with: "")
            .trimmingCharacters(in: .whitespaces)
        return flat.count > maxLength ? String(flat.prefix(maxLength)) + "…" : flat
    }

    // MARK: Parsing helpers

    static func normalized(_ source: String) -> String {
        source.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
    }

    private static func parseHeading(_ trimmed: String) -> (level: Int, text: String)? {
        var level = 0
        for ch in trimmed {
            if ch == "#" { level += 1 } else { break }
        }
        guard (1...6).contains(level) else { return nil }
        let rest = trimmed.dropFirst(level)
        guard rest.first == " " else { return rest.isEmpty ? (level, "") : nil }
        var text = rest.trimmingCharacters(in: .whitespaces)
        while text.hasSuffix("#") { text.removeLast() }
        return (level, text.trimmingCharacters(in: .whitespaces))
    }

    private static func isRule(_ trimmed: String) -> Bool {
        let stripped = trimmed.replacingOccurrences(of: " ", with: "")
        guard stripped.count >= 3, let first = stripped.first, "-*_".contains(first) else { return false }
        return stripped.allSatisfy { $0 == first }
    }

    private static func isTableSeparator(_ line: String) -> Bool {
        let t = line.trimmingCharacters(in: .whitespaces)
        guard t.contains("-"), t.contains("|") || t.contains(":") else { return false }
        return t.allSatisfy { "|-: ".contains($0) }
    }

    private static func tableCells(_ line: String) -> [String] {
        var t = line.trimmingCharacters(in: .whitespaces)
        if t.hasPrefix("|") { t.removeFirst() }
        if t.hasSuffix("|") { t.removeLast() }
        return t.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
    }

    static func parseListItem(_ line: String, index: Int) -> MarkdownListItem? {
        var spaces = 0
        var rest = Substring(line)
        while let first = rest.first, first == " " || first == "\t" {
            spaces += first == "\t" ? 4 : 1
            rest = rest.dropFirst()
        }
        var number: Int?
        if let first = rest.first, "-*+".contains(first) {
            rest = rest.dropFirst()
        } else {
            let digits = rest.prefix { $0.isNumber }
            guard !digits.isEmpty, digits.count <= 9, let value = Int(digits) else { return nil }
            rest = rest.dropFirst(digits.count)
            guard let mark = rest.first, mark == "." || mark == ")" else { return nil }
            rest = rest.dropFirst()
            number = value
        }
        guard rest.first == " " else { return nil }
        rest = rest.dropFirst()

        var checked: Bool?
        let body = rest.drop { $0 == " " }
        if body.hasPrefix("[ ]") || body.hasPrefix("[x]") || body.hasPrefix("[X]") {
            let after = body.dropFirst(3)
            if after.isEmpty || after.first == " " {
                checked = !body.hasPrefix("[ ]")
                return MarkdownListItem(text: after.trimmingCharacters(in: .whitespaces), depth: spaces / 2,
                                        checked: checked, line: index, number: number)
            }
        }
        return MarkdownListItem(text: body.trimmingCharacters(in: .whitespaces), depth: spaces / 2,
                                checked: nil, line: index, number: number)
    }
}
