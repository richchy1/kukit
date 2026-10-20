import SwiftUI
import KukitCore

/// Renders parsed Markdown. Inline styling (bold, italic, code, links) comes from
/// `AttributedString`; block layout (headings, lists, tables…) is drawn here.
struct MarkdownPreview: View {
    var source: String
    /// Called with the source line of a checklist item when its box is tapped.
    var onToggleLine: (Int) -> Void
    /// Called with the title inside a `[[page link]]`.
    var onOpenNote: (String) -> Void

    var body: some View {
        let blocks = Markdown.parse(source)
        VStack(alignment: .leading, spacing: 12) {
            if blocks.isEmpty {
                Text("Nothing to preview yet.")
                    .foregroundStyle(.secondary)
            }
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                view(for: block)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .textSelection(.enabled)
        .environment(\.openURL, OpenURLAction { url in
            if let title = Markdown.wikiLinkTitle(from: url) {
                onOpenNote(title)
                return .handled
            }
            return .systemAction
        })
    }

    @ViewBuilder
    private func view(for block: MarkdownBlock) -> some View {
        switch block {
        case .heading(let level, let text):
            inline(text)
                .font(headingFont(level))
                .fontWeight(.bold)
                .padding(.top, level <= 2 ? 6 : 2)
                .accessibilityAddTraits(.isHeader)

        case .paragraph(let text):
            inline(text)

        case .list(_, let items):
            VStack(alignment: .leading, spacing: 5) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    listRow(item)
                }
            }

        case .quote(let text):
            HStack(alignment: .top, spacing: 10) {
                RoundedRectangle(cornerRadius: 2).fill(Theme.accent.opacity(0.7)).frame(width: 3)
                inline(text).italic().foregroundStyle(.secondary)
            }
            .fixedSize(horizontal: false, vertical: true)

        case .code(_, let text):
            ScrollView(.horizontal, showsIndicators: false) {
                Text(text.isEmpty ? " " : text)
                    .font(.system(.callout, design: .monospaced))
                    .padding(12)
            }
            .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))

        case .rule:
            Divider().padding(.vertical, 4)

        case .table(let header, let rows):
            Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 6) {
                GridRow {
                    ForEach(Array(header.enumerated()), id: \.offset) { _, cell in
                        inline(cell).fontWeight(.semibold)
                    }
                }
                Divider().gridCellUnsizedAxes(.horizontal)
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    GridRow {
                        ForEach(Array(row.enumerated()), id: \.offset) { _, cell in inline(cell) }
                    }
                }
            }
            .padding(10)
            .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }

    private func listRow(_ item: MarkdownListItem) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            if let checked = item.checked {
                Button { onToggleLine(item.line) } label: {
                    Image(systemName: checked ? "checkmark.square.fill" : "square")
                        .foregroundStyle(checked ? Theme.accent : Color.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(checked ? "Checked" : "Not checked")
                inline(item.text)
                    .strikethrough(checked)
                    .foregroundStyle(checked ? .secondary : .primary)
            } else if let number = item.number {
                Text("\(number).").monospacedDigit().foregroundStyle(.secondary)
                inline(item.text)
            } else {
                Text("•").foregroundStyle(.secondary)
                inline(item.text)
            }
        }
        .padding(.leading, CGFloat(item.depth) * 20)
    }

    private func headingFont(_ level: Int) -> Font {
        switch level {
        case 1: .title
        case 2: .title2
        case 3: .title3
        default: .headline
        }
    }

    private func inline(_ text: String) -> Text {
        let prepared = Markdown.expandWikiLinks(text)
        let options = AttributedString.MarkdownParsingOptions(
            allowsExtendedAttributes: false,
            interpretedSyntax: .inlineOnlyPreservingWhitespace,
            failurePolicy: .returnPartiallyParsedIfPossible
        )
        if let attributed = try? AttributedString(markdown: prepared, options: options) {
            return Text(attributed)
        }
        return Text(text)
    }
}
