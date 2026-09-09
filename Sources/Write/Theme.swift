import AppKit

/// The palette, ported from Omawrite. Every colour is dynamic: AppKit resolves
/// it against the appearance in effect when it is drawn, so the app follows
/// System Settings › Appearance without any code of its own.
enum Palette {
    static let page = dynamic(dark: "#101010", light: "#ffffff")
    static let text = dynamic(dark: "#eeeeee", light: "#222324")
    static let muted = dynamic(dark: "#909191", light: "#aeb1b5")
    static let marker = dynamic(dark: "#4f525a", light: "#aeb1b5")
    static let accent = dynamic(dark: "#5584aa", light: "#2077b2")
    static let selection = dynamic(dark: "#186a9a", light: "#2077b2")
    static let codeBackground = dynamic(dark: "#1c1a1a", light: "#f8f8f8")

    static let findBackground = dynamic(dark: "#22221f", light: "#fffef2")
    static let findControl = dynamic(dark: "#eeeeee", light: "#62635f")
    static let findSeparator = dynamic(dark: "#6f6f62", light: "#d5d56e")
    static let searchMatch = dynamic(dark: "#725b18", light: "#ffe58a")
    static let currentSearchMatch = dynamic(dark: "#b36b20", light: "#ffad42")

    private static func dynamic(dark: String, light: String) -> NSColor {
        let darkColor = NSColor(hex: dark)
        let lightColor = NSColor(hex: light)
        return NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? darkColor : lightColor
        }
    }
}

/// Fixed colours for print, where the paper is white whatever the screen is.
enum PrintPalette {
    static let text = NSColor(hex: "#222324")
    static let marker = NSColor(hex: "#aeb1b5")
    static let accent = NSColor(hex: "#2077b2")
    static let codeBackground = NSColor(hex: "#f8f8f8")
}

extension NSColor {
    /// Parses `#rgb`, `#rrggbb` and `#rrggbbaa`. Anything else is magenta, so a
    /// mistake is loud rather than silent.
    convenience init(hex: String) {
        var digits = hex.trimmingCharacters(in: .whitespaces)
        if digits.hasPrefix("#") { digits.removeFirst() }

        if digits.count == 3 {
            digits = digits.map { "\($0)\($0)" }.joined()
        }
        guard digits.count == 6 || digits.count == 8,
              let value = UInt64(digits, radix: 16) else {
            self.init(srgbRed: 1, green: 0, blue: 1, alpha: 1)
            return
        }

        let hasAlpha = digits.count == 8
        let shift = hasAlpha ? 8 : 0
        let component = { (byte: Int) in
            CGFloat((value >> UInt64(byte * 8 + shift)) & 0xFF) / 255
        }
        self.init(srgbRed: component(2), green: component(1), blue: component(0),
                  alpha: hasAlpha ? CGFloat(value & 0xFF) / 255 : 1)
    }
}
