import Foundation

public enum SuggestedFileName {
    private static let unsafeCharacters: NSRegularExpression = {
        do {
            return try NSRegularExpression(pattern: #"[/\x00-\x1f\x7f:]"#)
        } catch {
            preconditionFailure("Invalid file name pattern: \(error)")
        }
    }()

    /// Names an untitled document after its first line, the way a writer would.
    ///
    /// Path separators and control characters become dashes. macOS also treats
    /// a colon in a file name as a separator in some contexts, so it is
    /// replaced too.
    public static func from(_ text: String) -> String {
        let firstLine = text.split(separator: "\n", maxSplits: 1,
                                   omittingEmptySubsequences: false).first.map { String($0) } ?? ""
        var name = firstLine.trimmingCharacters(in: .whitespaces)

        let range = NSRange(location: 0, length: (name as NSString).length)
        name = unsafeCharacters.stringByReplacingMatches(in: name, options: [],
                                                         range: range, withTemplate: "-")

        name = String(name.prefix(120)).trimmingCharacters(in: .whitespaces)
        if name.isEmpty || name == "." || name == ".." {
            name = "Untitled"
        }
        if !name.lowercased().hasSuffix(".md") {
            name += ".md"
        }
        return name
    }
}
