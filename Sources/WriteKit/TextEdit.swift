import Foundation

/// A replacement to apply to the document, plus where the selection should
/// land once it has been applied.
public struct TextEdit: Equatable {
    /// The range being replaced, in the document as it stands now.
    public let range: NSRange
    public let replacement: String
    /// The selection afterwards, in the document as it will stand. An empty
    /// range is a caret.
    public let selection: NSRange

    public init(range: NSRange, replacement: String, selection: NSRange) {
        self.range = range
        self.replacement = replacement
        self.selection = selection
    }

    /// The common case: leave the caret at the end of what was inserted.
    public init(range: NSRange, replacement: String) {
        self.init(range: range,
                  replacement: replacement,
                  selection: NSRange(location: range.location + (replacement as NSString).length,
                                     length: 0))
    }
}
