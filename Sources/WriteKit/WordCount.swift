import Foundation

public enum WordCount {
    // Letters and digits, with apostrophes and hyphens allowed inside a word,
    // so "don't" and "two-three" each count once and CJK runs count as one
    // word per run.
    private static let wordPattern: NSRegularExpression = {
        do {
            return try NSRegularExpression(pattern: #"[\p{L}\p{N}]+(?:['-][\p{L}\p{N}]+)*"#)
        } catch {
            preconditionFailure("Invalid word pattern: \(error)")
        }
    }()

    public static func count(in text: String) -> Int {
        let range = NSRange(location: 0, length: (text as NSString).length)
        return wordPattern.numberOfMatches(in: text, options: [], range: range)
    }
}
