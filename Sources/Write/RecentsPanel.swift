import AppKit
import WriteKit

/// A quick switcher for recently opened documents, reachable with ⌘K.
///
/// Type to narrow the list, ↑/↓ to move, ⏎ to open, ⎋ to dismiss. The list
/// is the same one AppKit keeps for File › Open Recent.
final class RecentsPanel: NSPanel, NSTextFieldDelegate, NSTableViewDataSource, NSTableViewDelegate {
    private static var shared: RecentsPanel?

    private let searchField = NSTextField()
    private let table = NSTableView()
    private let scrollView = NSScrollView()
    private let emptyLabel = NSTextField(labelWithString: "No recent documents")

    private var allURLs: [URL] = []
    private var visibleURLs: [URL] = []

    private static let width: CGFloat = 520
    private static let rowHeight: CGFloat = 44
    private static let maxRows = 8

    static func toggle() {
        if let panel = shared, panel.isVisible {
            panel.dismiss()
        } else {
            show()
        }
    }

    private static func show() {
        let panel = shared ?? RecentsPanel()
        shared = panel
        panel.reload()
        panel.searchField.stringValue = ""
        panel.applyFilter()
        panel.centerOverKeyWindow()
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(panel.searchField)
    }

    private init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: RecentsPanel.width, height: 100),
                   styleMask: [.titled, .fullSizeContentView, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        isMovableByWindowBackground = true
        isReleasedWhenClosed = false
        hidesOnDeactivate = true
        backgroundColor = Palette.page
        setUp()
    }

    // MARK: - Layout

    private func setUp() {
        let container = BackgroundView(frame: frame)
        contentView = container

        searchField.placeholderString = "Open recent…"
        searchField.font = Fonts.interface(size: 18)
        searchField.textColor = Palette.text
        searchField.isBezeled = false
        searchField.drawsBackground = false
        searchField.focusRingType = .none
        searchField.delegate = self
        searchField.translatesAutoresizingMaskIntoConstraints = false

        let separator = NSBox()
        separator.boxType = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("recent"))
        table.addTableColumn(column)
        table.headerView = nil
        table.rowHeight = RecentsPanel.rowHeight
        table.backgroundColor = .clear
        table.selectionHighlightStyle = .regular
        table.intercellSpacing = .zero
        table.dataSource = self
        table.delegate = self
        table.target = self
        table.action = #selector(rowClicked)
        table.refusesFirstResponder = true

        scrollView.documentView = table
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        emptyLabel.font = Fonts.interface(size: 13)
        emptyLabel.textColor = Palette.muted
        emptyLabel.alignment = .center
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(searchField)
        container.addSubview(separator)
        container.addSubview(scrollView)
        container.addSubview(emptyLabel)

        NSLayoutConstraint.activate([
            searchField.topAnchor.constraint(equalTo: container.topAnchor, constant: 16),
            searchField.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 20),
            searchField.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -20),

            separator.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: 14),
            separator.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: container.trailingAnchor),

            scrollView.topAnchor.constraint(equalTo: separator.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: container.bottomAnchor),

            emptyLabel.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            emptyLabel.topAnchor.constraint(equalTo: separator.bottomAnchor, constant: 18),
        ])
    }

    private func centerOverKeyWindow() {
        let anchor = NSApp.keyWindow?.frame
            ?? NSApp.mainWindow?.frame
            ?? NSScreen.main?.visibleFrame
            ?? NSRect(x: 0, y: 0, width: 800, height: 600)
        let origin = NSPoint(x: anchor.midX - frame.width / 2,
                             y: anchor.midY - frame.height / 2 + anchor.height * 0.15)
        setFrameOrigin(origin)
    }

    private func resizeToFit() {
        let rows = min(max(visibleURLs.count, 1), RecentsPanel.maxRows)
        let listHeight = CGFloat(rows) * RecentsPanel.rowHeight
        let fieldHeight = searchField.intrinsicContentSize.height
        let height = 16 + fieldHeight + 14 + 1 + listHeight
        let top = frame.maxY
        setFrame(NSRect(x: frame.minX, y: top - height, width: RecentsPanel.width, height: height),
                 display: true)
    }

    // MARK: - Data

    private func reload() {
        // Files that have since moved or been deleted are not worth listing.
        allURLs = NSDocumentController.shared.recentDocumentURLs.filter {
            FileManager.default.fileExists(atPath: $0.path)
        }
    }

    private func applyFilter() {
        visibleURLs = RecentsFilter.filter(allURLs, query: searchField.stringValue,
                                           name: { $0.lastPathComponent })
        table.reloadData()
        emptyLabel.isHidden = !visibleURLs.isEmpty
        scrollView.isHidden = visibleURLs.isEmpty
        if !visibleURLs.isEmpty {
            table.selectRowIndexes([0], byExtendingSelection: false)
            table.scrollRowToVisible(0)
        }
        resizeToFit()
    }

    private func dismiss() {
        orderOut(nil)
    }

    private func openSelected() {
        let row = table.selectedRow
        guard row >= 0, row < visibleURLs.count else { return }
        let url = visibleURLs[row]
        dismiss()
        NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { _, _, error in
            if let error {
                NSApp.presentError(error)
            }
        }
    }

    private func moveSelection(by delta: Int) {
        guard !visibleURLs.isEmpty else { return }
        let row = min(max(table.selectedRow + delta, 0), visibleURLs.count - 1)
        table.selectRowIndexes([row], byExtendingSelection: false)
        table.scrollRowToVisible(row)
    }

    @objc private func rowClicked() {
        if table.clickedRow >= 0 {
            table.selectRowIndexes([table.clickedRow], byExtendingSelection: false)
            openSelected()
        }
    }

    // MARK: - NSTextFieldDelegate

    func controlTextDidChange(_ notification: Notification) {
        applyFilter()
    }

    func control(_ control: NSControl, textView: NSTextView,
                 doCommandBy commandSelector: Selector) -> Bool {
        switch commandSelector {
        case #selector(NSResponder.cancelOperation(_:)):
            dismiss()
            return true
        case #selector(NSResponder.insertNewline(_:)):
            openSelected()
            return true
        case #selector(NSResponder.moveDown(_:)):
            moveSelection(by: 1)
            return true
        case #selector(NSResponder.moveUp(_:)):
            moveSelection(by: -1)
            return true
        default:
            return false
        }
    }

    // MARK: - NSTableViewDataSource / Delegate

    func numberOfRows(in tableView: NSTableView) -> Int {
        visibleURLs.count
    }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?,
                   row: Int) -> NSView? {
        let url = visibleURLs[row]
        let identifier = NSUserInterfaceItemIdentifier("RecentRow")
        let cell = tableView.makeView(withIdentifier: identifier, owner: nil) as? RecentRowView
            ?? RecentRowView(identifier: identifier)
        cell.configure(name: url.deletingPathExtension().lastPathComponent,
                       location: RecentsPanel.displayPath(for: url.deletingLastPathComponent()))
        return cell
    }

    func tableView(_ tableView: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        RecentRowBackground()
    }

    /// "~/Documents/Notes" reads better than the full path.
    private static func displayPath(for url: URL) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let path = url.path
        if path.hasPrefix(home) {
            return "~" + path.dropFirst(home.count)
        }
        return path
    }
}

/// One row: the file name, with where it lives in smaller muted text below.
private final class RecentRowView: NSTableCellView {
    private let nameLabel = NSTextField(labelWithString: "")
    private let locationLabel = NSTextField(labelWithString: "")

    init(identifier: NSUserInterfaceItemIdentifier) {
        super.init(frame: .zero)
        self.identifier = identifier

        nameLabel.font = Fonts.interface(size: 14)
        nameLabel.textColor = Palette.text
        nameLabel.lineBreakMode = .byTruncatingTail
        nameLabel.translatesAutoresizingMaskIntoConstraints = false

        locationLabel.font = Fonts.interface(size: 11)
        locationLabel.textColor = Palette.muted
        locationLabel.lineBreakMode = .byTruncatingMiddle
        locationLabel.translatesAutoresizingMaskIntoConstraints = false

        addSubview(nameLabel)
        addSubview(locationLabel)
        NSLayoutConstraint.activate([
            nameLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            nameLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),
            nameLabel.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            locationLabel.leadingAnchor.constraint(equalTo: nameLabel.leadingAnchor),
            locationLabel.trailingAnchor.constraint(equalTo: nameLabel.trailingAnchor),
            locationLabel.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 1),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(name: String, location: String) {
        nameLabel.stringValue = name
        locationLabel.stringValue = location
    }
}

/// Selection drawn in the app's own accent rather than the system blue.
private final class RecentRowBackground: NSTableRowView {
    override func drawSelection(in dirtyRect: NSRect) {
        guard selectionHighlightStyle != .none else { return }
        Palette.selection.withAlphaComponent(0.35).setFill()
        bounds.fill()
    }
}
