import AppKit
import WebKit
import UniformTypeIdentifiers

/// A standalone, distraction-free writing editor built on a real ProseMirror
/// WYSIWYG surface (bundled offline in `Resources/editor`). Links render as their
/// label with the URL hidden, bold/italic are real, and the document round-trips
/// to Markdown for storage. A sidebar keeps the local draft history.
///
/// Stage 1b: the editor surface + drafts/autosave/theme/font/Dock. The live
/// Hemingway + grammar highlighting is re-bridged as ProseMirror decorations in
/// the next stage; the header already shows the local readability grade and
/// counts, which need no editor integration.
final class WritingEditorWindowController: NSWindowController, NSWindowDelegate, NSTableViewDataSource, NSTableViewDelegate, WKScriptMessageHandler, WKNavigationDelegate, NSMenuDelegate {
    static let shared = WritingEditorWindowController()

    private let store = DraftStore.shared

    private var theme: Theme = .white
    private var webView: WKWebView!
    private var editorPane: NSView!
    private var headerView: NSView!
    private var summaryLabel: NSTextField!
    private var wordCountLabel: NSTextField!
    private var checkingSpinner: NSProgressIndicator!
    private var sidebarToggleButton: NSButton!
    private var headerDivider: NSView!

    // Note / Math mode — a switch in the toolbar swaps the page between the notes
    // editor and the Math Playground (same window, no separate menu).
    private enum Mode { case note, math }
    private var mode: Mode = .note
    private var modeSwitch: NSSegmentedControl!
    private var mathWebView: WKWebView?
    private var mathReady = false
    private var mathSaveWork: DispatchWorkItem?
    private static let modeKey = "editorMode"

    private var sidebarPane: NSView!
    private var groupBar: NSView!
    private var groupButton: NSButton!
    private var newDraftButton: NSButton!
    private var tableView: NSTableView!
    private var grammarToggle: NSButton!

    // Groups (themes). Each draft belongs to one group; the sidebar shows one
    // group at a time so the writer stays focused on a single theme.
    private let groupStore = GroupStore.shared
    private var groups: [WritingGroup] = []
    private var currentGroupID: UUID?
    /// Drafts in the current group, newest first — what the table shows.
    private var visible: [WritingDraft] = []
    private static let currentGroupKey = "currentGroupID"

    /// Distraction-free mode: the drafts sidebar can be collapsed to give the
    /// page the full window. New/Delete/Export then live in the menu bar, and the
    /// header keeps a toggle button so the sidebar is always one click away.
    private var sidebarCollapsed = false
    private var sidebarAnim: Timer?
    private var savedSidebarWidth: CGFloat = WritingEditorWindowController.sidebarWidth
    private static let sidebarCollapsedKey = "sidebarCollapsed"

    private var drafts: [WritingDraft] = []
    private var currentDraft: WritingDraft?

    /// The active surface's plain text that findings and decoration offsets are
    /// measured against. Per-surface (note vs. math) so switching modes keeps
    /// each side's findings and text in sync with what's on screen.
    private var noteLastText = ""
    private var mathLastText = ""
    private var lastText: String {
        get { mode == .math ? mathLastText : noteLastText }
        set { if mode == .math { mathLastText = newValue } else { noteLastText = newValue } }
    }
    /// Math-mode text is assembled from the note blocks; this records, for each
    /// text block, its character range in `mathLastText` so decoration offsets
    /// can be mapped back to the block that owns them.
    private var mathTextRanges: [(index: Int, start: Int, end: Int)] = []

    // Optional model grammar check (Stage 3-ready), layered over the always-on
    // local Hemingway highlights.
    private let client = GrammarClient()
    private var grammarCheckEnabled = false
    /// Model errors currently shown, per surface. Each completed check replaces
    /// this set (relocated into the current text); freshest check is authoritative.
    private var noteStanding: [GrammarError] = []
    private var mathStanding: [GrammarError] = []
    private var standing: [GrammarError] {
        get { mode == .math ? mathStanding : noteStanding }
        set { if mode == .math { mathStanding = newValue } else { noteStanding = newValue } }
    }
    private var checkWork: DispatchWorkItem?
    private var checkTask: URLSessionTask?
    private var checkGeneration = 0
    private var isChecking = false

    /// The editor page fires "ready" once; markdown/theme/font are applied then.
    private var editorReady = false
    private var autosaveWork: DispatchWorkItem?
    private var keyMonitor: Any?
    private let relativeDate = RelativeDateTimeFormatter()

    private static let fontSizeKey = "writingEditorFontSize"
    private static let defaultFontSize: CGFloat = 20
    private static let minFontSize: CGFloat = 14
    private static let maxFontSize: CGFloat = 40
    private static let headerHeight: CGFloat = 46
    private static let toolbarHeight: CGFloat = 44
    private static let sidebarWidth: CGFloat = 244
    private static let headerFont = NSFont.systemFont(ofSize: 14, weight: .semibold)

    private var fontSize: CGFloat = defaultFontSize

    private init() { super.init(window: nil) }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    // MARK: - Presentation

    private var historyLoaded = false

    func show() {
        reloadTheme()
        if window == nil { buildWindow() }
        // Load the draft list exactly once. A second show() — e.g. when a file
        // is opened at launch and applicationDidFinishLaunching also calls show()
        // — must not re-run loadHistory and clobber the just-imported note.
        if !historyLoaded {
            loadHistory(); historyLoaded = true
            if UserDefaults.standard.string(forKey: Self.modeKey) == "math" { setMode(.math) }
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    private func reloadTheme() {
        theme = Theme.current
    }

    private func loadHistory() {
        // Groups first, creating a default one on a fresh install.
        groups = groupStore.load()
        if groups.isEmpty {
            groups = [WritingGroup(name: "Notes", order: 0)]
            groupStore.save(groups)
        }
        let valid = Set(groups.map { $0.id })

        // Adopt any pre-groups or orphaned drafts into the first group.
        drafts = store.allDrafts()
        let fallback = groups[0].id
        for i in drafts.indices where drafts[i].groupID == nil || !valid.contains(drafts[i].groupID!) {
            drafts[i].groupID = fallback
            store.save(drafts[i])
        }

        // Restore the last-open group if it still exists.
        if let saved = UserDefaults.standard.string(forKey: Self.currentGroupKey),
           let id = UUID(uuidString: saved), valid.contains(id) {
            currentGroupID = id
        } else {
            currentGroupID = groups[0].id
        }

        rebuildVisible()
        if let first = visible.first {
            selectRow(0)
            loadDraft(first)
        } else {
            newDraft()
        }
    }

    private func currentGroup() -> WritingGroup? {
        groups.first { $0.id == currentGroupID } ?? groups.first
    }

    /// Recompute the current group's drafts (newest first) and refresh the list.
    private func rebuildVisible() {
        visible = drafts.filter { $0.groupID == currentGroupID }.sorted { $0.updatedAt > $1.updatedAt }
        groupButton?.title = currentGroup()?.name ?? "Notes"
        tableView?.reloadData()
    }

    // MARK: - Construction

    private func buildWindow() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 980, height: 660),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Writing"
        window.minSize = NSSize(width: 640, height: 400)
        let storedSize = UserDefaults.standard.double(forKey: Self.fontSizeKey)
        fontSize = storedSize > 0 ? CGFloat(storedSize) : Self.defaultFontSize
        window.center()
        window.delegate = self
        window.isReleasedWhenClosed = false
        window.backgroundColor = webBackground()
        self.window = window

        let split = NSSplitView(frame: NSRect(x: 0, y: 0, width: 980, height: 660))
        split.isVertical = true
        split.dividerStyle = .thin
        split.autoresizingMask = [.width, .height]
        window.contentView = split

        buildSidebar(in: split)
        buildEditor(in: split)
        split.addArrangedSubview(sidebarPane)
        split.addArrangedSubview(editorPane)
        split.setHoldingPriority(.defaultHigh, forSubviewAt: 0)

        layoutSidebar()
        layoutEditor()

        // Restore the collapsed sidebar if that's how it was left.
        if UserDefaults.standard.bool(forKey: Self.sidebarCollapsedKey) {
            sidebarCollapsed = true
            sidebarPane.removeFromSuperview()
            split.adjustSubviews()
        }
        updateSidebarToggleButton()
    }

    private func buildSidebar(in split: NSSplitView) {
        let pane = NSView(frame: NSRect(x: 0, y: 0, width: Self.sidebarWidth, height: 660))
        pane.postsFrameChangedNotifications = true
        NotificationCenter.default.addObserver(self, selector: #selector(sidebarFrameChanged),
                                               name: NSView.frameDidChangeNotification, object: pane)
        self.sidebarPane = pane

        // Group bar: the current theme's name (a pull-down of all groups) on the
        // left, and a New-note button on the right.
        let bar = NSView(frame: .zero)
        pane.addSubview(bar)
        self.groupBar = bar

        let gb = NSButton(title: "Notes", target: self, action: #selector(groupButtonClicked))
        gb.isBordered = false
        gb.alignment = .left
        gb.font = .systemFont(ofSize: 14, weight: .semibold)
        gb.imagePosition = .imageRight
        gb.image = NSImage(systemSymbolName: "chevron.down", accessibilityDescription: "Switch group")?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 9, weight: .semibold))
        gb.toolTip = "Switch or manage groups"
        bar.addSubview(gb)
        self.groupButton = gb

        let plus = NSButton(title: "", target: self, action: #selector(newDraftClicked))
        plus.image = NSImage(systemSymbolName: "square.and.pencil", accessibilityDescription: "New note")
        plus.imagePosition = .imageOnly
        plus.isBordered = false
        plus.bezelStyle = .regularSquare
        plus.toolTip = "New note (⌘N)"
        bar.addSubview(plus)
        self.newDraftButton = plus

        let scroll = NSScrollView(frame: .zero)
        scroll.borderType = .noBorder
        scroll.hasVerticalScroller = true
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false

        let table = NSTableView(frame: .zero)
        table.headerView = nil
        table.rowHeight = 52
        table.backgroundColor = .clear
        table.dataSource = self
        table.delegate = self
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("draft"))
        column.resizingMask = .autoresizingMask
        table.addTableColumn(column)
        scroll.documentView = table
        pane.addSubview(scroll)
        self.tableView = table

        let rowMenu = NSMenu()
        rowMenu.delegate = self
        table.menu = rowMenu
    }

    private func buildEditor(in split: NSSplitView) {
        let pane = NSView(frame: NSRect(x: 0, y: 0, width: 736, height: 660))
        pane.postsFrameChangedNotifications = true
        NotificationCenter.default.addObserver(self, selector: #selector(editorFrameChanged),
                                               name: NSView.frameDidChangeNotification, object: pane)
        self.editorPane = pane

        let header = NSView(frame: .zero)
        header.wantsLayer = true
        pane.addSubview(header)
        self.headerView = header

        let sbToggle = NSButton(frame: .zero)
        sbToggle.image = NSImage(systemSymbolName: "sidebar.left", accessibilityDescription: "Toggle sidebar")
        sbToggle.imagePosition = .imageOnly
        sbToggle.isBordered = false
        sbToggle.bezelStyle = .regularSquare
        sbToggle.target = self
        sbToggle.action = #selector(toggleSidebar)
        sbToggle.toolTip = "Hide sidebar (⌃⌘S)"
        header.addSubview(sbToggle)
        self.sidebarToggleButton = sbToggle

        let spinner = NSProgressIndicator(frame: .zero)
        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.isDisplayedWhenStopped = false
        header.addSubview(spinner)
        self.checkingSpinner = spinner

        let summary = NSTextField(labelWithString: "")
        summary.font = Self.headerFont
        summary.lineBreakMode = .byTruncatingTail
        header.addSubview(summary)
        self.summaryLabel = summary

        let words = NSTextField(labelWithString: "")
        words.font = Self.headerFont
        words.alignment = .right
        header.addSubview(words)
        self.wordCountLabel = words

        let toggle = NSButton(checkboxWithTitle: "Grammar check", target: self, action: #selector(toggleGrammarCheck))
        toggle.font = Self.headerFont
        grammarCheckEnabled = UserDefaults.standard.bool(forKey: "writingEditorGrammarCheckEnabled")
        toggle.state = grammarCheckEnabled ? .on : .off
        header.addSubview(toggle)
        self.grammarToggle = toggle

        // The mode switch: Note | Math.
        let modes = NSSegmentedControl(labels: ["Note", "Math"], trackingMode: .selectOne,
                                       target: self, action: #selector(modeSwitched))
        modes.segmentStyle = .texturedRounded
        modes.selectedSegment = 0
        modes.font = .systemFont(ofSize: 12, weight: .medium)
        header.addSubview(modes)
        self.modeSwitch = modes

        // A hairline that cleanly separates the header from the page.
        let divider = NSView()
        divider.wantsLayer = true
        header.addSubview(divider)
        self.headerDivider = divider

        // Center every control on one line with Auto Layout — fixed frames let the
        // icon, labels and checkbox drift vertically. Centering removes the drift.
        for v in [sbToggle, modes, spinner, summary, words, toggle, divider] as [NSView] {
            v.translatesAutoresizingMaskIntoConstraints = false
        }
        summary.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        NSLayoutConstraint.activate([
            sbToggle.leadingAnchor.constraint(equalTo: header.leadingAnchor, constant: 14),
            sbToggle.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            sbToggle.widthAnchor.constraint(equalToConstant: 24),
            sbToggle.heightAnchor.constraint(equalToConstant: 22),

            modes.leadingAnchor.constraint(equalTo: sbToggle.trailingAnchor, constant: 10),
            modes.centerYAnchor.constraint(equalTo: header.centerYAnchor),

            spinner.leadingAnchor.constraint(equalTo: modes.trailingAnchor, constant: 12),
            spinner.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            spinner.widthAnchor.constraint(equalToConstant: 15),
            spinner.heightAnchor.constraint(equalToConstant: 15),

            summary.leadingAnchor.constraint(equalTo: spinner.trailingAnchor, constant: 8),
            summary.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            summary.trailingAnchor.constraint(lessThanOrEqualTo: toggle.leadingAnchor, constant: -12),

            toggle.trailingAnchor.constraint(equalTo: words.leadingAnchor, constant: -12),
            toggle.centerYAnchor.constraint(equalTo: header.centerYAnchor),

            words.trailingAnchor.constraint(equalTo: header.trailingAnchor, constant: -14),
            words.centerYAnchor.constraint(equalTo: header.centerYAnchor),
            words.widthAnchor.constraint(equalToConstant: 96),

            divider.leadingAnchor.constraint(equalTo: header.leadingAnchor),
            divider.trailingAnchor.constraint(equalTo: header.trailingAnchor),
            divider.bottomAnchor.constraint(equalTo: header.bottomAnchor),
            divider.heightAnchor.constraint(equalToConstant: 1),
        ])

        let config = WKWebViewConfiguration()
        config.userContentController.add(self, name: "editor")
        let web = WKWebView(frame: .zero, configuration: config)
        web.navigationDelegate = self
        // Public API (macOS 12+) — the page's own themed background covers the
        // view. Avoids the private `drawsBackground` KVC, which can raise.
        web.underPageBackgroundColor = webBackground()
        pane.addSubview(web)
        self.webView = web

        if let url = Bundle.main.url(forResource: "index", withExtension: "html", subdirectory: "editor") {
            web.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        } else {
            NSLog("SimpleWriting: editor bundle missing from app Resources/editor")
        }
    }

    // MARK: - Layout

    @objc private func sidebarFrameChanged() { layoutSidebar() }
    @objc private func editorFrameChanged() { layoutEditor() }

    private func layoutSidebar() {
        guard let pane = sidebarPane else { return }
        let bounds = pane.bounds
        groupBar.frame = NSRect(x: 0, y: bounds.height - Self.toolbarHeight, width: bounds.width, height: Self.toolbarHeight)
        let pad: CGFloat = 14
        let h: CGFloat = 26
        let y = ((Self.toolbarHeight - h) / 2).rounded()
        let plusW: CGFloat = 28
        newDraftButton.frame = NSRect(x: bounds.width - pad - plusW, y: y, width: plusW, height: h)
        groupButton.frame = NSRect(x: pad, y: y, width: max(0, newDraftButton.frame.minX - pad - 6), height: h)
        tableView.enclosingScrollView?.frame = NSRect(x: 0, y: 0, width: bounds.width, height: bounds.height - Self.toolbarHeight)
    }

    private func layoutEditor() {
        guard let pane = editorPane else { return }
        let bounds = pane.bounds
        // The header bar; its controls are centered via Auto Layout (see buildEditor).
        headerView.frame = NSRect(x: 0, y: bounds.height - Self.headerHeight, width: bounds.width, height: Self.headerHeight)
        let content = NSRect(x: 0, y: 0, width: bounds.width, height: bounds.height - Self.headerHeight)
        webView.frame = content
        mathWebView?.frame = content
    }

    // MARK: - Theme / font

    private func webBackground() -> NSColor {
        theme.isDark ? NSColor(calibratedWhite: 0.105, alpha: 1) : NSColor(calibratedWhite: 0.99, alpha: 1)
    }

    private func applyThemeToWeb() {
        window?.appearance = NSAppearance(named: theme.appearanceName)
        window?.backgroundColor = webBackground()
        headerView.layer?.backgroundColor = webBackground().cgColor
        headerDivider.layer?.backgroundColor = (theme.isDark
            ? NSColor(calibratedWhite: 1, alpha: 0.08) : NSColor(calibratedWhite: 0, alpha: 0.07)).cgColor
        summaryLabel.textColor = theme.readableSecondaryText
        wordCountLabel.textColor = theme.readableTertiaryText
        sidebarToggleButton.contentTintColor = theme.readableSecondaryText
        webView.evaluateJavaScript("window.editorSetTheme(\(theme.isDark ? "true" : "false"))")
        if mathReady { mathWebView?.evaluateJavaScript("window.mathSetTheme(\(theme.isDark ? "true" : "false"))") }
    }

    private func applyFontToWeb() {
        webView.evaluateJavaScript("window.editorSetFontSize(\(Int(fontSize)))")
    }

    @objc func zoomIn() { setFontSize(fontSize + 2) }
    @objc func zoomOut() { setFontSize(fontSize - 2) }
    @objc func actualSize() { setFontSize(Self.defaultFontSize) }

    private func setFontSize(_ size: CGFloat) {
        let clamped = min(Self.maxFontSize, max(Self.minFontSize, size))
        guard clamped != fontSize else { return }
        fontSize = clamped
        UserDefaults.standard.set(Double(fontSize), forKey: Self.fontSizeKey)
        applyFontToWeb()
    }

    // MARK: - Sidebar collapse

    @objc func toggleSidebar() {
        guard let split = window?.contentView as? NSSplitView else { return }
        sidebarAnim?.invalidate(); sidebarAnim = nil
        sidebarCollapsed.toggle()
        UserDefaults.standard.set(sidebarCollapsed, forKey: Self.sidebarCollapsedKey)
        updateSidebarToggleButton()
        if sidebarCollapsed {
            let from = sidebarPane.frame.width
            if from > 0 { savedSidebarWidth = from }
            animateDivider(from: from, to: 0) { [weak self] in
                guard let self, let split = self.window?.contentView as? NSSplitView else { return }
                // Remove the pane at the end so its 1px divider goes with it.
                self.sidebarPane.removeFromSuperview()
                split.adjustSubviews()
                self.layoutEditor()
            }
        } else {
            if sidebarPane.superview == nil {
                split.insertArrangedSubview(sidebarPane, at: 0)
                split.setHoldingPriority(.defaultHigh, forSubviewAt: 0)
            }
            split.setPosition(0, ofDividerAt: 0)
            animateDivider(from: 0, to: savedSidebarWidth) { [weak self] in self?.layoutEditor() }
        }
    }

    /// A quick easeOut slide of the divider — motion with a purpose (~0.2s), and
    /// instant when the system asks for reduced motion.
    private func animateDivider(from: CGFloat, to: CGFloat, completion: @escaping () -> Void) {
        guard let split = window?.contentView as? NSSplitView else { completion(); return }
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            split.setPosition(to, ofDividerAt: 0); completion(); return
        }
        let duration: TimeInterval = 0.2
        let startTime = Date()
        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] t in
            guard let self else { t.invalidate(); return }
            let p = min(1, Date().timeIntervalSince(startTime) / duration)
            let eased = 1 - pow(1 - p, 3) // easeOutCubic — quick, then settles
            split.setPosition(from + (to - from) * CGFloat(eased), ofDividerAt: 0)
            if p >= 1 { t.invalidate(); self.sidebarAnim = nil; completion() }
        }
        sidebarAnim = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func updateSidebarToggleButton() {
        sidebarToggleButton?.toolTip = sidebarCollapsed ? "Show sidebar (⌃⌘S)" : "Hide sidebar (⌃⌘S)"
    }

    // MARK: - Open / import

    /// Entry point for files opened from Finder — make sure the window exists,
    /// bring it forward, and import.
    func openExternalFiles(_ urls: [URL]) {
        if window == nil { show() }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        importFiles(urls)
    }

    @objc func openFileClicked() {
        guard let window else { return }
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        var types: [UTType] = [.plainText, .text]
        if let md = UTType(filenameExtension: "md") { types.append(md) }
        if let markdown = UTType(filenameExtension: "markdown") { types.append(markdown) }
        panel.allowedContentTypes = types
        panel.message = "Open a Markdown file as a note"
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let self else { return }
            self.importFiles(panel.urls)
        }
    }

    /// Copy each file's Markdown into a new note in the current group. The file
    /// itself is left untouched — the note is a self-contained copy, like a
    /// notes app that imports rather than links.
    private func importFiles(_ urls: [URL]) {
        flushCurrent()
        var firstImported: WritingDraft?
        for url in urls {
            let content = (try? String(contentsOf: url, encoding: .utf8)) ?? (try? String(contentsOf: url))
            guard let body = content, !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
            let draft = WritingDraft(body: body, groupID: currentGroupID)
            drafts.insert(draft, at: 0)
            store.save(draft)
            if firstImported == nil { firstImported = draft }
        }
        rebuildVisible()
        if let draft = firstImported {
            currentDraft = draft
            if let row = visible.firstIndex(where: { $0.id == draft.id }) { selectRow(row) }
            loadDraft(draft)
        }
    }

    // MARK: - Export

    /// A filename-safe base name for exports, taken from the draft's title.
    private func exportBaseName() -> String {
        let raw = currentDraft?.displayTitle ?? "Untitled"
        let cleaned = raw.components(separatedBy: CharacterSet(charactersIn: "/\\:")).joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "Untitled" : cleaned
    }

    @objc func exportMarkdown() {
        guard let window else { return }
        webView.evaluateJavaScript("window.editorGetMarkdown ? window.editorGetMarkdown() : ''") { [weak self] result, _ in
            guard let self else { return }
            let markdown = (result as? String) ?? ""
            let panel = NSSavePanel()
            panel.allowedContentTypes = [UTType(filenameExtension: "md") ?? .plainText]
            panel.nameFieldStringValue = "\(self.exportBaseName()).md"
            panel.beginSheetModal(for: window) { response in
                guard response == .OK, let url = panel.url else { return }
                try? markdown.write(to: url, atomically: true, encoding: .utf8)
            }
        }
    }

    @objc func exportPDF() {
        guard let window, let web = webView else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.pdf]
        panel.nameFieldStringValue = "\(exportBaseName()).pdf"
        panel.beginSheetModal(for: window) { response in
            guard response == .OK, let url = panel.url else { return }
            let info = NSPrintInfo()
            info.paperSize = NSSize(width: 612, height: 792) // US Letter, 72 dpi
            info.topMargin = 56; info.bottomMargin = 56
            info.leftMargin = 64; info.rightMargin = 64
            info.horizontalPagination = .fit
            info.verticalPagination = .automatic
            info.isHorizontallyCentered = false
            info.isVerticallyCentered = false
            info.jobDisposition = .save
            info.dictionary()[NSPrintInfo.AttributeKey.jobSavingURL] = url as NSURL
            let op = web.printOperation(with: info)
            op.showsPrintPanel = false
            op.showsProgressPanel = false
            op.run()
        }
    }

    /// Keep the sidebar-toggle menu item's title in step with the current state.
    @objc func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(toggleSidebar) {
            menuItem.title = sidebarCollapsed ? "Show Sidebar" : "Hide Sidebar"
        }
        return true
    }

    // MARK: - Draft lifecycle

    @objc func newDraftClicked() { newDraft() }

    private func newDraft() {
        flushCurrent()
        drafts.removeAll { $0.isEmpty && $0.id != currentDraft?.id }
        var draft = WritingDraft()
        draft.groupID = currentGroupID
        drafts.insert(draft, at: 0)
        currentDraft = draft
        rebuildVisible()
        selectRow(0)
        loadDraft(draft)
        webView.evaluateJavaScript("window.editorFocus()")
    }

    @objc func deleteDraftClicked() {
        guard let draft = currentDraft else { return }
        autosaveWork?.cancel()
        store.delete(draft.id)
        drafts.removeAll { $0.id == draft.id }
        currentDraft = nil
        rebuildVisible()
        if visible.isEmpty { newDraft() } else { selectRow(0); loadDraft(visible[0]) }
    }

    // MARK: - Groups

    @objc private func groupButtonClicked() {
        let menu = NSMenu()
        for g in groups {
            let item = menu.addItem(withTitle: g.name, action: #selector(selectGroupMenu(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = g.id.uuidString
            item.state = (g.id == currentGroupID) ? .on : .off
        }
        menu.addItem(.separator())
        let name = currentGroup()?.name ?? ""
        let ng = menu.addItem(withTitle: "New Group…", action: #selector(newGroupClicked), keyEquivalent: ""); ng.target = self
        let rn = menu.addItem(withTitle: "Rename “\(name)”…", action: #selector(renameCurrentGroup), keyEquivalent: ""); rn.target = self
        let del = menu.addItem(withTitle: "Delete “\(name)”", action: #selector(deleteCurrentGroup), keyEquivalent: ""); del.target = self
        del.isEnabled = groups.count > 1
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: groupButton.bounds.height + 4), in: groupButton)
    }

    @objc private func selectGroupMenu(_ sender: NSMenuItem) {
        guard let s = sender.representedObject as? String, let id = UUID(uuidString: s) else { return }
        switchGroup(to: id)
    }

    private func switchGroup(to id: UUID) {
        guard id != currentGroupID else { return }
        flushCurrent()
        drafts.removeAll { $0.isEmpty && $0.id != currentDraft?.id }
        currentGroupID = id
        UserDefaults.standard.set(id.uuidString, forKey: Self.currentGroupKey)
        rebuildVisible()
        if let first = visible.first { selectRow(0); loadDraft(first) } else { newDraft() }
    }

    @objc func newGroupClicked() {
        guard let name = promptForName(title: "New Group", initial: "") else { return }
        let order = (groups.map { $0.order }.max() ?? -1) + 1
        let group = WritingGroup(name: name, order: order)
        groups.append(group)
        groupStore.save(groups)
        switchGroup(to: group.id)
    }

    @objc private func renameCurrentGroup() {
        guard let g = currentGroup(), let name = promptForName(title: "Rename Group", initial: g.name) else { return }
        if let i = groups.firstIndex(where: { $0.id == g.id }) {
            groups[i].name = name
            groupStore.save(groups)
        }
        groupButton.title = name
    }

    @objc private func deleteCurrentGroup() {
        guard groups.count > 1, let g = currentGroup() else { return }
        let target = groups.first { $0.id != g.id }!
        let count = drafts.filter { $0.groupID == g.id && !$0.isEmpty }.count
        let alert = NSAlert()
        alert.messageText = "Delete “\(g.name)”?"
        alert.informativeText = count == 0
            ? "This group is empty."
            : "Its \(count) note\(count == 1 ? "" : "s") will move to “\(target.name)”."
        alert.addButton(withTitle: "Delete")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        for i in drafts.indices where drafts[i].groupID == g.id {
            drafts[i].groupID = target.id
            if !drafts[i].isEmpty { store.save(drafts[i]) }
        }
        groups.removeAll { $0.id == g.id }
        groupStore.save(groups)
        switchGroup(to: target.id)
    }

    // MARK: - Row context menu (move / delete a note)

    func menuNeedsUpdate(_ menu: NSMenu) {
        guard menu === tableView.menu else { return }
        menu.removeAllItems()
        let row = tableView.clickedRow
        guard row >= 0, row < visible.count else { return }
        let draft = visible[row]
        let move = NSMenuItem(title: "Move to", action: nil, keyEquivalent: "")
        let sub = NSMenu()
        for g in groups where g.id != draft.groupID {
            let item = sub.addItem(withTitle: g.name, action: #selector(moveClickedDraft(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = [draft.id.uuidString, g.id.uuidString]
        }
        move.submenu = sub
        move.isEnabled = !sub.items.isEmpty
        menu.addItem(move)
        menu.addItem(.separator())
        let del = menu.addItem(withTitle: "Delete", action: #selector(deleteClickedDraft(_:)), keyEquivalent: "")
        del.target = self
        del.representedObject = draft.id.uuidString
    }

    @objc private func moveClickedDraft(_ sender: NSMenuItem) {
        guard let pair = sender.representedObject as? [String], pair.count == 2,
              let did = UUID(uuidString: pair[0]), let gid = UUID(uuidString: pair[1]) else { return }
        if currentDraft?.id == did { currentDraft?.groupID = gid }
        if let i = drafts.firstIndex(where: { $0.id == did }) {
            drafts[i].groupID = gid
            if !drafts[i].isEmpty { store.save(drafts[i]) }
        }
        rebuildVisible()
        if !visible.contains(where: { $0.id == currentDraft?.id }) {
            if let first = visible.first { selectRow(0); loadDraft(first) } else { newDraft() }
        }
    }

    @objc private func deleteClickedDraft(_ sender: NSMenuItem) {
        guard let s = sender.representedObject as? String, let id = UUID(uuidString: s) else { return }
        autosaveWork?.cancel()
        store.delete(id)
        drafts.removeAll { $0.id == id }
        if currentDraft?.id == id { currentDraft = nil }
        rebuildVisible()
        if currentDraft == nil {
            if visible.isEmpty { newDraft() } else { selectRow(0); loadDraft(visible[0]) }
        }
    }

    private func promptForName(title: String, initial: String) -> String? {
        let alert = NSAlert()
        alert.messageText = title
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
        field.stringValue = initial
        alert.accessoryView = field
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        let name = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? nil : name
    }

    private func flushCurrent() {
        autosaveWork?.cancel()
        autosaveWork = nil
        guard let draft = currentDraft else { return }
        if draft.isEmpty { store.delete(draft.id) } else { store.save(draft) }
    }

    private func loadDraft(_ draft: WritingDraft) {
        currentDraft = draft
        cancelGrammarCheck()
        standing = []
        if editorReady {
            setWebMarkdown(draft.body)
            refreshDecorationsFromEditor()
        }
    }

    private func setWebMarkdown(_ markdown: String) {
        webView.evaluateJavaScript("window.editorSetMarkdown(\(jsString(markdown)))")
    }

    private func scheduleAutosave() {
        autosaveWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, let draft = self.currentDraft, !draft.isEmpty else { return }
            self.store.save(draft)
        }
        autosaveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: work)
    }

    private func updateHeader(findings: [GrammarError], text: String) {
        var summary = LocalStyleDetector.summaryLine(errors: findings, text: text)
        let showSpinner = grammarCheckEnabled && client.isConfigured && isChecking
        if grammarCheckEnabled {
            if !client.isConfigured { summary += " · add an API key for grammar check" }
            else if isChecking { summary += " · checking grammar…" }
        }
        summaryLabel.stringValue = summary
        if showSpinner { checkingSpinner.startAnimation(nil) } else { checkingSpinner.stopAnimation(nil) }
        let count = LocalStyleDetector.wordCount(in: text)
        wordCountLabel.stringValue = "\(count) word\(count == 1 ? "" : "s")"
    }

    /// Recompute findings (local + optional model) for the current text and push
    /// them to the editor as decorations, and refresh the header.
    private func recomputeAndSend() {
        let text = lastText
        let local = LocalStyleDetector.localFindings(in: text)
        let findings: [GrammarError]
        if grammarCheckEnabled {
            // Re-locate standing errors in the *current* text so editing one error
            // doesn't drop the others (offsets shift; fragments remain); a fragment
            // that's now gone (edited away) is pruned here.
            standing = FindingMerge.relocate(standing, in: text)
            findings = FindingMerge.mergeLocalFindings(into: standing, local: local)
        } else {
            findings = local
        }
        sendDecorations(findings, text: text)
        updateHeader(findings: findings, text: text)
    }

    private func sendDecorations(_ findings: [GrammarError], text: String) {
        let ns = text as NSString
        var items: [[String: Any]] = []
        for error in findings {
            let range = error.range
            guard range.location >= 0, NSMaxRange(range) <= ns.length, range.length > 0 else { continue }
            let fill = HemingwayPalette.fillColor(for: error, dark: theme.isDark)
            let accent = HemingwayPalette.color(for: error, dark: theme.isDark)
            // Two orthogonal channels so errors and suggestions are always both
            // visible, even on the same words: errors are a wavy underline;
            // suggestions are a soft highlight fill.
            let style: String
            if error.kind == .error {
                style = "text-decoration: underline; text-decoration-style: wavy; text-decoration-color: \(cssColor(accent, opaque: true)); text-decoration-thickness: 2px; text-underline-offset: 3px"
            } else if error.scope == .sentence {
                style = "border-bottom: 2px solid \(cssColor(accent, opaque: true))"
            } else {
                style = "background-color: \(cssColor(fill))"
            }
            let severity = error.kind == .error ? "Required" : "Optional"
            let title = "\(severity) · \(error.scope.label) · \(error.focus.label) — \(error.type)"
            let hint = error.hint.isEmpty ? "No further hint for this one — you've got it." : error.hint
            var item: [String: Any] = [
                "from": range.location, "to": NSMaxRange(range),
                "style": style, "accent": cssColor(accent, opaque: true),
                "title": title, "hint": hint,
            ]
            // In Math mode the text spans several note blocks: translate the
            // global range to the owning block and a block-local range.
            if mode == .math {
                guard let b = mathTextRanges.first(where: { range.location >= $0.start && range.location < $0.end }) else { continue }
                item["block"] = b.index
                item["from"] = range.location - b.start
                item["to"] = min(NSMaxRange(range), b.end) - b.start
            }
            items.append(item)
        }
        guard let data = try? JSONSerialization.data(withJSONObject: items),
              let json = String(data: data, encoding: .utf8) else { return }
        let fn = (mode == .math) ? "window.mathSetDecorations" : "window.editorSetDecorations"
        let target = (mode == .math) ? mathWebView : webView
        target?.evaluateJavaScript("\(fn)(\(json))")
    }

    /// Pull the editor's plain text back (ProseMirror `textContent`) so findings
    /// and decoration offsets line up, then recompute. Used after a draft loads.
    private func refreshDecorationsFromEditor() {
        webView.evaluateJavaScript("window.editorGetText ? window.editorGetText() : ''") { [weak self] result, _ in
            guard let self else { return }
            self.lastText = (result as? String) ?? ""
            self.recomputeAndSend()
            if self.grammarCheckEnabled { self.scheduleGrammarCheck() }
        }
    }

    private func cssColor(_ color: NSColor, opaque: Bool = false) -> String {
        let c = color.usingColorSpace(.sRGB) ?? color
        let r = Int((c.redComponent * 255).rounded())
        let g = Int((c.greenComponent * 255).rounded())
        let b = Int((c.blueComponent * 255).rounded())
        return opaque ? "rgb(\(r),\(g),\(b))" : "rgba(\(r),\(g),\(b),\(String(format: "%.2f", c.alphaComponent)))"
    }

    // MARK: - Optional model grammar check

    @objc private func toggleGrammarCheck() {
        grammarCheckEnabled = grammarToggle.state == .on
        UserDefaults.standard.set(grammarCheckEnabled, forKey: "writingEditorGrammarCheckEnabled")
        if grammarCheckEnabled {
            scheduleGrammarCheck()
        } else {
            cancelGrammarCheck()
            standing = []
            recomputeAndSend()
        }
    }

    private func cancelGrammarCheck() {
        checkWork?.cancel(); checkWork = nil
        checkTask?.cancel(); checkTask = nil
        checkGeneration += 1
        isChecking = false
    }

    private func scheduleGrammarCheck() {
        cancelGrammarCheck()
        guard grammarCheckEnabled, client.isConfigured else { recomputeAndSend(); return }
        let text = lastText
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let generation = checkGeneration
        let work = DispatchWorkItem { [weak self] in
            guard let self, generation == self.checkGeneration else { return }
            self.isChecking = true
            self.recomputeAndSend() // shows "· checking…"
            WriterLog.log("REQUEST (\(text.count) chars): <<<\(text)>>>")
            self.checkTask = self.client.check(text: text) { [weak self] result in
                DispatchQueue.main.async {
                    guard let self, generation == self.checkGeneration else { return }
                    self.isChecking = false
                    self.checkTask = nil
                    switch result {
                    case .success(let e): WriterLog.log("RESPONSE fragments=\(e.map { $0.fragment })")
                    case .failure(let e): WriterLog.log("RESPONSE error=\(e.localizedDescription)")
                    }
                    if case .success(let freshErrors) = result {
                        // The completed check is authoritative for the text it saw.
                        // A check only ever fires while the writer is editing, so on
                        // stable text there is exactly one check and no second opinion
                        // to reconcile against — the freshest result IS the truth.
                        // Relocate its findings into the current text (the writer may
                        // have typed while it ran) and replace. Temperature 0 already
                        // makes the check deterministic; carrying old flags across
                        // checks (the previous region-scoped reconcile) only froze
                        // fixed/false flags on screen forever.
                        self.standing = FindingMerge.relocate(freshErrors, in: self.lastText)
                        WriterLog.log("DISPLAY standing=\(self.standing.map { $0.fragment })")
                    }
                    self.recomputeAndSend()
                }
            }
        }
        checkWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.7, execute: work)
    }

    // MARK: - Editor bridge

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any], let type = body["type"] as? String else { return }
        if message.name == "math" { handleMathMessage(type: type, body: body); return }
        switch type {
        case "ready":
            editorReady = true
            applyThemeToWeb()
            applyFontToWeb()
            if let draft = currentDraft {
                setWebMarkdown(draft.body)
                refreshDecorationsFromEditor()
            }
        case "change":
            handleChange(markdown: body["markdown"] as? String ?? "", text: body["text"] as? String ?? "")
        case "requestLink":
            promptForLink()
        case "openLink":
            if let href = body["href"] as? String { openLink(href) }
        default:
            break
        }
    }

    // MARK: - Math mode

    /// The note whose math the page is currently showing. The math web view keeps
    /// its DOM (and decorations) while hidden, so we only reload when the note
    /// actually changes — re-entering Math for the same note leaves it intact.
    private var mathLoadedDraftID: UUID?
    private var mathGrammarWork: DispatchWorkItem?

    /// Push the current note's math notebook into the page — only when the note
    /// changed. Math is per-note, so this also resets the math grammar state.
    private func loadMathForCurrentDraft() {
        guard mathReady, currentDraft?.id != mathLoadedDraftID else { return }
        mathLoadedDraftID = currentDraft?.id
        mathStanding = []; mathLastText = ""; mathTextRanges = []
        let json = currentDraft?.mathJSON ?? "[]"
        mathWebView?.evaluateJavaScript("window.mathLoad(\(jsString(json)))")
    }

    @objc private func modeSwitched() {
        setMode(modeSwitch.selectedSegment == 1 ? .math : .note)
    }

    private func setMode(_ newMode: Mode) {
        mode = newMode
        modeSwitch?.selectedSegment = (newMode == .math) ? 1 : 0
        UserDefaults.standard.set(newMode == .math ? "math" : "note", forKey: Self.modeKey)
        let isMath = (newMode == .math)
        // Grammar check works in both modes now; only the word count is note-only.
        wordCountLabel?.isHidden = isMath
        for v: NSView? in [checkingSpinner, summaryLabel, grammarToggle] { v?.isHidden = false }
        if isMath {
            ensureMathWebView()
            webView.isHidden = true
            mathWebView?.isHidden = false
            loadMathForCurrentDraft() // show this note's math (no-op until the page is ready)
        } else {
            mathWebView?.isHidden = true
            webView.isHidden = false
        }
        // Refresh the header to the surface we just switched to (its own findings).
        updateHeader(findings: standing, text: lastText)
        layoutEditor()
    }

    /// Assemble the grammar text from a math notebook's note blocks, recording each
    /// block's character range so decorations can be mapped back. Note blocks are
    /// joined by a blank line; math and graph blocks are skipped.
    private func mathGrammarText(from blocks: [[String: Any]]) -> (text: String, ranges: [(index: Int, start: Int, end: Int)]) {
        var combined = ""
        var ranges: [(Int, Int, Int)] = []
        var textIndex = 0
        for b in blocks where (b["type"] as? String) == "text" {
            let value = (b["value"] as? String) ?? ""
            // Blank out inline math ($…$) so the checker never flags a formula.
            // Same length, so decoration offsets still map onto the raw source.
            let masked = Self.maskInlineMath(value)
            let start = (combined as NSString).length
            combined += masked
            ranges.append((textIndex, start, (combined as NSString).length))
            combined += "\n\n" // keep blocks distinct; whitespace, so never flagged
            textIndex += 1
        }
        return (combined, ranges)
    }

    private static let inlineMathRegex = try? NSRegularExpression(pattern: "\\$[^$\\n]+\\$")
    /// Replace each `$…$` run with spaces of equal length.
    private static func maskInlineMath(_ s: String) -> String {
        guard let re = inlineMathRegex else { return s }
        let ns = s as NSString
        let result = NSMutableString(string: s)
        // Replace back-to-front so earlier ranges stay valid.
        for m in re.matches(in: s, range: NSRange(location: 0, length: ns.length)).reversed() {
            result.replaceCharacters(in: m.range, with: String(repeating: " ", count: m.range.length))
        }
        return result as String
    }

    private func ensureMathWebView() {
        guard mathWebView == nil else { return }
        let config = WKWebViewConfiguration()
        config.userContentController.add(self, name: "math")
        let web = WKWebView(frame: webView.frame, configuration: config)
        web.navigationDelegate = self
        web.underPageBackgroundColor = webBackground()
        editorPane.addSubview(web)
        mathWebView = web
        if let url = Bundle.main.url(forResource: "math", withExtension: "html", subdirectory: "math") {
            web.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        } else {
            NSLog("SimpleWriting: math playground bundle missing from Resources/math")
        }
    }

    private func handleMathMessage(type: String, body: [String: Any]) {
        switch type {
        case "ready":
            mathReady = true
            mathWebView?.evaluateJavaScript("window.mathSetTheme(\(theme.isDark ? "true" : "false"))")
            loadMathForCurrentDraft()
        case "change":
            if let blocks = body["blocks"],
               let data = try? JSONSerialization.data(withJSONObject: blocks, options: [.prettyPrinted]),
               let json = String(data: data, encoding: .utf8),
               mode == .math, var draft = currentDraft {
                // Save into the note Math mode is showing. Capture the draft by
                // value so a note switch before the debounce fires still writes it.
                draft.mathJSON = json
                draft.updatedAt = Date()
                currentDraft = draft
                if let i = drafts.firstIndex(where: { $0.id == draft.id }) { drafts[i] = draft }
                mathSaveWork?.cancel()
                let work = DispatchWorkItem { [weak self] in self?.store.save(draft) }
                mathSaveWork = work
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)

                // Grammar-check the note blocks, same pipeline as Note mode.
                if let arr = body["blocks"] as? [[String: Any]] {
                    let built = mathGrammarText(from: arr)
                    let changed = (built.text != lastText)
                    lastText = built.text
                    mathTextRanges = built.ranges
                    mathGrammarWork?.cancel()
                    let gw = DispatchWorkItem { [weak self] in
                        guard let self, self.mode == .math else { return }
                        self.recomputeAndSend()
                        if changed && self.grammarCheckEnabled { self.scheduleGrammarCheck() }
                    }
                    mathGrammarWork = gw
                    // Debounce so the contenteditable isn't rewritten on every keystroke.
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: gw)
                }
            }
        default:
            break
        }
    }

    private func handleChange(markdown: String, text: String) {
        currentDraft?.body = markdown
        currentDraft?.updatedAt = Date()
        if let draft = currentDraft {
            if let i = drafts.firstIndex(where: { $0.id == draft.id }) { drafts[i] = draft }
            // Update the title in place; don't reorder mid-typing (jarring).
            if let v = visible.firstIndex(where: { $0.id == draft.id }) {
                visible[v] = draft
                refreshRowTitle(v)
            }
        }
        lastText = text
        recomputeAndSend()
        scheduleAutosave()
        if grammarCheckEnabled { scheduleGrammarCheck() }
    }

    private func promptForLink() {
        let alert = NSAlert()
        alert.messageText = "Insert link"
        alert.informativeText = "Paste or type the URL:"
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 320, height: 24))
        alert.accessoryView = field
        alert.addButton(withTitle: "Insert")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let url = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !url.isEmpty else { return }
        webView.evaluateJavaScript("window.editorInsertLink(\(jsString(url)))")
    }

    private func openLink(_ string: String) {
        var candidate = string
        if !candidate.contains("://"), !candidate.hasPrefix("mailto:") {
            candidate = candidate.contains("@") ? "mailto:\(candidate)" : "https://\(candidate)"
        }
        guard let url = URL(string: candidate),
              let scheme = url.scheme?.lowercased(),
              ["http", "https", "mailto"].contains(scheme) else { return }
        NSWorkspace.shared.open(url)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        // "ready" is posted from the page once ProseMirror is mounted.
    }

    /// If the web content process is killed (memory pressure, a WebKit fault),
    /// the editor would otherwise go blank/frozen. Reload and re-hydrate.
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        NSLog("SimpleWriting: web content process terminated; reloading")
        if webView === mathWebView {
            mathReady = false
            if let url = Bundle.main.url(forResource: "math", withExtension: "html", subdirectory: "math") {
                webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
            }
        } else {
            editorReady = false
            if let url = Bundle.main.url(forResource: "index", withExtension: "html", subdirectory: "editor") {
                webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
            }
        }
    }

    private func jsString(_ string: String) -> String {
        (try? String(data: JSONEncoder().encode(string), encoding: .utf8)) ?? "\"\""
    }

    // MARK: - Table

    private func selectRow(_ row: Int) {
        guard row >= 0, row < visible.count else { return }
        tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
    }

    private func refreshRowTitle(_ row: Int) {
        guard row >= 0, row < visible.count,
              let cell = tableView.view(atColumn: 0, row: row, makeIfNecessary: false) as? DraftCellView else { return }
        let draft = visible[row]
        cell.configure(
            title: draft.displayTitle,
            subtitle: draft.isEmpty ? "New draft" : relativeDate.localizedString(for: draft.updatedAt, relativeTo: Date()),
            titleColor: theme.primaryText,
            subtitleColor: theme.readableTertiaryText
        )
    }

    func numberOfRows(in tableView: NSTableView) -> Int { visible.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard row < visible.count else { return nil }
        let draft = visible[row]
        let identifier = NSUserInterfaceItemIdentifier("draftCell")
        let cell = tableView.makeView(withIdentifier: identifier, owner: self) as? DraftCellView ?? DraftCellView(identifier: identifier)
        cell.configure(
            title: draft.displayTitle,
            subtitle: draft.isEmpty ? "New draft" : relativeDate.localizedString(for: draft.updatedAt, relativeTo: Date()),
            titleColor: theme.primaryText,
            subtitleColor: theme.readableTertiaryText
        )
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        let row = tableView.selectedRow
        guard row >= 0, row < visible.count else { return }
        if mode == .math { setMode(.note) }   // choosing a note returns to note mode
        guard visible[row].id != currentDraft?.id else { return }
        flushCurrent()
        loadDraft(visible[row])
    }

    // MARK: - Window delegate

    func windowDidBecomeKey(_ notification: Notification) {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, event.modifierFlags.contains(.command) else { return event }
            switch event.charactersIgnoringModifiers?.lowercased() {
            case "=", "+": self.zoomIn(); return nil
            case "-", "_": self.zoomOut(); return nil
            case "0": self.setFontSize(Self.defaultFontSize); return nil
            default: return event
            }
        }
    }

    func windowWillClose(_ notification: Notification) {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor); self.keyMonitor = nil }
        flushCurrent()
    }
}

/// A two-line history row: draft title above, a relative timestamp below.
private final class DraftCellView: NSTableCellView {
    private let titleLabel = NSTextField(labelWithString: "")
    private let subtitleLabel = NSTextField(labelWithString: "")

    init(identifier: NSUserInterfaceItemIdentifier) {
        super.init(frame: .zero)
        self.identifier = identifier
        titleLabel.font = NSFont.systemFont(ofSize: 14, weight: .semibold)
        titleLabel.lineBreakMode = .byTruncatingTail
        subtitleLabel.font = NSFont.systemFont(ofSize: 12, weight: .regular)
        subtitleLabel.lineBreakMode = .byTruncatingTail
        addSubview(titleLabel)
        addSubview(subtitleLabel)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(title: String, subtitle: String, titleColor: NSColor, subtitleColor: NSColor) {
        titleLabel.stringValue = title
        titleLabel.textColor = titleColor
        subtitleLabel.stringValue = subtitle
        subtitleLabel.textColor = subtitleColor
    }

    override func layout() {
        super.layout()
        let pad: CGFloat = 12
        let width = bounds.width - pad * 2
        titleLabel.frame = NSRect(x: pad, y: bounds.height - 30, width: width, height: 20)
        subtitleLabel.frame = NSRect(x: pad, y: 8, width: width, height: 16)
    }
}
