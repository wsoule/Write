import AppKit

final class DocumentWindowController: NSWindowController {
    init(document: WriteDocument) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1000, height: 720),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false)

        window.titlebarAppearsTransparent = true
        window.backgroundColor = Palette.page
        window.minSize = NSSize(width: 620, height: 440)
        window.tabbingMode = .preferred
        window.isMovableByWindowBackground = false

        super.init(window: window)

        shouldCascadeWindows = true
        windowFrameAutosaveName = "WriteWindow"
        contentViewController = EditorViewController(document: document)
    }

    required init?(coder: NSCoder) {
        fatalError("DocumentWindowController is created in code")
    }
}
