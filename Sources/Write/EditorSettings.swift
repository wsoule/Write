import AppKit

/// The one preference the app has: how big the writing is.
///
/// Omawrite follows the desktop's text-size setting. macOS has no equivalent
/// knob, so the size lives here and is driven by the usual ⌘+ / ⌘- / ⌘0.
enum EditorSettings {
    static let fontSizeDidChange = Notification.Name("WriteEditorFontSizeDidChange")

    private static let key = "editorFontSize"
    static let defaultSize: CGFloat = 20
    static let minimumSize: CGFloat = 11
    static let maximumSize: CGFloat = 42

    static var fontSize: CGFloat {
        get {
            let stored = UserDefaults.standard.double(forKey: key)
            guard stored > 0 else { return defaultSize }
            return clamp(CGFloat(stored))
        }
        set {
            UserDefaults.standard.set(Double(clamp(newValue)), forKey: key)
            NotificationCenter.default.post(name: fontSizeDidChange, object: nil)
        }
    }

    /// Interface chrome is sized relative to the writing, so the whole window
    /// grows together the way it does in Omawrite.
    static var interfaceFontSize: CGFloat {
        max(10, (fontSize / defaultSize) * 11)
    }

    private static func clamp(_ size: CGFloat) -> CGFloat {
        min(maximumSize, max(minimumSize, size))
    }
}
