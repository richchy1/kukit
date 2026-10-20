import Foundation
import Testing
@testable import KukitCore

@Suite("Markdown parsing")
struct MarkdownParsingTests {
    @Test func headingsParagraphsAndBlankLines() {
        let blocks = Markdown.parse("# Title\n\nFirst line\nsecond line\n\n### Small ###\n")
        #expect(blocks == [
            .heading(level: 1, text: "Title"),
            .paragraph("First line\nsecond line"),
            .heading(level: 3, text: "Small"),
        ])
    }

    @Test func hashWithoutSpaceIsNotAHeading() {
        #expect(Markdown.parse("#hashtag") == [.paragraph("#hashtag")])
        #expect(Markdown.parse("####### seven") == [.paragraph("####### seven")])
    }

    @Test func bulletNumberedAndChecklistItems() {
        let blocks = Markdown.parse("- one\n- [ ] todo\n- [x] done\n  - nested\n\n1. first\n2) second")
        guard blocks.count == 2,
              case .list(let ordered1, let items1) = blocks[0],
              case .list(let ordered2, let items2) = blocks[1] else { Issue.record("shape: \(blocks)"); return }
        #expect(!ordered1 && ordered2)
        #expect(items1.map(\.text) == ["one", "todo", "done", "nested"])
        #expect(items1.map(\.checked) == [nil, false, true, nil])
        #expect(items1.map(\.depth) == [0, 0, 0, 1])
        #expect(items1.map(\.line) == [0, 1, 2, 3])
        #expect(items2.map(\.number) == [1, 2])
        #expect(items2.map(\.text) == ["first", "second"])
    }

    @Test func dashesAndStarsThatAreRulesAreNotLists() {
        #expect(Markdown.parse("---") == [.rule])
        #expect(Markdown.parse("* * *") == [.rule])
        #expect(Markdown.parse("-----") == [.rule])
        #expect(Markdown.parse("-no space") == [.paragraph("-no space")])
    }

    @Test func quotesAndFencedCode() {
        let blocks = Markdown.parse("> wise\n> words\n\n```swift\nlet x = 1\n\nprint(x)\n```\nafter")
        #expect(blocks == [
            .quote("wise\nwords"),
            .code(language: "swift", text: "let x = 1\n\nprint(x)"),
            .paragraph("after"),
        ])
    }

    @Test func unclosedCodeFenceRunsToTheEnd() {
        #expect(Markdown.parse("```\nabc\ndef") == [.code(language: "", text: "abc\ndef")])
    }

    @Test func tables() {
        let blocks = Markdown.parse("| Term | Meaning |\n|---|:--|\n| a | b |\n| c | d |\n\nafter")
        #expect(blocks == [
            .table(header: ["Term", "Meaning"], rows: [["a", "b"], ["c", "d"]]),
            .paragraph("after"),
        ])
    }

    @Test func aPipeWithoutASeparatorRowIsJustText() {
        #expect(Markdown.parse("a | b") == [.paragraph("a | b")])
    }

    @Test func windowsLineEndings() {
        #expect(Markdown.parse("# A\r\n\r\ntext") == [.heading(level: 1, text: "A"), .paragraph("text")])
    }

    @Test func emptyInput() {
        #expect(Markdown.parse("").isEmpty)
        #expect(Markdown.parse("\n\n  \n").isEmpty)
    }

    @Test func snippetSkipsMarkup() {
        let source = "# Limits\n\nA **limit** is the value `f(x)` approaches.\n\n- one\n- two"
        #expect(Markdown.snippet(source, maxLength: 200) == "Limits A limit is the value f(x) approaches. one two")
        #expect(Markdown.snippet(source, maxLength: 10).hasSuffix("…"))
    }
}

@Suite("Markdown checklists and links")
struct MarkdownChecklistTests {
    @Test func togglingFlipsOnlyThatLine() {
        let source = "- [ ] a\n- [x] b\n- plain\n"
        #expect(Markdown.toggleChecklist(in: source, line: 0) == "- [x] a\n- [x] b\n- plain\n")
        #expect(Markdown.toggleChecklist(in: source, line: 1) == "- [ ] a\n- [ ] b\n- plain\n")
        #expect(Markdown.toggleChecklist(in: source, line: 2) == source)        // not a checklist item
        #expect(Markdown.toggleChecklist(in: source, line: 99) == source)       // out of range
        #expect(Markdown.toggleChecklist(in: "- [X] caps", line: 0) == "- [ ] caps")
    }

    @Test func togglingKeepsBracketsInTheTextAlone() {
        let source = "- [ ] read [1] and [x]"
        #expect(Markdown.toggleChecklist(in: source, line: 0) == "- [x] read [1] and [x]")
    }

    @Test func wikiLinksBecomeInternalLinks() {
        let expanded = Markdown.expandWikiLinks("See [[Limits]] and [[Chain rule]].")
        #expect(expanded == "See [Limits](kukit-note://page/Limits) and [Chain rule](kukit-note://page/Chain%20rule).")
        #expect(Markdown.expandWikiLinks("no links here") == "no links here")
        #expect(Markdown.expandWikiLinks("[[]]") == "[[]]")
    }

    @Test func wikiLinkURLsResolveBackToTitles() {
        #expect(Markdown.wikiLinkTitle(from: URL(string: "kukit-note://page/Chain%20rule")!) == "Chain rule")
        #expect(Markdown.wikiLinkTitle(from: URL(string: "https://example.com/Chain")!) == nil)
    }

    @Test func titlesAreExtractedInOrderWithoutDuplicates() {
        #expect(Markdown.wikiLinkTitles(in: "[[A]] x [[b]] y [[a]] [[ C ]]") == ["A", "b", "C"])
    }
}

@Suite("Markdown editing")
struct MarkdownEditingTests {
    @Test func wrapSelectionAndUnwrap() {
        let bold = MarkdownEditing.toggleWrap("make this loud", selection: 5..<9, prefix: "**")
        #expect(bold.text == "make **this** loud")
        #expect(bold.selection == 7..<11)
        let undone = MarkdownEditing.toggleWrap(bold.text, selection: bold.selection, prefix: "**")
        #expect(undone.text == "make this loud")
        #expect(undone.selection == 5..<9)
    }

    @Test func wrapWithoutSelectionInsertsPlaceholder() {
        let result = MarkdownEditing.toggleWrap("ab", selection: 1..<1, prefix: "`", placeholder: "code")
        #expect(result.text == "a`code`b")
        #expect(result.selection == 2..<6)
    }

    @Test func linkStyleWrapUsesDifferentPrefixAndSuffix() {
        let result = MarkdownEditing.toggleWrap("go here now", selection: 3..<7, prefix: "[", suffix: "](url)")
        #expect(result.text == "go [here](url) now")
    }

    @Test func wrapHandlesEmojiAndOutOfRangeSelections() {
        let result = MarkdownEditing.toggleWrap("😀 hi", selection: 2..<4, prefix: "_")
        #expect(result.text == "😀 _hi_")
        let clamped = MarkdownEditing.toggleWrap("abc", selection: 10..<20, prefix: "*", placeholder: "x")
        #expect(clamped.text == "abc*x*")
    }

    @Test func bulletPrefixAcrossLinesAndBack() {
        let text = "one\ntwo\nthree"
        let on = MarkdownEditing.toggleLinePrefix(text, selection: 1..<6, prefix: "- ")
        #expect(on.text == "- one\n- two\nthree")
        let off = MarkdownEditing.toggleLinePrefix(on.text, selection: on.selection, prefix: "- ")
        #expect(off.text == text)
    }

    @Test func switchingListKindsReplacesTheMarker() {
        let result = MarkdownEditing.toggleLinePrefix("- item", selection: 0..<0, prefix: "- [ ] ")
        #expect(result.text == "- [ ] item")
        let numbered = MarkdownEditing.toggleLinePrefix("1. item", selection: 0..<0, prefix: "> ")
        #expect(numbered.text == "> item")
    }

    @Test func headingsReplaceEachOther() {
        let h1 = MarkdownEditing.setHeading("Title", selection: 0..<0, level: 1)
        #expect(h1.text == "# Title")
        let h2 = MarkdownEditing.setHeading(h1.text, selection: h1.selection, level: 2)
        #expect(h2.text == "## Title")
        let none = MarkdownEditing.setHeading(h2.text, selection: h2.selection, level: 2)
        #expect(none.text == "Title")
    }

    @Test func indentAndOutdent() {
        let indented = MarkdownEditing.shiftIndent("- a\n- b", selection: 0..<7, outdent: false)
        #expect(indented.text == "  - a\n  - b")
        #expect(MarkdownEditing.shiftIndent(indented.text, selection: 0..<indented.text.count, outdent: true).text == "- a\n- b")
        #expect(MarkdownEditing.shiftIndent("x", selection: 0..<0, outdent: true).text == "x")
    }

    @Test func returnContinuesListsAndEndsThemOnEmptyItems() {
        let bullet = MarkdownEditing.continueList("- apples", cursor: 8)
        #expect(bullet?.text == "- apples\n- ")
        #expect(bullet?.selection == 11..<11)

        let numbered = MarkdownEditing.continueList("1. first\n2. second", cursor: 18)
        #expect(numbered?.text == "1. first\n2. second\n3. ")

        let checklist = MarkdownEditing.continueList("- [x] done", cursor: 10)
        #expect(checklist?.text == "- [x] done\n- [ ] ")

        let nested = MarkdownEditing.continueList("  - child", cursor: 9)
        #expect(nested?.text == "  - child\n  - ")

        let ended = MarkdownEditing.continueList("- apples\n- ", cursor: 11)
        #expect(ended?.text == "- apples\n")

        #expect(MarkdownEditing.continueList("plain text", cursor: 10) == nil)
        #expect(MarkdownEditing.continueList("- middle of line", cursor: 4) == nil)
    }

    @Test func detectsASingleTypedNewline() {
        #expect(MarkdownEditing.insertedNewline(old: "- a", new: "- a\n") == 3)
        #expect(MarkdownEditing.insertedNewline(old: "ab", new: "a\nb") == 1)
        #expect(MarkdownEditing.insertedNewline(old: "ab", new: "axb") == nil)       // not a newline
        #expect(MarkdownEditing.insertedNewline(old: "ab", new: "a\n\nb") == nil)    // two characters
        #expect(MarkdownEditing.insertedNewline(old: "", new: "\n") == 0)
        #expect(MarkdownEditing.insertedNewline(old: "same", new: "same") == nil)
    }
}
