import AppKit
import WriteKit

/// The writing surface.
///
/// A plain `NSTextView` plus the handful of behaviours that make writing
/// Markdown feel like writing prose: Return continues a list, Backspace undoes
/// a whole paragraph break, pasting a URL over a phrase links it, and the
/// markers around the span the caret touches come back into view.
final class MarkdownTextView: NSTextView {
    private static let placeholder = "# Start writing"

    // MARK: - Setup

    func configureForWriting(font: NSFont) {
        isRichText = false
        allowsUndo = true
        isEditable = true
        isSelectable = true
        usesFindPanel = false
        drawsBackground = false
        smartInsertDeleteEnabled = false
        isAutomaticQuoteSubstitutionEnabled = false
        isAutomaticDashSubstitutionEnabled = false
        isAutomaticTextReplacementEnabled = false
        isAutomaticLinkDetectionEnabled = false
        isContinuousSpellCheckingEnabled = true
        isGrammarCheckingEnabled = false
        insertionPointColor = Palette.text
        selectedTextAttributes = [.backgroundColor: Palette.selection,
                                  .foregroundColor: Palette.text]
        apply(font: font)
    }

    func apply(font: NSFont) {
        self.font = font
        typingAttributes = [.font: font,
                            .foregroundColor: Palette.text,
                            .paragraphStyle: MarkdownHighlighter.paragraphStyle]
        needsDisplay = true
    }

    // MARK: - Editing behaviour

    override func insertNewline(_ sender: Any?) {
        guard !hasMarkedText() else {
            super.insertNewline(sender)
            return
        }
        let softBreak = NSApp.currentEvent?.modifierFlags.contains(.shift) ?? false
        apply(SmartReturn.edit(in: string, selection: selectedRange(), softBreak: softBreak))
    }

    override func insertLineBreak(_ sender: Any?) {
        apply(SmartReturn.edit(in: string, selection: selectedRange(), softBreak: true))
    }

    override func deleteBackward(_ sender: Any?) {
        if !hasMarkedText(),
           let edit = MarkdownEdits.deleteParagraphBreak(in: string, selection: selectedRange()) {
            apply(edit)
            return
        }
        super.deleteBackward(sender)
    }

    override func paste(_ sender: Any?) {
        if let edit = MarkdownEdits.pasteAsLink(in: string, selection: selectedRange(),
                                                pasteboardURL: pasteboardURL()) {
            apply(edit)
            return
        }
        pasteAsPlainText(sender)
    }

    // MARK: - Formatting

    @objc func toggleBoldMarkdown(_ sender: Any?) {
        apply(MarkdownEdits.wrap(in: string, selection: selectedRange(), before: "**", after: "**"))
    }

    @objc func toggleItalicMarkdown(_ sender: Any?) {
        apply(MarkdownEdits.wrap(in: string, selection: selectedRange(), before: "*", after: "*"))
    }

    @objc func insertMarkdownLink(_ sender: Any?) {
        apply(MarkdownEdits.link(in: string, selection: selectedRange(),
                                 pasteboardURL: pasteboardURL()))
    }

    /// Applies an edit through the text view so undo, the delegate and the
    /// highlighter all see it as one change.
    func apply(_ edit: TextEdit) {
        guard let textStorage = self.textStorage,
              shouldChangeText(in: edit.range, replacementString: edit.replacement) else { return }

        textStorage.replaceCharacters(in: edit.range, with: edit.replacement)
        didChangeText()

        let length = textStorage.length
        let location = min(edit.selection.location, length)
        let selection = NSRange(location: location,
                                length: min(edit.selection.length, length - location))
        setSelectedRange(selection)
        scrollRangeToVisible(selection)
    }

    // MARK: - Revealing markers around the caret

    /// The highlighter that collapses and reveals markers; it needs to know
    /// where the caret is.
    weak var highlighter: MarkdownHighlighter?

    /// Every selection change — keys, mouse, programmatic — funnels through
    /// here, so this is where the highlighter learns the caret moved.
    override func setSelectedRanges(_ ranges: [NSValue], affinity: NSSelectionAffinity,
                                    stillSelecting: Bool) {
        super.setSelectedRanges(ranges, affinity: affinity, stillSelecting: stillSelecting)
        if let first = ranges.first?.rangeValue {
            highlighter?.setSelection(first)
        }
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil {
            highlighter?.setSelection(selectedRange())
        }
    }

    // MARK: - Pasteboard

    private func pasteboardURL() -> String? {
        let pasteboard = NSPasteboard.general

        if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL] {
            for url in urls {
                if let normalized = LinkURL.normalized(url.absoluteString) { return normalized }
            }
        }
        guard let text = pasteboard.string(forType: .string) else { return nil }
        return LinkURL.normalized(text)
    }

    // MARK: - Caret height

    /// The 1.4 line height leaves air above every line, and the stock caret
    /// stretches through all of it. Trim it to the glyphs it sits beside.
    override func drawInsertionPoint(in rect: NSRect, color: NSColor, turnedOn flag: Bool) {
        super.drawInsertionPoint(in: glyphAlignedCaret(rect), color: color, turnedOn: flag)
    }

    private func glyphAlignedCaret(_ rect: NSRect) -> NSRect {
        guard let layoutManager, let font = fontAtInsertionPoint() else { return rect }
        // TextKit adds the extra line height above the glyph block, so the
        // block is the bottom `defaultLineHeight` of the fragment, with the
        // baseline `ascender` below its top.
        let blockTop = rect.maxY - layoutManager.defaultLineHeight(for: font)
        let height = min(font.ascender - font.descender, rect.maxY - blockTop)
        return NSRect(x: rect.minX, y: blockTop, width: rect.width, height: height)
    }

    private func fontAtInsertionPoint() -> NSFont? {
        guard let storage = textStorage else { return font }
        let location = selectedRange().location
        let sample = location < storage.length ? location : location - 1
        if sample >= 0, sample < storage.length,
           let font = storage.attribute(.font, at: sample, effectiveRange: nil) as? NSFont {
            return font
        }
        return typingAttributes[.font] as? NSFont ?? font
    }

    // MARK: - Placeholder

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard string.isEmpty, let font = self.font else { return }

        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: Palette.muted,
            .paragraphStyle: MarkdownHighlighter.paragraphStyle,
        ]
        let origin = NSPoint(x: textContainerInset.width + (textContainer?.lineFragmentPadding ?? 0),
                             y: textContainerInset.height)
        (Self.placeholder as NSString).draw(at: origin, withAttributes: attributes)
    }
}
