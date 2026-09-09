import Foundation

/// The Markdown the formatting shortcuts insert.
public enum MarkdownEdits {

    /// Wraps the selection in `before`/`after` and keeps the same text
    /// selected, so pressing the shortcut twice reads naturally.
    public static func wrap(in text: String, selection: NSRange,
                            before: String, after: String) -> TextEdit {
        let selected = (text as NSString).substring(with: clamped(selection, in: text))
        let prefixLength = (before as NSString).length
        return TextEdit(range: clamped(selection, in: text),
                        replacement: before + selected + after,
                        selection: NSRange(location: selection.location + prefixLength,
                                           length: (selected as NSString).length))
    }

    /// Builds a Markdown link, using the pasteboard URL when there is one and
    /// selecting whichever half still needs the writer's attention.
    public static func link(in text: String, selection: NSRange,
                            pasteboardURL: String?) -> TextEdit {
        let range = clamped(selection, in: text)
        let selected = (text as NSString).substring(with: range)
        let url = pasteboardURL ?? ""

        let label = selected.isEmpty ? "link text" : selected
        let destination = url.isEmpty ? "https://" : url
        let escapedLabel = escapeLinkText(label)
        let markdown = "[\(escapedLabel)](\(escapeLinkDestination(destination)))"

        let labelLength = (escapedLabel as NSString).length
        let markdownLength = (markdown as NSString).length

        if selected.isEmpty {
            // Nothing to go on: select the placeholder label to type over.
            return TextEdit(range: range, replacement: markdown,
                            selection: NSRange(location: range.location + 1, length: labelLength))
        }
        if url.isEmpty {
            // The label is written; select the placeholder destination.
            return TextEdit(range: range, replacement: markdown,
                            selection: NSRange(location: range.location + labelLength + 3,
                                               length: markdownLength - labelLength - 4))
        }
        return TextEdit(range: range, replacement: markdown)
    }

    /// Pasting a URL over selected text links that text instead of replacing
    /// it. Returns nil when the paste should happen normally.
    public static func pasteAsLink(in text: String, selection: NSRange,
                                   pasteboardURL: String?) -> TextEdit? {
        let range = clamped(selection, in: text)
        guard range.length > 0, let url = pasteboardURL, !url.isEmpty else { return nil }

        let selected = (text as NSString).substring(with: range)
        let leading = String(selected.prefix { $0.isWhitespace })
        let trailing = String(selected.reversed().prefix { $0.isWhitespace }.reversed())
        let linkText = String(selected.dropFirst(leading.count).dropLast(trailing.count))
        guard !linkText.isEmpty else { return nil }

        let markdown = leading
            + "[\(escapeLinkText(linkText))](\(escapeLinkDestination(url)))"
            + trailing
        return TextEdit(range: range, replacement: markdown)
    }

    /// Backspace against the blank line between two paragraphs removes the
    /// whole break, so it undoes one Return rather than half of one.
    public static func deleteParagraphBreak(in text: String, selection: NSRange) -> TextEdit? {
        guard selection.length == 0, selection.location >= 2 else { return nil }
        let start = selection.location - 2
        guard (text as NSString).substring(with: NSRange(location: start, length: 2)) == "\n\n" else {
            return nil
        }
        return TextEdit(range: NSRange(location: start, length: 2), replacement: "")
    }

    public static func escapeLinkText(_ linkText: String) -> String {
        linkText
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "[", with: "\\[")
            .replacingOccurrences(of: "]", with: "\\]")
    }

    public static func escapeLinkDestination(_ url: String) -> String {
        url
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "(", with: "\\(")
            .replacingOccurrences(of: ")", with: "\\)")
    }

    private static func clamped(_ range: NSRange, in text: String) -> NSRange {
        let length = (text as NSString).length
        let location = max(0, min(range.location, length))
        return NSRange(location: location, length: max(0, min(range.length, length - location)))
    }
}
