import XCTest
@testable import WriteKit

final class WordCountTests: XCTestCase {
    func testCountsWordsTheWayAWriterWould() {
        XCTAssertEqual(WordCount.count(in: "one two-three don't 42"), 4)
        XCTAssertEqual(WordCount.count(in: "你好 世界"), 2)
        XCTAssertEqual(WordCount.count(in: ""), 0)
        XCTAssertEqual(WordCount.count(in: "  --- *** \n\n "), 0)
    }
}

final class LinkURLTests: XCTestCase {
    func testNormalizesWebAndMailLinks() {
        XCTAssertEqual(LinkURL.normalized("www.example.com/path"), "https://www.example.com/path")
        XCTAssertEqual(LinkURL.normalized("  https://example.com/a  "), "https://example.com/a")
        XCTAssertEqual(LinkURL.normalized("mailto:writer@example.com"), "mailto:writer@example.com")
    }

    func testRejectsAnythingThatIsNotALink() {
        XCTAssertNil(LinkURL.normalized("example.com"))
        XCTAssertNil(LinkURL.normalized("file:///tmp/private"))
        XCTAssertNil(LinkURL.normalized("just some prose"))
        XCTAssertNil(LinkURL.normalized(""))
    }

    func testUsesOnlyTheFirstLine() {
        XCTAssertEqual(LinkURL.normalized("https://example.com\nand more"), "https://example.com")
    }
}

final class SuggestedFileNameTests: XCTestCase {
    func testNamesTheDocumentAfterItsFirstLine() {
        XCTAssertEqual(SuggestedFileName.from("My first draft\nBody"), "My first draft.md")
        XCTAssertEqual(SuggestedFileName.from("# A heading"), "# A heading.md")
        XCTAssertEqual(SuggestedFileName.from("Already.md"), "Already.md")
    }

    func testKeepsTheNameSafeForTheFileSystem() {
        XCTAssertEqual(SuggestedFileName.from("A/B"), "A-B.md")
        XCTAssertEqual(SuggestedFileName.from("Notes: Monday"), "Notes- Monday.md")
        XCTAssertEqual(SuggestedFileName.from(""), "Untitled.md")
        XCTAssertEqual(SuggestedFileName.from("   "), "Untitled.md")
        XCTAssertEqual(SuggestedFileName.from(".."), "Untitled.md")
    }
}

final class MarkdownSyntaxTests: XCTestCase {
    func testFindsInlineMarkdownRanges() {
        let markup = MarkdownSyntax.inlineMarkup(
            in: "**bold** and *italic* and [site](https://example.com)")
        XCTAssertEqual(markup.count, 3)

        XCTAssertEqual(markup[0].kind, .bold)
        XCTAssertEqual(markup[0].content, NSRange(location: 2, length: 4))
        XCTAssertEqual(markup[0].markers, [NSRange(location: 0, length: 2),
                                           NSRange(location: 6, length: 2)])

        XCTAssertEqual(markup[1].kind, .italic)
        XCTAssertEqual(markup[1].content, NSRange(location: 14, length: 6))

        XCTAssertEqual(markup[2].kind, .link)
        XCTAssertEqual(markup[2].content, NSRange(location: 27, length: 4))
        XCTAssertEqual(markup[2].markers[0], NSRange(location: 26, length: 1))
        // The closing marker covers "](https://example.com)".
        XCTAssertEqual(markup[2].markers[1], NSRange(location: 31, length: 22))
    }

    func testUnderscoreEmphasis() {
        let markup = MarkdownSyntax.inlineMarkup(in: "__strong__ and _soft_")
        XCTAssertEqual(markup.map(\.kind), [.bold, .italic])
        XCTAssertEqual(markup[0].content, NSRange(location: 2, length: 6))
        XCTAssertEqual(markup[1].content, NSRange(location: 16, length: 4))
    }

    func testIgnoresLinesWithoutMarkup() {
        XCTAssertTrue(MarkdownSyntax.inlineMarkup(in: "plain prose").isEmpty)
        XCTAssertTrue(MarkdownSyntax.hiddenMarkerRanges(in: "plain prose").isEmpty)
    }

    func testHiddenMarkersAreSorted() {
        let hidden = MarkdownSyntax.hiddenMarkerRanges(in: "*a* and **b**")
        XCTAssertEqual(hidden.map(\.location), [0, 2, 8, 11])
    }

    func testCodeSpansIncludeTheirBackticks() {
        XCTAssertEqual(MarkdownSyntax.codeSpans(in: "run `swift build` now"),
                       [NSRange(location: 4, length: 13)])
    }

    func testHeadingSplitsMarkerFromText() {
        let spans = MarkdownSyntax.blockSpans(in: "## Title")
        XCTAssertEqual(spans, [.init(range: NSRange(location: 0, length: 3), style: .marker),
                               .init(range: NSRange(location: 3, length: 5), style: .heading)])
    }

    func testQuotesListsAndRules() {
        XCTAssertEqual(MarkdownSyntax.blockSpans(in: "> quoted").map(\.style), [.marker, .quote])
        XCTAssertEqual(MarkdownSyntax.blockSpans(in: "  - item").map(\.style), [.marker])
        XCTAssertEqual(MarkdownSyntax.blockSpans(in: "3) item").map(\.style), [.marker])
        XCTAssertEqual(MarkdownSyntax.blockSpans(in: "---"),
                       [.init(range: NSRange(location: 0, length: 3), style: .marker)])
        XCTAssertTrue(MarkdownSyntax.blockSpans(in: "just prose").isEmpty)
        XCTAssertTrue(MarkdownSyntax.blockSpans(in: "").isEmpty)
    }

    func testHashInTheMiddleIsNotAHeading() {
        XCTAssertTrue(MarkdownSyntax.blockSpans(in: "a # b").isEmpty)
    }
}

final class SmartReturnTests: XCTestCase {
    private func apply(_ text: String, at position: Int, softBreak: Bool = false) -> String {
        let edit = SmartReturn.edit(in: text, selection: NSRange(location: position, length: 0),
                                    softBreak: softBreak)
        return (text as NSString).replacingCharacters(in: edit.range, with: edit.replacement)
    }

    func testProseGetsABlankLineBetweenParagraphs() {
        XCTAssertEqual(apply("done", at: 4), "done\n\n")
    }

    func testShiftReturnIsASoftBreak() {
        XCTAssertEqual(apply("done", at: 4, softBreak: true), "done\n")
    }

    func testBulletsContinue() {
        XCTAssertEqual(apply("- milk", at: 6), "- milk\n- ")
        XCTAssertEqual(apply("  * milk", at: 8), "  * milk\n  * ")
    }

    func testOrderedListsCountUp() {
        XCTAssertEqual(apply("2. second", at: 9), "2. second\n3. ")
        XCTAssertEqual(apply("9) ninth", at: 8), "9) ninth\n10) ")
    }

    func testQuotesContinue() {
        XCTAssertEqual(apply("> said", at: 6), "> said\n> ")
    }

    func testEmptyItemEndsTheList() {
        XCTAssertEqual(apply("- milk\n- ", at: 9), "- milk\n\n")
    }

    func testCodeFenceGetsAPlainNewline() {
        XCTAssertEqual(apply("```\ncode", at: 8), "```\ncode\n")
        // Once the fence is closed, prose behaves like prose again.
        XCTAssertEqual(apply("```\ncode\n```\nafter", at: 18), "```\ncode\n```\nafter\n\n")
    }
}

final class MarkdownEditsTests: XCTestCase {
    func testWrapKeepsTheSelectionOnTheText() {
        let text = "make this bold"
        let edit = MarkdownEdits.wrap(in: text, selection: NSRange(location: 10, length: 4),
                                      before: "**", after: "**")
        XCTAssertEqual((text as NSString).replacingCharacters(in: edit.range, with: edit.replacement),
                       "make this **bold**")
        XCTAssertEqual(edit.selection, NSRange(location: 12, length: 4))
    }

    func testLinkWithNothingSelectedOffersAPlaceholderLabel() {
        let edit = MarkdownEdits.link(in: "", selection: NSRange(location: 0, length: 0),
                                      pasteboardURL: nil)
        XCTAssertEqual(edit.replacement, "[link text](https://)")
        XCTAssertEqual(edit.selection, NSRange(location: 1, length: 9))
    }

    func testLinkWithSelectionSelectsTheDestination() {
        let text = "Anthropic"
        let edit = MarkdownEdits.link(in: text, selection: NSRange(location: 0, length: 9),
                                      pasteboardURL: nil)
        XCTAssertEqual(edit.replacement, "[Anthropic](https://)")
        let destination = (edit.replacement as NSString).substring(with: edit.selection)
        XCTAssertEqual(destination, "https://")
    }

    func testLinkUsesThePasteboardURL() {
        let text = "Anthropic"
        let edit = MarkdownEdits.link(in: text, selection: NSRange(location: 0, length: 9),
                                      pasteboardURL: "https://anthropic.com")
        XCTAssertEqual(edit.replacement, "[Anthropic](https://anthropic.com)")
        XCTAssertEqual(edit.selection.length, 0)
    }

    func testLinkEscapesBracketsAndParentheses() {
        let text = "a [b] c"
        let edit = MarkdownEdits.link(in: text, selection: NSRange(location: 0, length: 7),
                                      pasteboardURL: "https://example.com/a(b)")
        XCTAssertEqual(edit.replacement, "[a \\[b\\] c](https://example.com/a\\(b\\))")
    }

    func testPastingAURLOverTextLinksIt() {
        let text = "  Anthropic  "
        let edit = MarkdownEdits.pasteAsLink(in: text, selection: NSRange(location: 0, length: 13),
                                             pasteboardURL: "https://anthropic.com")
        XCTAssertEqual(edit?.replacement, "  [Anthropic](https://anthropic.com)  ")
    }

    func testPastingWithoutASelectionOrURLPastesNormally() {
        XCTAssertNil(MarkdownEdits.pasteAsLink(in: "text", selection: NSRange(location: 0, length: 0),
                                               pasteboardURL: "https://anthropic.com"))
        XCTAssertNil(MarkdownEdits.pasteAsLink(in: "text", selection: NSRange(location: 0, length: 4),
                                               pasteboardURL: nil))
        XCTAssertNil(MarkdownEdits.pasteAsLink(in: "   ", selection: NSRange(location: 0, length: 3),
                                               pasteboardURL: "https://anthropic.com"))
    }

    func testBackspaceRemovesAWholeParagraphBreak() {
        let edit = MarkdownEdits.deleteParagraphBreak(in: "one\n\n", selection: NSRange(location: 5, length: 0))
        XCTAssertEqual(edit?.range, NSRange(location: 3, length: 2))
        XCTAssertNil(MarkdownEdits.deleteParagraphBreak(in: "one\n", selection: NSRange(location: 4, length: 0)))
    }
}

final class RecentsFilterTests: XCTestCase {
    private let names = ["Notes.md", "Draft chapter.md", "todo.md", "Meeting notes.md"]

    func testAnEmptyQueryKeepsEverythingInOrder() {
        XCTAssertEqual(RecentsFilter.filter(names, query: ""), names)
        XCTAssertEqual(RecentsFilter.filter(names, query: "   "), names)
    }

    func testMatchesIgnoreCase() {
        XCTAssertEqual(RecentsFilter.filter(names, query: "NOTES"), ["Notes.md", "Meeting notes.md"])
    }

    func testSubstringMatchesRankAboveScatteredOnes() {
        // "ia" sits inside "Diary" but is only scattered through "Ideas", so
        // Diary wins even though Ideas was opened more recently.
        XCTAssertEqual(RecentsFilter.filter(["Ideas.md", "Diary.md"], query: "ia"),
                       ["Diary.md", "Ideas.md"])
    }

    func testScatteredLettersMustAppearInOrder() {
        XCTAssertEqual(RecentsFilter.filter(names, query: "dch"), ["Draft chapter.md"])
        XCTAssertEqual(RecentsFilter.filter(names, query: "hcd"), [])
    }

    func testDropsNamesThatDoNotContainTheQueryLetters() {
        XCTAssertEqual(RecentsFilter.filter(names, query: "xyz"), [])
    }

    func testFiltersArbitraryItemsByAName() {
        struct Item: Equatable { let name: String; let id: Int }
        let items = [Item(name: "b.md", id: 1), Item(name: "a.md", id: 2)]
        XCTAssertEqual(RecentsFilter.filter(items, query: "a", name: \.name), [items[1]])
    }
}
