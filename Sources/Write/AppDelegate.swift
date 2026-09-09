import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        Fonts.registerBundledFonts()
        NSApp.activate(ignoringOtherApps: false)
    }

    /// A writing app with nothing open is not much use.
    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        true
    }

    @objc func showKeyboardShortcuts(_ sender: Any?) {
        ShortcutsPanel.show()
    }
}
