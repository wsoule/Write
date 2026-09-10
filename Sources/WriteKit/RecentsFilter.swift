import Foundation

public enum RecentsFilter {
    /// Narrows a recency-ordered list down to the items whose name matches
    /// the query, the way a quick switcher does.
    ///
    /// Matching is case-insensitive. Names that contain the query outright
    /// come first; names that merely contain its letters in order (so "dch"
    /// finds "Draft chapter") follow. Within each group the original order is
    /// kept, so the most recent file stays on top.
    public static func filter<Item>(_ items: [Item], query: String,
                                    name: (Item) -> String) -> [Item] {
        let query = query.trimmingCharacters(in: .whitespaces).lowercased()
        if query.isEmpty { return items }

        var substringMatches: [Item] = []
        var scatteredMatches: [Item] = []
        for item in items {
            let candidate = name(item).lowercased()
            if candidate.contains(query) {
                substringMatches.append(item)
            } else if containsInOrder(candidate, query) {
                scatteredMatches.append(item)
            }
        }
        return substringMatches + scatteredMatches
    }

    public static func filter(_ names: [String], query: String) -> [String] {
        filter(names, query: query, name: { $0 })
    }

    private static func containsInOrder(_ text: String, _ letters: String) -> Bool {
        var remaining = letters[...]
        for character in text where character == remaining.first {
            remaining = remaining.dropFirst()
            if remaining.isEmpty { return true }
        }
        return remaining.isEmpty
    }
}
