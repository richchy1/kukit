import Foundation

/// Minimal RFC 4180 CSV writer for exports.
public enum CSV {
    /// Quotes a field when it contains a comma, quote or line break.
    public static func escape(_ field: String) -> String {
        guard field.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" || $0 == "\r" }) else { return field }
        return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    public static func row(_ fields: [String]) -> String {
        fields.map(escape).joined(separator: ",")
    }

    /// A whole document with CRLF line endings and a UTF-8 byte-order mark, so Excel opens
    /// non-Latin text (Korean course names, say) correctly.
    public static func document(header: [String], rows: [[String]]) -> String {
        let lines = [row(header)] + rows.map(row)
        return "\u{FEFF}" + lines.joined(separator: "\r\n") + "\r\n"
    }
}
