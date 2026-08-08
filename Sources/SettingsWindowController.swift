import AppKit

/// A small Settings window to configure the OpenAI-compatible API the grammar
/// checker uses: base URL, model, and API key. Values persist to `Settings`
/// (the app's own defaults) as you type.
final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    static let shared = SettingsWindowController()

    private var baseURLField: NSTextField!
    private var modelField: NSTextField!
    private var apiKeyField: NSSecureTextField!

    private init() { super.init(window: nil) }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func show() {
        if window == nil { buildWindow() }
        loadValues()
        NSApp.activate(ignoringOtherApps: true)
        window?.center()
        window?.makeKeyAndOrderFront(nil)
    }

    private func buildWindow() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 250),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Settings"
        window.isReleasedWhenClosed = false
        window.delegate = self
        self.window = window

        let content = NSView(frame: window.contentView!.bounds)
        content.autoresizingMask = [.width, .height]
        window.contentView = content

        baseURLField = NSTextField()
        baseURLField.placeholderString = Settings.defaultBaseURL
        modelField = NSTextField()
        modelField.placeholderString = Settings.defaultModel
        apiKeyField = NSSecureTextField()
        apiKeyField.placeholderString = "sk-…"

        let rows: [(String, NSTextField)] = [
            ("Base URL", baseURLField),
            ("Model", modelField),
            ("API Key", apiKeyField),
        ]

        let grid = NSGridView(numberOfColumns: 2, rows: 0)
        grid.translatesAutoresizingMaskIntoConstraints = false
        grid.rowSpacing = 14
        grid.columnSpacing = 12
        for (title, field) in rows {
            let label = NSTextField(labelWithString: title)
            label.alignment = .right
            field.translatesAutoresizingMaskIntoConstraints = false
            field.target = self
            field.action = #selector(fieldChanged)
            field.widthAnchor.constraint(equalToConstant: 300).isActive = true
            grid.addRow(with: [label, field])
        }
        grid.column(at: 0).xPlacement = .trailing

        let note = NSTextField(wrappingLabelWithString:
            "Any OpenAI-compatible chat API works. Changes save automatically.")
        note.font = NSFont.systemFont(ofSize: 11)
        note.textColor = .secondaryLabelColor
        note.translatesAutoresizingMaskIntoConstraints = false

        content.addSubview(grid)
        content.addSubview(note)
        NSLayoutConstraint.activate([
            grid.centerXAnchor.constraint(equalTo: content.centerXAnchor),
            grid.topAnchor.constraint(equalTo: content.topAnchor, constant: 28),
            note.leadingAnchor.constraint(equalTo: grid.leadingAnchor),
            note.trailingAnchor.constraint(equalTo: grid.trailingAnchor),
            note.topAnchor.constraint(equalTo: grid.bottomAnchor, constant: 18),
        ])
    }

    private func loadValues() {
        baseURLField.stringValue = UserDefaults.standard.string(forKey: Settings.baseURLKey) ?? ""
        modelField.stringValue = UserDefaults.standard.string(forKey: Settings.modelKey) ?? ""
        apiKeyField.stringValue = Settings.apiKey
    }

    /// Persist on every edit so there is no separate Save step to forget.
    @objc private func fieldChanged() {
        Settings.baseURL = baseURLField.stringValue
        Settings.model = modelField.stringValue
        Settings.apiKey = apiKeyField.stringValue
    }

    func windowWillClose(_ notification: Notification) { fieldChanged() }
}
