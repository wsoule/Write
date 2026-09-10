import AppKit
import WriteKit

/// The window's single view: a page of text, a find strip over it, and a
/// footer under it.
final class EditorViewController: NSViewController, NSTextViewDelegate, FindBarDelegate {
    private let document: WriteDocument
    private let scrollView = NSScrollView()
    private let textView: MarkdownTextView
    private let footer = FooterView(frame: .zero)
    private let findBar = FindBar(frame: .zero)

    private var matches: [NSRange] = []
    private var matchIndex = -1
    private var wordCountTimer: Timer?

    /// The writing column, in characters. 65 is the width Omawrite is built
    /// around and about where prose stops being comfortable to read.
    private let columnCharacters: CGFloat = 65

    init(document: WriteDocument) {
        self.document = document

        let layoutManager = NSLayoutManager()
        let container = NSTextContainer(size: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        container.lineFragmentPadding = 0
        document.textStorage.addLayoutManager(layoutManager)
        layoutManager.addTextContainer(container)
        textView = MarkdownTextView(frame: .zero, textContainer: container)

        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("EditorViewController is created in code")
    }

    deinit {
        wordCountTimer?.invalidate()
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - View

    override func loadView() {
        let root = BackgroundView(frame: NSRect(x: 0, y: 0, width: 1000, height: 720))

        configureTextView()
        configureScrollView()

        footer.translatesAutoresizingMaskIntoConstraints = false
        footer.onSave = { [weak self] in
            NSApp.sendAction(#selector(NSDocument.save(_:)), to: nil, from: self)
        }
        footer.onOpen = { [weak self] in
            NSApp.sendAction(#selector(NSDocumentController.openDocument(_:)), to: nil, from: self)
        }

        findBar.delegate = self
        findBar.translatesAutoresizingMaskIntoConstraints = false

        root.addSubview(scrollView)
        root.addSubview(footer)
        root.addSubview(findBar)

        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: root.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: root.bottomAnchor),

            footer.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            footer.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            footer.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            footer.heightAnchor.constraint(equalToConstant: 34),

            findBar.topAnchor.constraint(equalTo: root.topAnchor, constant: 12),
            findBar.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 12),
            findBar.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -12),
        ])

        view = root
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        applyFontSize()
        refreshWordCount()
        footer.status = document.status

        NotificationCenter.default.addObserver(
            self, selector: #selector(fontSizeDidChange(_:)),
            name: EditorSettings.fontSizeDidChange, object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(statusDidChange(_:)),
            name: WriteDocument.statusDidChange, object: document)
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        view.window?.makeFirstResponder(textView)
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        layOutWritingColumn()
    }

    private func configureTextView() {
        textView.configureForWriting(font: Fonts.editor(size: EditorSettings.fontSize))
        textView.delegate = self
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude,
                                  height: CGFloat.greatestFiniteMagnitude)
    }

    private func configureScrollView() {
        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.drawsBackground = false
        scrollView.autohidesScrollers = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        // Room to keep writing without the caret pinned to the bottom edge,
        // and to keep the last line clear of the footer.
        scrollView.automaticallyAdjustsContentInsets = false
        scrollView.contentInsets = NSEdgeInsets(top: 0, left: 0, bottom: 140, right: 0)
    }

    /// Centres a fixed-width column of text in whatever width the window has.
    private func layOutWritingColumn() {
        let font = Fonts.editor(size: EditorSettings.fontSize)
        let characterWidth = Fonts.characterWidth(of: font)
        let available = scrollView.contentSize.width
        guard available > 0 else { return }

        let column = min((characterWidth * columnCharacters).rounded(),
                         max(360, available - (characterWidth * 20).rounded()))
        let horizontal = max(24, ((available - column) / 2).rounded(.down))
        let vertical = max(42, (view.bounds.height * 0.05).rounded())

        let inset = NSSize(width: horizontal, height: vertical)
        if textView.textContainerInset != inset {
            textView.textContainerInset = inset
            textView.needsDisplay = true
        }
    }

    // MARK: - Font size

    @objc private func fontSizeDidChange(_ notification: Notification) {
        applyFontSize()
    }

    private func applyFontSize() {
        let font = Fonts.editor(size: EditorSettings.fontSize)
        textView.apply(font: font)
        document.highlighter.setBaseFont(font)
        footer.apply(fontSize: EditorSettings.interfaceFontSize)
        layOutWritingColumn()
    }

    @objc func increaseFontSize(_ sender: Any?) {
        EditorSettings.fontSize = EditorSettings.fontSize + 1
    }

    @objc func decreaseFontSize(_ sender: Any?) {
        EditorSettings.fontSize = EditorSettings.fontSize - 1
    }

    @objc func resetFontSize(_ sender: Any?) {
        EditorSettings.fontSize = EditorSettings.defaultSize
    }

    // MARK: - Status and word count

    @objc private func statusDidChange(_ notification: Notification) {
        footer.status = document.status
    }

    private func scheduleWordCount() {
        wordCountTimer?.invalidate()
        wordCountTimer = Timer.scheduledTimer(withTimeInterval: 0.12, repeats: false) {
            [weak self] _ in self?.refreshWordCount()
        }
    }

    private func refreshWordCount() {
        footer.wordCount = WordCount.count(in: textView.string)
    }

    // MARK: - NSTextViewDelegate

    func textDidChange(_ notification: Notification) {
        scheduleWordCount()
        document.noteTextEdited()
        if !findBar.isHidden {
            recomputeMatches(query: findBar.query, keepingIndex: true)
        }
    }

    /// Route undo through the document so its edited state stays honest.
    func undoManager(for view: NSTextView) -> UndoManager? {
        document.undoManager
    }

    // MARK: - Find

    @objc func showFind(_ sender: Any?) {
        findBar.present(showingReplace: false, in: view.window)
        recomputeMatches(query: findBar.query)
    }

    @objc func showFindAndReplace(_ sender: Any?) {
        findBar.present(showingReplace: true, in: view.window)
        recomputeMatches(query: findBar.query)
    }

    @objc func findNext(_ sender: Any?) {
        guard !findBar.isHidden else {
            showFind(sender)
            return
        }
        step(by: 1)
    }

    @objc func findPrevious(_ sender: Any?) {
        guard !findBar.isHidden else {
            showFind(sender)
            return
        }
        step(by: -1)
    }

    func findBar(_ bar: FindBar, didChangeQuery query: String) {
        recomputeMatches(query: query)
    }

    func findBarDidRequestNext(_ bar: FindBar) { step(by: 1) }
    func findBarDidRequestPrevious(_ bar: FindBar) { step(by: -1) }

    func findBar(_ bar: FindBar, replaceCurrentWith replacement: String) {
        guard matches.indices.contains(matchIndex) else { return }
        textView.apply(TextEdit(range: matches[matchIndex], replacement: replacement))
        recomputeMatches(query: bar.query, keepingIndex: true)
    }

    func findBar(_ bar: FindBar, replaceAllWith replacement: String) {
        guard !bar.query.isEmpty, !matches.isEmpty else { return }

        let undoManager = document.undoManager
        undoManager?.beginUndoGrouping()
        // Back to front, so each replacement leaves the earlier offsets intact.
        for range in matches.reversed() {
            textView.apply(TextEdit(range: range, replacement: replacement))
        }
        undoManager?.endUndoGrouping()
        undoManager?.setActionName("Replace All")

        recomputeMatches(query: bar.query)
    }

    func findBarDidClose(_ bar: FindBar) {
        matches = []
        matchIndex = -1
        document.highlighter.setSearch(query: "", currentMatchLocation: nil)
        view.window?.makeFirstResponder(textView)
    }

    private func step(by direction: Int) {
        guard !matches.isEmpty else { return }
        matchIndex = (matchIndex + direction + matches.count) % matches.count
        showCurrentMatch()
    }

    private func recomputeMatches(query: String, keepingIndex: Bool = false) {
        let previousIndex = matchIndex
        matches = ranges(of: query, in: textView.string)

        if matches.isEmpty {
            matchIndex = -1
        } else if keepingIndex, previousIndex >= 0 {
            matchIndex = min(previousIndex, matches.count - 1)
        } else {
            matchIndex = 0
        }
        showCurrentMatch()
    }

    private func showCurrentMatch() {
        let location = matches.indices.contains(matchIndex) ? matches[matchIndex].location : nil
        document.highlighter.setSearch(query: findBar.query, currentMatchLocation: location)
        findBar.showMatches(index: matchIndex, of: matches.count)

        guard matches.indices.contains(matchIndex) else { return }
        textView.setSelectedRange(matches[matchIndex])
        textView.scrollRangeToVisible(matches[matchIndex])
    }

    private func ranges(of query: String, in text: String) -> [NSRange] {
        guard !query.isEmpty else { return [] }

        let string = text as NSString
        var found: [NSRange] = []
        var searchRange = NSRange(location: 0, length: string.length)

        while searchRange.length > 0 {
            let match = string.range(of: query, options: [.caseInsensitive], range: searchRange)
            guard match.location != NSNotFound else { break }

            found.append(match)
            let next = match.location + max(1, match.length)
            guard next < string.length else { break }
            searchRange = NSRange(location: next, length: string.length - next)
        }
        return found
    }
}

/// A plain view that paints the page colour and follows the appearance.
final class BackgroundView: NSView {
    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        layer?.backgroundColor = Palette.page.cgColor
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
    }
}
