import AppKit

let application = NSApplication.shared

// Document handling is set up before the menu bar, so File > Open Recent finds
// the document controller that populates it.
_ = NSDocumentController.shared
let appDelegate = AppDelegate()
application.delegate = appDelegate
application.setActivationPolicy(.regular)
MainMenu.install(into: application)
application.run()
