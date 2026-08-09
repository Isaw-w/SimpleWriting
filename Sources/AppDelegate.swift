import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        installMainMenu()
        WritingEditorWindowController.shared.show()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { WritingEditorWindowController.shared.show() }
        return true
    }

    /// A minimal menu bar. The Edit items target the first responder, so the
    /// WKWebView editor gets standard Copy/Paste/Undo/Select-All shortcuts.
    private func installMainMenu() {
        let mainMenu = NSMenu()

        let appItem = NSMenuItem()
        mainMenu.addItem(appItem)
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About SimpleWriting",
                        action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        let settingsItem = appMenu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hide SimpleWriting", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(withTitle: "Quit SimpleWriting", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu

        // File — draft + export actions, so they stay reachable when the sidebar
        // (which holds New/Delete) is collapsed.
        let editor = WritingEditorWindowController.shared
        let fileItem = NSMenuItem()
        mainMenu.addItem(fileItem)
        let fileMenu = NSMenu(title: "File")
        fileMenu.addItem(withTitle: "New Note", action: #selector(WritingEditorWindowController.newDraftClicked), keyEquivalent: "n").target = editor
        let newGroup = fileMenu.addItem(withTitle: "New Group…", action: #selector(WritingEditorWindowController.newGroupClicked), keyEquivalent: "n")
        newGroup.keyEquivalentModifierMask = [.command, .shift]
        newGroup.target = editor
        fileMenu.addItem(.separator())
        fileMenu.addItem(withTitle: "Export as PDF…", action: #selector(WritingEditorWindowController.exportPDF), keyEquivalent: "e").target = editor
        let mdItem = fileMenu.addItem(withTitle: "Export as Markdown…", action: #selector(WritingEditorWindowController.exportMarkdown), keyEquivalent: "e")
        mdItem.keyEquivalentModifierMask = [.command, .shift]
        mdItem.target = editor
        fileMenu.addItem(.separator())
        fileMenu.addItem(withTitle: "Delete Draft", action: #selector(WritingEditorWindowController.deleteDraftClicked), keyEquivalent: "").target = editor
        fileItem.submenu = fileMenu

        let editItem = NSMenuItem()
        mainMenu.addItem(editItem)
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = editMenu

        // View — collapse the drafts sidebar for distraction-free writing.
        let viewItem = NSMenuItem()
        mainMenu.addItem(viewItem)
        let viewMenu = NSMenu(title: "View")
        let sidebarItem = viewMenu.addItem(withTitle: "Hide Sidebar", action: #selector(WritingEditorWindowController.toggleSidebar), keyEquivalent: "s")
        sidebarItem.keyEquivalentModifierMask = [.command, .control]
        sidebarItem.target = editor
        viewMenu.addItem(.separator())
        viewMenu.addItem(withTitle: "Zoom In", action: #selector(WritingEditorWindowController.zoomIn), keyEquivalent: "+").target = editor
        viewMenu.addItem(withTitle: "Zoom Out", action: #selector(WritingEditorWindowController.zoomOut), keyEquivalent: "-").target = editor
        viewMenu.addItem(withTitle: "Actual Size", action: #selector(WritingEditorWindowController.actualSize), keyEquivalent: "0").target = editor
        viewItem.submenu = viewMenu

        NSApp.mainMenu = mainMenu
    }

    @objc private func openSettings() {
        SettingsWindowController.shared.show()
    }
}
