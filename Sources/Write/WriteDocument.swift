import AppKit
import UniformTypeIdentifiers
import WriteKit

/// One Markdown file.
///
/// `NSDocument` supplies the parts Omawrite hand-rolls on Linux — autosave in
/// place, draft recovery after a crash, the edited dot in the title bar, save
/// sheets and Versions — so what is left here is reading and writing UTF-8,
/// printing, and deciding what to do when the file changes underneath us.
/// The runtime name is pinned so `NSDocumentClass` in Info.plist resolves it
/// without the Swift module prefix.
@objc(WriteDocument)
final class WriteDocument: NSDocument {
    static let statusDidChange = Notification.Name("WriteDocumentStatusDidChange")

    let textStorage = NSTextStorage()

    private(set) lazy var highlighter = MarkdownHighlighter(
        textStorage: textStorage,
        baseFont: Fonts.editor(size: EditorSettings.fontSize))

    /// The line shown in the footer. Transient, never persisted.
    private(set) var status = "" {
        didSet {
            guard status != oldValue else { return }
            NotificationCenter.default.post(name: Self.statusDidChange, object: self)
        }
    }

    private var isPresentingExternalChange = false

    var text: String { textStorage.string }

    // MARK: - Document behaviour

    override class var autosavesInPlace: Bool { true }

    override func makeWindowControllers() {
        addWindowController(DocumentWindowController(document: self))
    }

    /// Typing marks the document dirty. The undo manager normally does this on
    /// its own; the check keeps the change count from being incremented twice
    /// when it does.
    func noteTextEdited() {
        if !isDocumentEdited {
            updateChangeCount(.changeDone)
        }
        status = "Unsaved"
    }

    // MARK: - Reading and writing

    override func data(ofType typeName: String) throws -> Data {
        guard let data = text.data(using: .utf8) else {
            throw NSError(domain: NSCocoaErrorDomain,
                          code: NSFileWriteInapplicableStringEncodingError, userInfo: nil)
        }
        return data
    }

    override func read(from data: Data, ofType typeName: String) throws {
        guard let contents = Self.decode(data) else {
            throw NSError(domain: NSCocoaErrorDomain,
                          code: NSFileReadInapplicableStringEncodingError, userInfo: nil)
        }
        load(contents)
    }

    override func write(to url: URL, ofType typeName: String,
                        for saveOperation: NSDocument.SaveOperationType,
                        originalContentsURL absoluteOriginalContentsURL: URL?) throws {
        try super.write(to: url, ofType: typeName, for: saveOperation,
                        originalContentsURL: absoluteOriginalContentsURL)
        if saveOperation == .saveOperation || saveOperation == .saveAsOperation {
            // Saving can happen off the main thread; the footer reads this.
            DispatchQueue.main.async { [weak self] in
                self?.status = "Saved \(url.lastPathComponent)"
            }
        }
    }

    private func load(_ contents: String) {
        // Touch the highlighter first so it is the storage's delegate before
        // the text lands and needs styling.
        _ = highlighter

        textStorage.beginEditing()
        textStorage.replaceCharacters(in: NSRange(location: 0, length: textStorage.length),
                                      with: contents)
        textStorage.endEditing()
    }

    /// UTF-8 covers everything this app writes; the fallback is for files that
    /// arrived from somewhere else.
    private static func decode(_ data: Data) -> String? {
        if let utf8 = String(data: data, encoding: .utf8) { return utf8 }

        var encoding: UInt = 0
        if let detected = NSString(data: data, usedEncoding: &encoding) as String? {
            return detected
        }
        return String(data: data, encoding: .isoLatin1)
    }

    override func prepareSavePanel(_ savePanel: NSSavePanel) -> Bool {
        if fileURL == nil {
            // Name an untitled draft after its first line, the way you would.
            savePanel.nameFieldStringValue = SuggestedFileName.from(text)
        }
        if let markdown = UTType(filenameExtension: "md") {
            savePanel.allowedContentTypes = [markdown]
        }
        savePanel.allowsOtherFileTypes = true
        return true
    }

    // MARK: - Changes made by other apps

    override func presentedItemDidChange() {
        DispatchQueue.main.async { [weak self] in
            self?.handleExternalChange()
        }
    }

    private func handleExternalChange() {
        guard let url = fileURL else { return }

        let exists = FileManager.default.fileExists(atPath: url.path)
        if exists, let onDisk = modificationDate(of: url), let known = fileModificationDate,
           onDisk <= known {
            // Our own save. The watcher fires on it either way.
            return
        }

        if exists, !isDocumentEdited {
            reloadFromDisk()
            return
        }
        presentExternalChangeAlert(deleted: !exists)
    }

    private func presentExternalChangeAlert(deleted: Bool) {
        guard !isPresentingExternalChange else { return }
        isPresentingExternalChange = true

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = deleted
            ? "\(displayName) was deleted"
            : "\(displayName) changed on disk"
        alert.informativeText = deleted
            ? "The file is gone. Keep what is in this window and save it again, or close the window to let it go."
            : "Another app changed this file. Your unsaved work is still here."
        alert.addButton(withTitle: "Keep Mine")
        if !deleted {
            alert.addButton(withTitle: "Reload from Disk")
        }

        let handle: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            guard let self else { return }
            self.isPresentingExternalChange = false
            if response == .alertSecondButtonReturn {
                self.reloadFromDisk()
            } else {
                self.keepLocalVersion()
            }
        }

        if let window = windowControllers.first?.window {
            alert.beginSheetModal(for: window, completionHandler: handle)
        } else {
            handle(alert.runModal())
        }
    }

    private func reloadFromDisk() {
        guard let url = fileURL, let type = fileType else { return }
        do {
            try revert(toContentsOf: url, ofType: type)
            status = "Reloaded \(url.lastPathComponent)"
        } catch {
            status = "Could not reload \(url.lastPathComponent)"
        }
    }

    private func keepLocalVersion() {
        // Adopt the file's current timestamp so the same change is not
        // reported twice, and make sure the window still counts as dirty.
        if let url = fileURL {
            fileModificationDate = modificationDate(of: url)
        }
        updateChangeCount(.changeDone)
        status = "Kept your version"
    }

    private func modificationDate(of url: URL) -> Date? {
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        return attributes?[.modificationDate] as? Date
    }

    // MARK: - Printing

    override func printOperation(
        withSettings printSettings: [NSPrintInfo.AttributeKey: Any]
    ) throws -> NSPrintOperation {
        let info = (printInfo.copy() as? NSPrintInfo) ?? NSPrintInfo()
        info.dictionary().addEntries(from: printSettings.reduce(into: [AnyHashable: Any]()) {
            $0[$1.key.rawValue] = $1.value
        })
        info.horizontalPagination = .fit
        info.isHorizontallyCentered = false
        info.isVerticallyCentered = false
        info.topMargin = 54
        info.bottomMargin = 54
        info.leftMargin = 54
        info.rightMargin = 54

        let width = info.paperSize.width - info.leftMargin - info.rightMargin
        let printView = NSTextView(frame: NSRect(x: 0, y: 0, width: width, height: width))
        printView.isVerticallyResizable = true
        printView.isHorizontallyResizable = false
        printView.textContainer?.containerSize = NSSize(width: width,
                                                        height: .greatestFiniteMagnitude)
        printView.textContainer?.widthTracksTextView = true
        printView.textContainer?.lineFragmentPadding = 0

        if let storage = printView.textStorage {
            storage.setAttributedString(NSAttributedString(string: text))
            let printHighlighter = MarkdownHighlighter(textStorage: storage,
                                                       baseFont: Fonts.editor(size: 11),
                                                       palette: .printing)
            printHighlighter.highlightAll(in: storage)
            storage.delegate = nil
        }
        printView.sizeToFit()

        let operation = NSPrintOperation(view: printView, printInfo: info)
        operation.jobTitle = displayName
        return operation
    }
}
