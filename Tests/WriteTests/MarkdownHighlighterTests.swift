import AppKit
import XCTest
@testable import Write

final class MarkdownHighlighterTests: XCTestCase {
    private var storage: NSTextStorage!
    private var highlighter: MarkdownHighlighter!

    override func setUp() {
        storage = NSTextStorage()
        highlighter = MarkdownHighlighter(textStorage: storage,
                                          baseFont: NSFont.monospacedSystemFont(ofSize: 20, weight: .regular))
    }

    /// Types `text` at the end the way the text view does: one edit, then a
    /// selection change.
    private func type(_ text: String) {
        storage.replaceCharacters(in: NSRange(location: storage.length, length: 0), with: text)
        highlighter.setSelection(NSRange(location: storage.length, length: 0))
    }

    private func font(at location: Int) -> NSFont? {
        storage.attribute(.font, at: location, effectiveRange: nil) as? NSFont
    }

    func testHeadingWithNoTextYetOnALaterLineDoesNotThrow() {
        // "# " at the end of a later paragraph has an empty heading range that
        // sits exactly at the end of the storage; that used to raise
        // NSRangeException and swallow every keystroke after it.
        type("para\n")
        type("#")
        type(" ")
        type("a")
        XCTAssertEqual(storage.string, "para\n# a")
        XCTAssertEqual(font(at: 7)?.pointSize, 32, "heading text is H1")
        XCTAssertEqual(font(at: 5)?.pointSize, 32, "revealed hashes match the heading")
    }

    func testMarkersHideAwayFromTheCaretAndShowBesideIt() {
        type("**bold** and more")
        // Caret at the end: far from the span, so the markers are collapsed.
        XCTAssertEqual(font(at: 0)?.pointSize, 1)
        // Caret touching the span's closing edge reveals them.
        highlighter.setSelection(NSRange(location: 8, length: 0))
        XCTAssertEqual(font(at: 0)?.pointSize, 20)
        XCTAssertEqual(font(at: 6)?.pointSize, 20)
    }

    func testHeadingsScaleByLevel() {
        type("# One\n## Two\n### Three\n#### Four")
        XCTAssertEqual(font(at: 2)?.pointSize, 32)
        XCTAssertEqual(font(at: 9)?.pointSize, 28)
        XCTAssertEqual(font(at: 17)?.pointSize, 25)
        XCTAssertEqual(font(at: 28)?.pointSize, 22)
    }
}
