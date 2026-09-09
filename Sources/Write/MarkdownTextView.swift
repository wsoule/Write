import AppKit
import WriteKit

/// The writing surface.
///
/// A plain `NSTextView` plus the handful of behaviours that make writing
/// Markdown feel like writing prose: Return continues a list, Backspace undoes
/// a whole paragraph break, pasting a URL over a phrase links it, and the caret
/// steps over the markers the highlighter collapsed.
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

    // MARK: - Caret and collapsed markers

    override func moveRight(_ sender: Any?) {
        super.moveRight(sender)
        skipCollapsedMarkers(forward: true)
    }

    override func moveLeft(_ sender: Any?) {
        super.moveLeft(sender)
        skipCollapsedMarkers(forward: false)
    }

    /// The markers are invisible, so a caret parked inside one looks like a
    /// caret that refuses to move. Step it past them.
    private func skipCollapsedMarkers(forward: Bool) {
        let selection = selectedRange()
        guard selection.length == 0 else { return }

        let adjusted = skippingCollapsedMarkers(from: selection.location, forward: forward)
        guard adjusted != selection.location else { return }
        setSelectedRange(NSRange(location: adjusted, length: 0))
    }

    private func skippingCollapsedMarkers(from position: Int, forward: Bool) -> Int {
        let ranges = collapsedMarkerRanges(around: position)
        guard !ranges.isEmpty else { return position }

        var result = position
        var moved = true
        while moved {
            moved = false
            for range in ranges {
                if forward, result >= range.location, result < range.upperBound {
                    result = range.upperBound
                    moved = true
                } else if !forward, result > range.location, result <= range.upperBound {
                    result = range.location
                    moved = true
                }
            }
        }
        return result
    }

    private func collapsedMarkerRanges(around position: Int) -> [NSRange] {
        let text = string as NSString
        guard text.length > 0 else { return [] }

        let lineRange = lineContentRange(containing: min(position, text.length), in: text)
        let line = text.substring(with: lineRange)
        return MarkdownSyntax.hiddenMarkerRanges(in: line).map {
            NSRange(location: $0.location + lineRange.location, length: $0.length)
        }
    }

    /// The line around `position`, without its terminator.
    private func lineContentRange(containing position: Int, in text: NSString) -> NSRange {
        let anchor = min(position, max(0, text.length - 1))
        var range = text.lineRange(for: NSRange(location: anchor, length: 0))
        while range.length > 0 {
            let last = text.character(at: range.upperBound - 1)
            guard let scalar = Unicode.Scalar(last), CharacterSet.newlines.contains(scalar) else {
                break
            }
            range.length -= 1
        }
        return range
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
