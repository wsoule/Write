import AppKit
import WriteKit

/// Colours the highlighter paints with. Screen and print differ only here.
struct HighlightPalette {
    let text: NSColor
    let marker: NSColor
    let link: NSColor
    let codeBackground: NSColor
    let searchMatch: NSColor
    let currentSearchMatch: NSColor

    static let screen = HighlightPalette(text: Palette.text,
                                         marker: Palette.marker,
                                         link: Palette.accent,
                                         codeBackground: Palette.codeBackground,
                                         searchMatch: Palette.searchMatch,
                                         currentSearchMatch: Palette.currentSearchMatch)

    static let printing = HighlightPalette(text: PrintPalette.text,
                                        marker: PrintPalette.marker,
                                        link: PrintPalette.accent,
                                        codeBackground: PrintPalette.codeBackground,
                                        searchMatch: .clear,
                                        currentSearchMatch: .clear)
}

/// Styles Markdown as it is typed.
///
/// Structural punctuation is dimmed, and the markers around bold, italic and
/// link text are collapsed to nothing so the prose reads clean while the source
/// stays plain text. `MarkdownTextView` steps the caret over the collapsed
/// markers using the same scan.
final class MarkdownHighlighter: NSObject, NSTextStorageDelegate {
    private(set) var baseFont: NSFont
    var palette: HighlightPalette

    /// Derived faces are cached: resolving them per span made typing in a long
    /// paragraph measurably slower.
    private var boldFont: NSFont = .systemFont(ofSize: 12)
    private var italicFont: NSFont = .systemFont(ofSize: 12)

    /// Highlighted occurrences of the find query, and which one is current.
    private(set) var searchQuery = ""
    private(set) var currentMatchLocation: Int?

    private weak var textStorage: NSTextStorage?

    /// 1.4 line height, matching Omawrite's typography.
    static let lineHeightMultiple: CGFloat = 1.4

    init(textStorage: NSTextStorage, baseFont: NSFont,
         palette: HighlightPalette = .screen) {
        self.textStorage = textStorage
        self.baseFont = baseFont
        self.palette = palette
        super.init()
        cacheDerivedFonts()
        textStorage.delegate = self
    }

    /// Restyles the whole document in a new size.
    ///
    /// Setting `NSTextView.font` flattens the storage back to one font, so the
    /// caller does that first and this puts the Markdown styling back.
    func setBaseFont(_ font: NSFont) {
        baseFont = font
        cacheDerivedFonts()
        rehighlightEverything()
    }

    private func cacheDerivedFonts() {
        boldFont = Fonts.bold(baseFont)
        italicFont = Fonts.italic(baseFont)
    }

    // MARK: - Attributes

    static let paragraphStyle: NSParagraphStyle = {
        let style = NSMutableParagraphStyle()
        style.lineHeightMultiple = MarkdownHighlighter.lineHeightMultiple
        return style
    }()

    var baseAttributes: [NSAttributedString.Key: Any] {
        [.font: baseFont,
         .foregroundColor: palette.text,
         .paragraphStyle: Self.paragraphStyle,
         .kern: 0]
    }

    // MARK: - Search

    func setSearch(query: String, currentMatchLocation: Int?) {
        guard query != searchQuery || currentMatchLocation != self.currentMatchLocation else {
            return
        }
        searchQuery = query
        self.currentMatchLocation = currentMatchLocation
        rehighlightEverything()
    }

    // MARK: - NSTextStorageDelegate

    func textStorage(_ textStorage: NSTextStorage,
                     didProcessEditing editedMask: NSTextStorageEditActions,
                     range editedRange: NSRange,
                     changeInLength delta: Int) {
        guard editedMask.contains(.editedCharacters) else { return }
        // Already inside the storage's editing transaction, so attributes are
        // applied directly rather than opening a nested one.
        highlight(textStorage, in: (textStorage.string as NSString).paragraphRange(for: editedRange))
    }

    func rehighlightEverything() {
        guard let textStorage = self.textStorage else { return }
        textStorage.beginEditing()
        highlight(textStorage, in: NSRange(location: 0, length: textStorage.length))
        textStorage.endEditing()
    }

    /// Styles a document from scratch — used for the print copy, which has no
    /// text view behind it.
    func highlightAll(in textStorage: NSTextStorage) {
        textStorage.beginEditing()
        highlight(textStorage, in: NSRange(location: 0, length: textStorage.length))
        textStorage.endEditing()
    }

    // MARK: - Highlighting

    private func highlight(_ storage: NSTextStorage, in range: NSRange) {
        let string = storage.string as NSString
        let scope = NSIntersectionRange(range, NSRange(location: 0, length: string.length))
        guard scope.length > 0 || string.length == 0 else { return }

        storage.setAttributes(baseAttributes, range: scope)

        let hidden = hiddenMarkerAttributes()
        string.enumerateSubstrings(in: scope, options: [.byLines, .substringNotRequired]) {
            _, lineRange, _, _ in
            let line = string.substring(with: lineRange)
            self.highlightLine(line, at: lineRange.location, in: storage, hidden: hidden)
        }

        highlightSearchMatches(in: storage, range: scope)
    }

    private func highlightLine(_ line: String, at offset: Int, in storage: NSTextStorage,
                               hidden: [NSAttributedString.Key: Any]) {
        for span in MarkdownSyntax.blockSpans(in: line) {
            let range = shifted(span.range, by: offset, within: storage)
            switch span.style {
            case .marker:
                storage.addAttribute(.foregroundColor, value: palette.marker, range: range)
            case .heading:
                storage.addAttributes([.font: boldFont,
                                       .foregroundColor: palette.text], range: range)
            case .quote:
                storage.addAttributes([.font: italicFont,
                                       .foregroundColor: palette.marker], range: range)
            }
        }

        for span in MarkdownSyntax.codeSpans(in: line) {
            storage.addAttribute(.backgroundColor, value: palette.codeBackground,
                                 range: shifted(span, by: offset, within: storage))
        }

        for markup in MarkdownSyntax.inlineMarkup(in: line) {
            let content = shifted(markup.content, by: offset, within: storage)
            switch markup.kind {
            case .bold:
                storage.addAttributes([.font: boldFont,
                                       .foregroundColor: palette.text], range: content)
            case .italic:
                storage.addAttributes([.font: italicFont,
                                       .foregroundColor: palette.text], range: content)
            case .link:
                storage.addAttributes([.foregroundColor: palette.link,
                                       .underlineStyle: NSUnderlineStyle.single.rawValue],
                                      range: content)
            }

            for marker in markup.markers {
                storage.addAttributes(hidden, range: shifted(marker, by: offset, within: storage))
            }
        }
    }

    private func highlightSearchMatches(in storage: NSTextStorage, range: NSRange) {
        guard !searchQuery.isEmpty else { return }

        let string = storage.string as NSString
        var searchRange = range
        while searchRange.length > 0 {
            let found = string.range(of: searchQuery, options: [.caseInsensitive],
                                     range: searchRange)
            guard found.location != NSNotFound else { return }

            let isCurrent = found.location == currentMatchLocation
            storage.addAttribute(.backgroundColor,
                                 value: isCurrent ? palette.currentSearchMatch : palette.searchMatch,
                                 range: found)

            let next = found.upperBound
            searchRange = NSRange(location: next, length: max(0, range.upperBound - next))
        }
    }

    /// Collapses a marker run to (near) zero width without removing it from the
    /// text: a one-point transparent font whose advance is cancelled by an
    /// equal and opposite kern.
    private func hiddenMarkerAttributes() -> [NSAttributedString.Key: Any] {
        let tinyFont = NSFont(descriptor: baseFont.fontDescriptor, size: 1)
            ?? NSFont.monospacedSystemFont(ofSize: 1, weight: .regular)
        let advance = ("[" as NSString).size(withAttributes: [.font: tinyFont]).width
        return [.font: tinyFont,
                .foregroundColor: NSColor.clear,
                .kern: -advance,
                .paragraphStyle: Self.paragraphStyle]
    }

    private func shifted(_ range: NSRange, by offset: Int, within storage: NSTextStorage) -> NSRange {
        let moved = NSRange(location: range.location + offset, length: range.length)
        return NSIntersectionRange(moved, NSRange(location: 0, length: storage.length))
    }
}
