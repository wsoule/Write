import AppKit

/// The quiet strip along the bottom: save and open, whatever the document last
/// had to say, and the word count.
final class FooterView: NSView {
    private let saveButton = FooterView.iconButton(symbol: "square.and.arrow.down",
                                                   tooltip: "Save")
    private let openButton = FooterView.iconButton(symbol: "folder", tooltip: "Open")
    private let statusLabel = FooterView.label(alignment: .left)
    private let wordCountLabel = FooterView.label(alignment: .right)

    var onSave: (() -> Void)?
    var onOpen: (() -> Void)?

    var status: String = "" {
        didSet { statusLabel.stringValue = status }
    }

    var wordCount: Int = 0 {
        didSet { wordCountLabel.stringValue = "\(wordCount) \(wordCount == 1 ? "Word" : "Words")" }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setUp()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setUp()
    }

    private func setUp() {
        alphaValue = 0.6
        wordCountLabel.stringValue = "0 Words"

        saveButton.target = self
        saveButton.action = #selector(save)
        openButton.target = self
        openButton.action = #selector(open)

        let stack = NSStackView(views: [saveButton, openButton, statusLabel])
        stack.orientation = .horizontal
        stack.spacing = 10
        stack.alignment = .centerY
        stack.translatesAutoresizingMaskIntoConstraints = false

        addSubview(stack)
        addSubview(wordCountLabel)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: wordCountLabel.leadingAnchor,
                                            constant: -12),

            wordCountLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -14),
            wordCountLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    func apply(fontSize: CGFloat) {
        let font = Fonts.interface(size: fontSize)
        statusLabel.font = font
        wordCountLabel.font = font
    }

    @objc private func save() { onSave?() }
    @objc private func open() { onOpen?() }

    // Clicks that miss the buttons belong to the editor underneath.
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let hit = super.hitTest(point) else { return nil }

        var candidate: NSView? = hit
        while let view = candidate, view !== self {
            if view is NSButton { return hit }
            candidate = view.superview
        }
        return nil
    }

    // MARK: - Pieces

    private static func iconButton(symbol: String, tooltip: String) -> NSButton {
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: tooltip)
        let button = NSButton(image: image ?? NSImage(), target: nil, action: nil)
        button.isBordered = false
        button.bezelStyle = .regularSquare
        button.imageScaling = .scaleProportionallyDown
        button.contentTintColor = Palette.muted
        button.toolTip = tooltip
        button.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: 20),
            button.heightAnchor.constraint(equalToConstant: 20),
        ])
        return button
    }

    private static func label(alignment: NSTextAlignment) -> NSTextField {
        let label = NSTextField(labelWithString: "")
        label.font = Fonts.interface(size: 11)
        label.textColor = Palette.muted
        label.alignment = alignment
        label.lineBreakMode = .byTruncatingTail
        label.translatesAutoresizingMaskIntoConstraints = false
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return label
    }
}
