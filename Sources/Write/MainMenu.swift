import AppKit

/// The menu bar, built in code so the app has no nib.
enum MainMenu {
    static func install(into application: NSApplication) {
        let mainMenu = NSMenu()
        mainMenu.addItem(appMenuItem(named: applicationName))
        mainMenu.addItem(fileMenuItem())
        mainMenu.addItem(editMenuItem())
        mainMenu.addItem(formatMenuItem())
        mainMenu.addItem(viewMenuItem())

        let windowItem = windowMenuItem()
        mainMenu.addItem(windowItem)
        application.windowsMenu = windowItem.submenu

        let helpItem = helpMenuItem()
        mainMenu.addItem(helpItem)
        application.helpMenu = helpItem.submenu

        application.mainMenu = mainMenu
    }

    private static var applicationName: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "Write"
    }

    // MARK: - Menus

    private static func appMenuItem(named name: String) -> NSMenuItem {
        let menu = NSMenu(title: name)
        menu.addItem(item("About \(name)", #selector(NSApplication.orderFrontStandardAboutPanel(_:))))
        menu.addItem(.separator())

        let services = NSMenu(title: "Services")
        let servicesItem = NSMenuItem(title: "Services", action: nil, keyEquivalent: "")
        servicesItem.submenu = services
        NSApplication.shared.servicesMenu = services
        menu.addItem(servicesItem)
        menu.addItem(.separator())

        menu.addItem(item("Hide \(name)", #selector(NSApplication.hide(_:)), "h"))
        menu.addItem(item("Hide Others", #selector(NSApplication.hideOtherApplications(_:)), "h",
                          [.command, .option]))
        menu.addItem(item("Show All", #selector(NSApplication.unhideAllApplications(_:))))
        menu.addItem(.separator())
        menu.addItem(item("Quit \(name)", #selector(NSApplication.terminate(_:)), "q"))

        return wrap(menu)
    }

    private static func fileMenuItem() -> NSMenuItem {
        let menu = NSMenu(title: "File")
        menu.addItem(item("New", Selector(("newDocument:")), "n"))
        menu.addItem(item("Open…", Selector(("openDocument:")), "o"))
        menu.addItem(item("Open Recent…", Selector(("showRecents:")), "k"))

        let recent = NSMenu(title: "Open Recent")
        // AppKit fills this in once it is identified as the recents menu.
        recent.identifier = NSUserInterfaceItemIdentifier("NSRecentDocumentsMenu")
        recent.addItem(item("Clear Menu", Selector(("clearRecentDocuments:"))))
        let recentItem = NSMenuItem(title: "Open Recent", action: nil, keyEquivalent: "")
        recentItem.submenu = recent
        menu.addItem(recentItem)

        menu.addItem(.separator())
        menu.addItem(item("Close", #selector(NSWindow.performClose(_:)), "w"))
        menu.addItem(item("Save", Selector(("saveDocument:")), "s"))
        menu.addItem(item("Save As…", Selector(("saveDocumentAs:")), "s", [.command, .shift]))
        menu.addItem(item("Duplicate", Selector(("duplicateDocument:")), "s",
                          [.command, .shift, .option]))
        menu.addItem(item("Rename…", Selector(("renameDocument:"))))
        menu.addItem(item("Move To…", Selector(("moveDocument:"))))
        menu.addItem(item("Revert to Saved", Selector(("revertDocumentToSaved:"))))
        menu.addItem(.separator())
        menu.addItem(item("Page Setup…", Selector(("runPageLayout:")), "p", [.command, .shift]))
        menu.addItem(item("Print…", Selector(("printDocument:")), "p"))

        return wrap(menu)
    }

    private static func editMenuItem() -> NSMenuItem {
        let menu = NSMenu(title: "Edit")
        menu.addItem(item("Undo", Selector(("undo:")), "z"))
        menu.addItem(item("Redo", Selector(("redo:")), "z", [.command, .shift]))
        menu.addItem(.separator())
        menu.addItem(item("Cut", Selector(("cut:")), "x"))
        menu.addItem(item("Copy", Selector(("copy:")), "c"))
        menu.addItem(item("Paste", Selector(("paste:")), "v"))
        menu.addItem(item("Paste and Match Style", Selector(("pasteAsPlainText:")), "v",
                          [.command, .shift, .option]))
        menu.addItem(item("Delete", Selector(("delete:"))))
        menu.addItem(item("Select All", Selector(("selectAll:")), "a"))
        menu.addItem(.separator())

        let find = NSMenu(title: "Find")
        find.addItem(item("Find…", Selector(("showFind:")), "f"))
        find.addItem(item("Find and Replace…", Selector(("showFindAndReplace:")), "f",
                          [.command, .option]))
        find.addItem(item("Find Next", Selector(("findNext:")), "g"))
        find.addItem(item("Find Previous", Selector(("findPrevious:")), "g", [.command, .shift]))
        let findItem = NSMenuItem(title: "Find", action: nil, keyEquivalent: "")
        findItem.submenu = find
        menu.addItem(findItem)

        let spelling = NSMenu(title: "Spelling")
        spelling.addItem(item("Show Spelling and Grammar",
                              Selector(("showGuessPanel:")), ":"))
        spelling.addItem(item("Check Document Now", Selector(("checkSpelling:")), ";"))
        spelling.addItem(.separator())
        spelling.addItem(item("Check Spelling While Typing",
                              Selector(("toggleContinuousSpellChecking:"))))
        let spellingItem = NSMenuItem(title: "Spelling", action: nil, keyEquivalent: "")
        spellingItem.submenu = spelling
        menu.addItem(spellingItem)

        return wrap(menu)
    }

    private static func formatMenuItem() -> NSMenuItem {
        let menu = NSMenu(title: "Format")
        menu.addItem(item("Bold", Selector(("toggleBoldMarkdown:")), "b"))
        menu.addItem(item("Italic", Selector(("toggleItalicMarkdown:")), "i"))
        menu.addItem(item("Link", Selector(("insertMarkdownLink:")), "l"))
        return wrap(menu)
    }

    private static func viewMenuItem() -> NSMenuItem {
        let menu = NSMenu(title: "View")
        menu.addItem(item("Bigger Text", Selector(("increaseFontSize:")), "+"))
        menu.addItem(item("Smaller Text", Selector(("decreaseFontSize:")), "-"))
        menu.addItem(item("Actual Size", Selector(("resetFontSize:")), "0"))
        menu.addItem(.separator())
        menu.addItem(item("Enter Full Screen", #selector(NSWindow.toggleFullScreen(_:)), "f",
                          [.command, .control]))
        return wrap(menu)
    }

    private static func windowMenuItem() -> NSMenuItem {
        let menu = NSMenu(title: "Window")
        menu.addItem(item("Minimize", #selector(NSWindow.performMiniaturize(_:)), "m"))
        menu.addItem(item("Zoom", #selector(NSWindow.performZoom(_:))))
        menu.addItem(.separator())
        menu.addItem(item("Bring All to Front", #selector(NSApplication.arrangeInFront(_:))))
        return wrap(menu)
    }

    private static func helpMenuItem() -> NSMenuItem {
        let menu = NSMenu(title: "Help")
        menu.addItem(item("Keyboard Shortcuts", Selector(("showKeyboardShortcuts:")), "/"))
        return wrap(menu)
    }

    // MARK: - Building blocks

    private static func wrap(_ menu: NSMenu) -> NSMenuItem {
        let item = NSMenuItem(title: menu.title, action: nil, keyEquivalent: "")
        item.submenu = menu
        return item
    }

    private static func item(_ title: String, _ action: Selector?, _ keyEquivalent: String = "",
                             _ modifiers: NSEvent.ModifierFlags = .command) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
        if !keyEquivalent.isEmpty {
            item.keyEquivalentModifierMask = modifiers
        }
        return item
    }
}
