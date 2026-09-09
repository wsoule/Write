import Foundation

/// Scans a single line of Markdown for the spans the editor styles.
///
/// This is the single source of truth for inline Markdown: the highlighter
/// uses it to style content and hide the markers, and the text view uses it
/// (through `hiddenMarkerRanges`) to skip the caret over markers it hid.
///
/// Everything is expressed in UTF-16 offsets (`NSRange`) so the results can be
/// handed straight to `NSTextStorage`.
public enum MarkdownSyntax {

    // MARK: - Inline

    public enum InlineKind: Equatable {
        case bold
        case italic
        case link
    }

    public struct InlineMarkup: Equatable {
        /// What the span means, which decides how the content is styled.
        public let kind: InlineKind
        /// The visible text between the markers.
        public let content: NSRange
        /// The two marker runs that are hidden: opening and closing.
        public let markers: [NSRange]

        public init(kind: InlineKind, content: NSRange, markers: [NSRange]) {
            self.kind = kind
            self.content = content
            self.markers = markers
        }
    }

    private static let boldPattern = regex(#"(\*\*|__)(.+?)(\1)"#)
    private static let italicPattern = regex(#"(?<!\*)\*([^*\n]+)\*(?!\*)|(?<!_)_([^_\n]+)_(?!_)"#)
    private static let linkPattern = regex(#"\[([^\]]+)\]\(((?:\\.|[^)])+)\)"#)
    private static let codePattern = regex(#"`([^`]+)`"#)

    /// Bold, italic and link spans on `line`, in that order. Later spans win
    /// where they overlap, which matches how the highlighter applies them.
    public static func inlineMarkup(in line: String) -> [InlineMarkup] {
        guard line.contains("*") || line.contains("_") || line.contains("[") else { return [] }

        let text = line as NSString
        let whole = NSRange(location: 0, length: text.length)
        var markup: [InlineMarkup] = []

        for match in boldPattern.matches(in: line, range: whole) {
            markup.append(InlineMarkup(kind: .bold,
                                       content: match.range(at: 2),
                                       markers: [match.range(at: 1), match.range(at: 3)]))
        }

        for match in italicPattern.matches(in: line, range: whole) {
            let span = match.range(at: 0)
            // Only one of the two alternatives captures, so take whichever did.
            let contentGroup = match.range(at: 1).location != NSNotFound ? 1 : 2
            markup.append(InlineMarkup(kind: .italic,
                                       content: match.range(at: contentGroup),
                                       markers: [NSRange(location: span.location, length: 1),
                                                 NSRange(location: span.upperBound - 1, length: 1)]))
        }

        for match in linkPattern.matches(in: line, range: whole) {
            let span = match.range(at: 0)
            let content = match.range(at: 1)
            markup.append(InlineMarkup(kind: .link,
                                       content: content,
                                       markers: [NSRange(location: span.location, length: 1),
                                                 NSRange(location: content.upperBound,
                                                         length: span.upperBound - content.upperBound)]))
        }

        return markup
    }

    /// Inline code spans, including the surrounding backticks.
    public static func codeSpans(in line: String) -> [NSRange] {
        guard line.contains("`") else { return [] }
        let whole = NSRange(location: 0, length: (line as NSString).length)
        return codePattern.matches(in: line, range: whole).map { $0.range(at: 0) }
    }

    /// The marker ranges the highlighter hides on `line`, sorted by position.
    public static func hiddenMarkerRanges(in line: String) -> [NSRange] {
        inlineMarkup(in: line)
            .flatMap(\.markers)
            .filter { $0.location != NSNotFound && $0.length > 0 }
            .sorted { $0.location < $1.location }
    }

    // MARK: - Block

    public enum BlockStyle: Equatable {
        /// Leading punctuation: `#`, `>`, list bullets, horizontal rules.
        case marker
        case heading
        case quote
    }

    public struct BlockSpan: Equatable {
        public let range: NSRange
        public let style: BlockStyle

        public init(range: NSRange, style: BlockStyle) {
            self.range = range
            self.style = style
        }
    }

    private static let headingPattern = regex(#"^(#{1,6})(\s+)(.*)$"#)
    private static let quotePattern = regex(#"^(\s*>+\s?)(.*)$"#)
    private static let listPattern = regex(#"^(\s*(?:[-+*]|\d+[.)])\s+)(.*)$"#)
    private static let rulePattern = regex(#"^\s{0,3}([-*_])(?:\s*\1){2,}\s*$"#)

    /// Block-level spans on `line`, in application order.
    public static func blockSpans(in line: String) -> [BlockSpan] {
        let text = line as NSString
        guard text.length > 0 else { return [] }

        var first = 0
        while first < text.length,
              CharacterSet.whitespaces.contains(unicodeScalar(text.character(at: first))) {
            first += 1
        }
        guard first < text.length else { return [] }

        let whole = NSRange(location: 0, length: text.length)
        let firstCharacter = Character(unicodeScalar(text.character(at: first)))
        var spans: [BlockSpan] = []

        if first == 0, firstCharacter == "#",
           let heading = headingPattern.firstMatch(in: line, range: whole) {
            let markerLength = heading.range(at: 1).length + heading.range(at: 2).length
            spans.append(BlockSpan(range: NSRange(location: 0, length: markerLength), style: .marker))
            spans.append(BlockSpan(range: heading.range(at: 3), style: .heading))
            return spans
        }

        if firstCharacter == ">", let quote = quotePattern.firstMatch(in: line, range: whole) {
            spans.append(BlockSpan(range: NSRange(location: 0, length: quote.range(at: 1).length),
                                   style: .marker))
            spans.append(BlockSpan(range: quote.range(at: 2), style: .quote))
        }

        if "-+*".contains(firstCharacter) || firstCharacter.isNumber,
           let list = listPattern.firstMatch(in: line, range: whole) {
            spans.append(BlockSpan(range: NSRange(location: 0, length: list.range(at: 1).length),
                                   style: .marker))
        }

        if "-*_".contains(firstCharacter), rulePattern.firstMatch(in: line, range: whole) != nil {
            spans.append(BlockSpan(range: whole, style: .marker))
        }

        return spans
    }

    // MARK: - Helpers

    private static func unicodeScalar(_ utf16Unit: unichar) -> Unicode.Scalar {
        Unicode.Scalar(utf16Unit) ?? Unicode.Scalar(0)
    }

    /// The patterns here are compile-time constants; a failure to compile one
    /// is a programming error rather than something to recover from.
    private static func regex(_ pattern: String) -> NSRegularExpression {
        do {
            return try NSRegularExpression(pattern: pattern)
        } catch {
            preconditionFailure("Invalid Markdown pattern \(pattern): \(error)")
        }
    }
}

extension NSRegularExpression {
    fileprivate func matches(in string: String, range: NSRange) -> [NSTextCheckingResult] {
        matches(in: string, options: [], range: range)
    }

    fileprivate func firstMatch(in string: String, range: NSRange) -> NSTextCheckingResult? {
        firstMatch(in: string, options: [], range: range)
    }
}
