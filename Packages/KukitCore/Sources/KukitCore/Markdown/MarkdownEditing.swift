import Foundation

/// Pure text edits behind the editor's formatting buttons. Selections are Character offsets.
public enum MarkdownEditing {
    public struct Result: Equatable, Sendable {
        public var text: String
        public var selection: Range<Int>
    }

    /// Wraps the selection in `prefix`/`suffix` (bold, italic, code…), or removes them if already
    /// there. With no selection, inserts the markers around `placeholder` and selects it.
    public static func toggleWrap(_ text: String, selection: Range<Int>, prefix: String,
                                  suffix: String? = nil, placeholder: String = "text") -> Result {
        let suffix = suffix ?? prefix
        var chars = Array(text)
        let range = clamp(selection, count: chars.count)
        let before = Array(prefix), after = Array(suffix)

        // Already wrapped just outside the selection?
        if range.lowerBound >= before.count, range.upperBound + after.count <= chars.count,
           Array(chars[(range.lowerBound - before.count)..<range.lowerBound]) == before,
           Array(chars[range.upperBound..<(range.upperBound + after.count)]) == after {
            chars.removeSubrange(range.upperBound..<(range.upperBound + after.count))
            chars.removeSubrange((range.lowerBound - before.count)..<range.lowerBound)
            let start = range.lowerBound - before.count
            return Result(text: String(chars), selection: start..<(start + range.count))
        }

        if range.isEmpty {
            chars.insert(contentsOf: before + Array(placeholder) + after, at: range.lowerBound)
            let start = range.lowerBound + before.count
            return Result(text: String(chars), selection: start..<(start + placeholder.count))
        }

        chars.insert(contentsOf: after, at: range.upperBound)
        chars.insert(contentsOf: before, at: range.lowerBound)
        let start = range.lowerBound + before.count
        return Result(text: String(chars), selection: start..<(start + range.count))
    }

    /// Adds `prefix` to every line touched by the selection, or removes it when all of them have it.
    public static func toggleLinePrefix(_ text: String, selection: Range<Int>, prefix: String) -> Result {
        transformLines(text, selection: selection) { lines in
            let allHave = lines.allSatisfy { $0.hasPrefix(prefix) }
            return lines.map { line in
                if allHave { return String(line.dropFirst(prefix.count)) }
                return line.hasPrefix(prefix) ? line : prefix + stripListMarker(line)
            }
        }
    }

    /// Sets (or, if already that level, clears) a heading on the touched lines.
    public static func setHeading(_ text: String, selection: Range<Int>, level: Int) -> Result {
        let marker = String(repeating: "#", count: max(1, min(6, level))) + " "
        return transformLines(text, selection: selection) { lines in
            let allHave = lines.allSatisfy { $0.hasPrefix(marker) }
            return lines.map { line in
                let bare = stripHeading(line)
                return allHave ? bare : marker + bare
            }
        }
    }

    /// Indents or outdents the touched lines by two spaces.
    public static func shiftIndent(_ text: String, selection: Range<Int>, outdent: Bool) -> Result {
        transformLines(text, selection: selection) { lines in
            lines.map { line in
                if !outdent { return "  " + line }
                if line.hasPrefix("  ") { return String(line.dropFirst(2)) }
                if line.hasPrefix("\t") || line.hasPrefix(" ") { return String(line.dropFirst()) }
                return line
            }
        }
    }

    /// Return pressed at the end of a list item: continue the list (or end it on an empty item).
    /// Returns nil when the cursor isn't in a list line, so the editor handles Return normally.
    public static func continueList(_ text: String, cursor: Int) -> Result? {
        let chars = Array(text)
        let position = min(max(0, cursor), chars.count)
        var lineStart = position
        while lineStart > 0, chars[lineStart - 1] != "\n" { lineStart -= 1 }
        var lineEnd = position
        while lineEnd < chars.count, chars[lineEnd] != "\n" { lineEnd += 1 }
        guard lineEnd == position else { return nil }   // only at the end of the line
        let line = String(chars[lineStart..<lineEnd])
        guard let item = Markdown.parseListItem(line, index: 0) else { return nil }

        let indent = String(repeating: " ", count: item.depth * 2)
        if item.text.isEmpty {
            // An empty item ends the list.
            var updated = chars
            updated.replaceSubrange(lineStart..<lineEnd, with: [])
            return Result(text: String(updated), selection: lineStart..<lineStart)
        }
        let marker: String
        if let number = item.number {
            marker = "\(number + 1). "
        } else {
            marker = "- "
        }
        let box = item.checked != nil ? "[ ] " : ""
        let insertion = Array("\n" + indent + marker + box)
        var updated = chars
        updated.insert(contentsOf: insertion, at: position)
        let newCursor = position + insertion.count
        return Result(text: String(updated), selection: newCursor..<newCursor)
    }

    /// If `new` is `old` with exactly one newline typed in, returns the Character offset where it
    /// was typed (in `old`). Lets the editor react to Return even from a software keyboard.
    public static func insertedNewline(old: String, new: String) -> Int? {
        let oldChars = Array(old), newChars = Array(new)
        guard newChars.count == oldChars.count + 1 else { return nil }
        var prefix = 0
        while prefix < oldChars.count, oldChars[prefix] == newChars[prefix] { prefix += 1 }
        guard newChars[prefix] == "\n", Array(newChars[(prefix + 1)...]) == Array(oldChars[prefix...]) else { return nil }
        return prefix
    }

    // MARK: Helpers

    private static func clamp(_ range: Range<Int>, count: Int) -> Range<Int> {
        let lower = min(max(0, range.lowerBound), count)
        let upper = min(max(lower, range.upperBound), count)
        return lower..<upper
    }

    private static func transformLines(_ text: String, selection: Range<Int>,
                                       _ change: ([String]) -> [String]) -> Result {
        let chars = Array(text)
        let range = clamp(selection, count: chars.count)
        var start = range.lowerBound
        while start > 0, chars[start - 1] != "\n" { start -= 1 }
        var end = range.upperBound
        // A selection ending right after a newline doesn't include the next line.
        if end > start, end > 0, chars[end - 1] == "\n", !range.isEmpty { end -= 1 }
        while end < chars.count, chars[end] != "\n" { end += 1 }

        let block = String(chars[start..<end])
        let oldLines = block.components(separatedBy: "\n")
        let newLines = change(oldLines)
        let replacement = newLines.joined(separator: "\n")

        var updated = chars
        updated.replaceSubrange(start..<end, with: Array(replacement))
        let delta = replacement.count - block.count
        let firstDelta = (newLines.first?.count ?? 0) - (oldLines.first?.count ?? 0)
        let newLower = max(start, range.lowerBound + (range.lowerBound == start ? 0 : firstDelta))
        let newUpper = max(newLower, range.upperBound + delta)
        return Result(text: String(updated), selection: newLower..<min(newUpper, updated.count))
    }

    private static func stripListMarker(_ line: String) -> String {
        var rest = Substring(line)
        let indent = rest.prefix { $0 == " " || $0 == "\t" }
        rest = rest.dropFirst(indent.count)
        if let item = Markdown.parseListItem(line, index: 0) {
            return String(indent) + item.text
        }
        return String(indent) + rest
    }

    private static func stripHeading(_ line: String) -> String {
        var hashes = 0
        for ch in line { if ch == "#" { hashes += 1 } else { break } }
        guard hashes > 0, hashes <= 6, line.dropFirst(hashes).first == " " else { return line }
        return String(line.dropFirst(hashes + 1))
    }
}
