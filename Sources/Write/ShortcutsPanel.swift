import AppKit

/// A small reference card, reachable from Help or ⌘/.
enum ShortcutsPanel {
    private static var panel: NSPanel?

    private static let shortcuts: [(String, String)] = [
        ("⌘N", "New document"),
        ("⌘O", "Open"),
        ("⌘K", "Open recent"),
        ("⌘S", "Save"),
        ("⇧⌘S", "Save As"),
        ("⌘P", "Print"),
        ("⌘Z / ⇧⌘Z", "Undo / Redo"),
        ("⌘F", "Find"),
        ("⌥⌘F", "Find and Replace"),
        ("⌘G / ⇧⌘G", "Next / previous match"),
        ("⌘B", "Bold"),
        ("⌘I", "Italic"),
        ("⌘L", "Link"),
        ("⌘+ / ⌘- / ⌘0", "Bigger / smaller / actual size"),
        ("⌃⌘F", "Full screen"),
        ("⏎", "New paragraph, or continue a list"),
        ("⇧⏎", "Line break inside a paragraph"),
    ]

    static func show() {
        if let existing = panel {
            existing.makeKeyAndOrderFront(nil)
            return
        }

        let content = NSTextField(wrappingLabelWithString: text())
        content.font = Fonts.interface(size: 12)
        content.textColor = Palette.text
        content.translatesAutoresizingMaskIntoConstraints = false

        let container = BackgroundView(frame: NSRect(x: 0, y: 0, width: 400, height: 460))
        container.addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 26),
            content.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -26),
            content.topAnchor.constraint(equalTo: container.topAnchor, constant: 24),
            content.bottomAnchor.constraint(lessThanOrEqualTo: container.bottomAnchor,
                                            constant: -24),
        ])

        let newPanel = NSPanel(contentRect: container.frame,
                               styleMask: [.titled, .closable, .utilityWindow],
                               backing: .buffered, defer: false)
        newPanel.title = "Keyboard Shortcuts"
        newPanel.contentView = container
        newPanel.backgroundColor = Palette.page
        newPanel.isReleasedWhenClosed = false
        newPanel.center()
        newPanel.makeKeyAndOrderFront(nil)
        panel = newPanel
    }

    private static func text() -> String {
        let width = shortcuts.map { $0.0.count }.max() ?? 0
        return shortcuts.map { shortcut, meaning in
            let padding = String(repeating: " ", count: max(0, width - shortcut.count))
            return "\(shortcut)\(padding)   \(meaning)"
        }.joined(separator: "\n")
    }
}
