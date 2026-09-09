import Foundation

public enum LinkURL {
    private static let schemePattern: NSRegularExpression = {
        do {
            return try NSRegularExpression(pattern: #"^[A-Za-z][A-Za-z0-9+.-]*:"#)
        } catch {
            preconditionFailure("Invalid scheme pattern: \(error)")
        }
    }()

    /// Turns pasteboard text into a URL worth linking to, or nil when it is
    /// just prose. Only web and mail links qualify: a bare `file://` path or
    /// an unschemed word should not silently become a link.
    public static func normalized(_ pasteboardText: String) -> String? {
        var candidate = pasteboardText.trimmingCharacters(in: .whitespacesAndNewlines)

        if let lineBreak = candidate.rangeOfCharacter(from: .newlines) {
            candidate = String(candidate[candidate.startIndex..<lineBreak.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard !candidate.isEmpty else { return nil }

        if candidate.lowercased().hasPrefix("www.") {
            candidate = "https://" + candidate
        }

        let range = NSRange(location: 0, length: (candidate as NSString).length)
        guard schemePattern.firstMatch(in: candidate, options: [], range: range) != nil else {
            return nil
        }

        guard let url = URL(string: candidate), let scheme = url.scheme?.lowercased(),
              !scheme.isEmpty else {
            return nil
        }

        let isWebURL = scheme == "http" || scheme == "https" || scheme == "ftp"
        if isWebURL {
            guard let host = url.host, !host.isEmpty else { return nil }
            return url.absoluteString
        }

        guard scheme == "mailto" else { return nil }
        return url.absoluteString
    }
}
