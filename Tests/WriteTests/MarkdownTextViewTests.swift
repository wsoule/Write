import AppKit
import XCTest
@testable import Write

/// Stands in for the caret update AppKit performs inside
/// `NSTextView.setSelectedRanges` when the window is key: it asks the layout
/// manager for the glyphs under the caret, laying the line out on the spot.
/// A test process never gets a key window, so the same layout is forced from
/// the selection-change notification, which fires at the same point — inside
/// `super.setSelectedRanges`, before `MarkdownTextView` restyles anything.
private final class CaretDisplayUpdater: NSObject, NSTextViewDelegate {
    func textViewDidChangeSelection(_ notification: Notification) {
        guard let textView = notification.object as? NSTextView else { return }
        textView.setNeedsDisplay(textView.visibleRect, avoidAdditionalLayout: false)
    }
}

final class MarkdownTextViewTests: XCTestCase {
    private var storage: NSTextStorage!
    private var highlighter: MarkdownHighlighter!
    private var layoutManager: NSLayoutManager!
    private var textView: MarkdownTextView!
    private var window: NSWindow!
    private let caretDisplayUpdater = CaretDisplayUpdater()

    override func setUp() {
        _ = NSApplication.shared
        let font = Fonts.editor(size: 20)

        // The same stack EditorViewController builds, minus the chrome.
        storage = NSTextStorage()
        highlighter = MarkdownHighlighter(textStorage: storage, baseFont: font)
        layoutManager = NSLayoutManager()
        let container = NSTextContainer(size: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        container.lineFragmentPadding = 0
        storage.addLayoutManager(layoutManager)
        layoutManager.addTextContainer(container)

        textView = MarkdownTextView(frame: NSRect(x: 0, y: 0, width: 600, height: 400),
                                    textContainer: container)
        textView.highlighter = highlighter
        textView.configureForWriting(font: font)
        textView.delegate = caretDisplayUpdater

        window = NSWindow(contentRect: textView.frame, styleMask: [.titled],
                          backing: .buffered, defer: false)
        window.contentView = textView
        window.makeFirstResponder(textView)
    }

    private func font(at location: Int) -> NSFont? {
        storage.attribute(.font, at: location, effectiveRange: nil) as? NSFont
    }

    /// Where the layout manager puts the character at `location`, horizontally.
    private func layoutX(ofCharacterAt location: Int) -> CGFloat {
        layoutManager.location(forGlyphAt: layoutManager.glyphIndexForCharacter(at: location)).x
    }

    /// Pressing Return at the end of a heading collapses its "# " (the caret
    /// leaves the line), and the layout has to follow.
    ///
    /// AppKit moves the caret from inside `NSTextStorage.processEditing`, and
    /// the caret update lays the heading line out right there, while its
    /// hashes are still revealed. Restyling the line at that moment used to be
    /// silently absorbed by the edit already in progress, so the layout
    /// manager never heard about the collapse: on screen the text kept its old
    /// position, with a 32pt gap where the hashes had been, until the next
    /// click on the line.
    func testReturnAfterHeadingCollapsesTheHashesInTheLayout() {
        textView.insertText("# Heading", replacementRange: textView.selectedRange())
        window.displayIfNeeded()
        XCTAssertEqual(font(at: 0)?.pointSize, 32, "hashes are revealed while the caret is on the line")
        let revealedX = layoutX(ofCharacterAt: 2)
        XCTAssertGreaterThan(revealedX, 30, "the heading text sits after the revealed hashes")

        textView.insertNewline(nil)
        window.displayIfNeeded()

        XCTAssertEqual(storage.string, "# Heading\n\n")
        XCTAssertEqual(font(at: 0)?.pointSize, 1, "the caret left the line, so the hashes collapsed")
        XCTAssertEqual(layoutX(ofCharacterAt: 2), 0, accuracy: 1,
                       "the layout still places the heading text after \(revealedX)pt of hashes")
    }
}
