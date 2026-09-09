import Foundation

/// What pressing Return does.
///
/// Prose gets a blank line between paragraphs, lists and quotes continue
/// themselves, an empty list item ends the list, and a fenced code block is
/// left alone.
public enum SmartReturn {
    private static let continuationPattern: NSRegularExpression = {
        do {
            return try NSRegularExpression(pattern: #"^(\s*)([-+*]|\d+[.)]|>+)\s+(.*)$"#)
        } catch {
            preconditionFailure("Invalid continuation pattern: \(error)")
        }
    }()

    private static let fencePattern: NSRegularExpression = {
        do {
            return try NSRegularExpression(pattern: "^\\s*```", options: [.anchorsMatchLines])
        } catch {
            preconditionFailure("Invalid fence pattern: \(error)")
        }
    }()

    public static func edit(in text: String, selection: NSRange, softBreak: Bool) -> TextEdit {
        if softBreak {
            return TextEdit(range: selection, replacement: "\n")
        }

        let string = text as NSString
        let caret = min(selection.location, string.length)
        let selectionEnd = min(selection.upperBound, string.length)

        // Inside an unclosed code fence, Return is just a newline.
        let before = string.substring(to: caret)
        let fences = fencePattern.numberOfMatches(
            in: before, options: [], range: NSRange(location: 0, length: (before as NSString).length))
        if fences % 2 == 1 {
            return TextEdit(range: selection, replacement: "\n")
        }

        let lineStart = lineStart(in: string, before: caret)
        let line = string.substring(with: NSRange(location: lineStart, length: caret - lineStart))
        let lineRange = NSRange(location: 0, length: (line as NSString).length)

        if let match = continuationPattern.firstMatch(in: line, options: [], range: lineRange) {
            let indent = (line as NSString).substring(with: match.range(at: 1))
            let marker = (line as NSString).substring(with: match.range(at: 2))
            let content = (line as NSString).substring(with: match.range(at: 3))

            if content.isEmpty {
                // Return on an empty item ends the list rather than adding another.
                return TextEdit(range: NSRange(location: lineStart, length: selectionEnd - lineStart),
                                replacement: "\n")
            }
            return TextEdit(range: selection, replacement: "\n" + indent + next(marker) + " ")
        }

        return TextEdit(range: selection, replacement: "\n\n")
    }

    /// Ordered markers advance; bullets and quote markers repeat.
    private static func next(_ marker: String) -> String {
        guard let first = marker.first, first.isNumber else { return marker }
        let digits = marker.prefix { $0.isNumber }
        guard let number = Int(digits), let delimiter = marker.last else { return marker }
        return "\(number + 1)\(delimiter)"
    }

    private static func lineStart(in string: NSString, before position: Int) -> Int {
        guard position > 0 else { return 0 }
        let searched = string.range(of: "\n", options: .backwards,
                                    range: NSRange(location: 0, length: position))
        return searched.location == NSNotFound ? 0 : searched.upperBound
    }
}
