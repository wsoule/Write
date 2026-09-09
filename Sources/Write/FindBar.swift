import AppKit

protocol FindBarDelegate: AnyObject {
    func findBar(_ bar: FindBar, didChangeQuery query: String)
    func findBarDidRequestNext(_ bar: FindBar)
    func findBarDidRequestPrevious(_ bar: FindBar)
    func findBar(_ bar: FindBar, replaceCurrentWith replacement: String)
    func findBar(_ bar: FindBar, replaceAllWith replacement: String)
    func findBarDidClose(_ bar: FindBar)
}

/// The find (and replace) strip that floats over the top of the page.
final class FindBar: NSView, NSTextFieldDelegate {
    weak var delegate: FindBarDelegate?

    private let findField = FindBar.field(placeholder: "Find")
    private let replaceField = FindBar.field(placeholder: "Replace with")
    private let matchLabel = NSTextField(labelWithString: "0/0")
    private let replaceButton = NSButton(title: "Replace", target: nil, action: nil)
    private let replaceAllButton = NSButton(title: "All", target: nil, action: nil)
    private let separator = NSBox()
    private var replaceRowConstraint: NSLayoutConstraint!

    private(set) var showsReplace = false

    var query: String { findField.stringValue }
    var replacement: String { replaceField.stringValue }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setUp()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setUp()
    }

    // MARK: - Appearance

    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        guard let layer = self.layer else { return }
        layer.cornerRadius = 9
        layer.backgroundColor = Palette.findBackground.cgColor
        layer.shadowColor = NSColor.black.cgColor
        layer.shadowOpacity = 0.25
        layer.shadowRadius = 12
        layer.shadowOffset = CGSize(width: 0, height: -2)
        layer.masksToBounds = false
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    // MARK: - Presentation

    func present(showingReplace: Bool, in window: NSWindow?) {
        showsReplace = showingReplace
        replaceField.isHidden = !showingReplace
        replaceButton.isHidden = !showingReplace
        replaceAllButton.isHidden = !showingReplace
        replaceRowConstraint.constant = showingReplace ? 48 : 0
        isHidden = false

        window?.makeFirstResponder(findField)
        findField.currentEditor()?.selectAll(nil)
    }

    func dismiss() {
        isHidden = true
        showsReplace = false
        delegate?.findBarDidClose(self)
    }

    func showMatches(index: Int, of total: Int) {
        matchLabel.stringValue = total == 0 ? "0/0" : "\(index + 1)/\(total)"
    }

    // MARK: - Layout

    private func setUp() {
        wantsLayer = true
        isHidden = true

        matchLabel.font = Fonts.interface(size: 13)
        matchLabel.textColor = Palette.findControl
        matchLabel.alignment = .center

        findField.delegate = self
        replaceField.delegate = self

        for button in [replaceButton, replaceAllButton] {
            button.bezelStyle = .rounded
            button.controlSize = .regular
            button.isHidden = true
        }
        replaceButton.target = self
        replaceButton.action = #selector(replaceCurrent)
        replaceAllButton.target = self
        replaceAllButton.action = #selector(replaceAll)

        separator.boxType = .custom
        separator.borderWidth = 0
        separator.fillColor = Palette.findSeparator
        separator.translatesAutoresizingMaskIntoConstraints = false

        let previous = Self.iconButton(symbol: "chevron.up", tooltip: "Previous match")
        previous.target = self
        previous.action = #selector(findPrevious)
        let next = Self.iconButton(symbol: "chevron.down", tooltip: "Next match")
        next.target = self
        next.action = #selector(findNext)
        let close = Self.iconButton(symbol: "xmark", tooltip: "Close")
        close.target = self
        close.action = #selector(closeBar)

        let controls = NSStackView(views: [matchLabel, replaceButton, replaceAllButton,
                                           separator, previous, next, close])
        controls.orientation = .horizontal
        controls.spacing = 6
        controls.alignment = .centerY
        controls.translatesAutoresizingMaskIntoConstraints = false
        controls.setHuggingPriority(.required, for: .horizontal)

        addSubview(findField)
        addSubview(replaceField)
        addSubview(controls)

        replaceRowConstraint = replaceField.heightAnchor.constraint(equalToConstant: 0)

        NSLayoutConstraint.activate([
            findField.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            findField.topAnchor.constraint(equalTo: topAnchor),
            findField.heightAnchor.constraint(equalToConstant: 52),
            findField.trailingAnchor.constraint(equalTo: controls.leadingAnchor, constant: -8),

            replaceField.leadingAnchor.constraint(equalTo: findField.leadingAnchor),
            replaceField.trailingAnchor.constraint(equalTo: findField.trailingAnchor),
            replaceField.topAnchor.constraint(equalTo: findField.bottomAnchor),
            replaceField.bottomAnchor.constraint(equalTo: bottomAnchor),
            replaceRowConstraint,

            controls.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            controls.centerYAnchor.constraint(equalTo: findField.centerYAnchor),

            matchLabel.widthAnchor.constraint(equalToConstant: 54),
            separator.widthAnchor.constraint(equalToConstant: 1),
            separator.heightAnchor.constraint(equalToConstant: 26),
        ])
    }

    // MARK: - Actions

    @objc private func findNext() { delegate?.findBarDidRequestNext(self) }
    @objc private func findPrevious() { delegate?.findBarDidRequestPrevious(self) }
    @objc private func closeBar() { dismiss() }

    @objc private func replaceCurrent() {
        delegate?.findBar(self, replaceCurrentWith: replaceField.stringValue)
    }

    @objc private func replaceAll() {
        delegate?.findBar(self, replaceAllWith: replaceField.stringValue)
    }

    // MARK: - NSTextFieldDelegate

    func controlTextDidChange(_ notification: Notification) {
        guard (notification.object as? NSTextField) === findField else { return }
        delegate?.findBar(self, didChangeQuery: findField.stringValue)
    }

    func control(_ control: NSControl, textView: NSTextView,
                 doCommandBy commandSelector: Selector) -> Bool {
        switch commandSelector {
        case #selector(NSResponder.cancelOperation(_:)):
            dismiss()
            return true
        case #selector(NSResponder.insertNewline(_:)):
            if control === replaceField {
                replaceCurrent()
            } else {
                delegate?.findBarDidRequestNext(self)
            }
            return true
        case #selector(NSResponder.insertBacktab(_:)):
            return false
        default:
            // Shift+Return arrives as insertLineBreak: and walks backwards.
            if commandSelector == #selector(NSResponder.insertLineBreak(_:)), control === findField {
                delegate?.findBarDidRequestPrevious(self)
                return true
            }
            return false
        }
    }

    // MARK: - Pieces

    private static func field(placeholder: String) -> NSTextField {
        let field = NSTextField(string: "")
        field.placeholderString = placeholder
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = Fonts.interface(size: 17)
        field.textColor = Palette.text
        field.lineBreakMode = .byTruncatingTail
        field.translatesAutoresizingMaskIntoConstraints = false
        return field
    }

    private static func iconButton(symbol: String, tooltip: String) -> NSButton {
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: tooltip)
        let button = NSButton(image: image ?? NSImage(), target: nil, action: nil)
        button.isBordered = false
        button.bezelStyle = .regularSquare
        button.contentTintColor = Palette.findControl
        button.toolTip = tooltip
        button.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: 30),
            button.heightAnchor.constraint(equalToConstant: 30),
        ])
        return button
    }
}
