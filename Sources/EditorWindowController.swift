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
final class WritingEditorWindowController: NSWindowController, NSWindowDelegate, NSTableViewDataSource, NSTableViewDelegate, WKScriptMessageHandler, WKNavigationDelegate {
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

    private var sidebarPane: NSView!
    private var sidebarToolbar: NSView!
    private var tableView: NSTableView!
    private var grammarToggle: NSButton!

    /// Distraction-free mode: the drafts sidebar can be collapsed to give the
    /// page the full window. New/Delete/Export then live in the menu bar, and the
    /// header keeps a toggle button so the sidebar is always one click away.
    private var sidebarCollapsed = false
    private var savedSidebarWidth: CGFloat = WritingEditorWindowController.sidebarWidth
    private static let sidebarCollapsedKey = "sidebarCollapsed"

    private var drafts: [WritingDraft] = []
    private var currentDraft: WritingDraft?

    /// The document's plain text (ProseMirror `textContent`) that findings and
    /// decoration offsets are measured against.
    private var lastText = ""

    // Optional model grammar check (Stage 3-ready), layered over the always-on
    // local Hemingway highlights.
    private let client = GrammarClient()
    private var grammarCheckEnabled = false
    /// Model errors currently shown. Each completed check replaces this set
    /// (relocated into the current text); the freshest check is authoritative.
    private var standing: [GrammarError] = []
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

    func show() {
        reloadTheme()
        if window == nil { buildWindow() }
        loadHistory()
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    private func reloadTheme() {
        theme = Theme.current
    }

    private func loadHistory() {
        drafts = store.allDrafts()
        tableView.reloadData()
        if let first = drafts.first {
            selectRow(0)
            loadDraft(first)
        } else {
            newDraft()
        }
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
            sidebarPane.isHidden = true
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

        let toolbar = NSView(frame: .zero)
        pane.addSubview(toolbar)
        self.sidebarToolbar = toolbar

        func button(_ title: String, _ id: String, _ action: Selector) -> NSButton {
            let b = NSButton(title: title, target: self, action: action)
            b.bezelStyle = .rounded
            b.controlSize = .small
            b.font = .systemFont(ofSize: 12)
            b.identifier = NSUserInterfaceItemIdentifier(id)
            toolbar.addSubview(b)
            return b
        }
        _ = button("New", "newButton", #selector(newDraftClicked))
        let smaller = button("A−", "smallerButton", #selector(zoomOut)); smaller.toolTip = "Smaller text (⌘−)"
        let bigger = button("A+", "biggerButton", #selector(zoomIn)); bigger.toolTip = "Bigger text (⌘+)"
        _ = button("Delete", "deleteButton", #selector(deleteDraftClicked))

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
        sidebarToolbar.frame = NSRect(x: 0, y: bounds.height - Self.toolbarHeight, width: bounds.width, height: Self.toolbarHeight)
        let pad: CGFloat = 12
        let h: CGFloat = 22
        let y = ((Self.toolbarHeight - h) / 2).rounded()
        func frame(_ id: String, _ rect: NSRect) {
            sidebarToolbar.subviews.first { $0.identifier?.rawValue == id }?.frame = rect
        }
        // One evenly-spaced row — New · A− · A+ · Delete — centered in the
        // toolbar so the spacing stays uniform (no stranded button) at any width.
        let items: [(String, CGFloat)] = [
            ("newButton", 52), ("smallerButton", 34), ("biggerButton", 34), ("deleteButton", 58),
        ]
        let totalButtonW = items.reduce(0) { $0 + $1.1 }
        let available = bounds.width - pad * 2
        let gap = max(8, min(16, (available - totalButtonW) / CGFloat(items.count - 1)))
        let groupW = totalButtonW + gap * CGFloat(items.count - 1)
        var x = (pad + max(0, (available - groupW) / 2)).rounded()
        for (id, width) in items {
            frame(id, NSRect(x: x, y: y, width: width, height: h))
            x += width + gap
        }
        tableView.enclosingScrollView?.frame = NSRect(x: 0, y: 0, width: bounds.width, height: bounds.height - Self.toolbarHeight)
    }

    private func layoutEditor() {
        guard let pane = editorPane else { return }
        let bounds = pane.bounds
        headerView.frame = NSRect(x: 0, y: bounds.height - Self.headerHeight, width: bounds.width, height: Self.headerHeight)
        // One centered band so labels, toggle, spinner and count all line up.
        let pad: CGFloat = 16
        let rowH: CGFloat = 22
        let rowY = ((Self.headerHeight - rowH) / 2).rounded()
        let wordWidth: CGFloat = 96
        let toggleWidth: CGFloat = 132
        let spinnerSize: CGFloat = 15

        // Sidebar toggle sits at the far left; the checking band follows it.
        let sbW: CGFloat = 26
        sidebarToggleButton.frame = NSRect(x: pad - 2, y: rowY, width: sbW, height: rowH)
        let bandX = pad - 2 + sbW + 8

        wordCountLabel.frame = NSRect(x: bounds.width - pad - wordWidth, y: rowY, width: wordWidth, height: rowH)
        grammarToggle.frame = NSRect(x: wordCountLabel.frame.minX - 12 - toggleWidth, y: rowY, width: toggleWidth, height: rowH)
        checkingSpinner.frame = NSRect(x: bandX, y: ((Self.headerHeight - spinnerSize) / 2).rounded(), width: spinnerSize, height: spinnerSize)
        let summaryX = bandX + spinnerSize + 8
        summaryLabel.frame = NSRect(x: summaryX, y: rowY, width: max(0, grammarToggle.frame.minX - summaryX - 10), height: rowH)
        webView.frame = NSRect(x: 0, y: 0, width: bounds.width, height: bounds.height - Self.headerHeight)
    }

    // MARK: - Theme / font

    private func webBackground() -> NSColor {
        theme.isDark ? NSColor(calibratedWhite: 0.105, alpha: 1) : NSColor(calibratedWhite: 0.99, alpha: 1)
    }

    private func applyThemeToWeb() {
        window?.appearance = NSAppearance(named: theme.appearanceName)
        window?.backgroundColor = webBackground()
        headerView.layer?.backgroundColor = webBackground().cgColor
        summaryLabel.textColor = theme.readableSecondaryText
        wordCountLabel.textColor = theme.readableTertiaryText
        sidebarToggleButton.contentTintColor = theme.readableSecondaryText
        webView.evaluateJavaScript("window.editorSetTheme(\(theme.isDark ? "true" : "false"))")
    }

    private func applyFontToWeb() {
        webView.evaluateJavaScript("window.editorSetFontSize(\(Int(fontSize)))")
    }

    @objc private func zoomIn() { setFontSize(fontSize + 2) }
    @objc private func zoomOut() { setFontSize(fontSize - 2) }

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
        sidebarCollapsed.toggle()
        if sidebarCollapsed {
            let width = sidebarPane.frame.width
            if width > 0 { savedSidebarWidth = width }
            sidebarPane.isHidden = true
            split.adjustSubviews()
        } else {
            sidebarPane.isHidden = false
            split.adjustSubviews()
            split.setPosition(savedSidebarWidth, ofDividerAt: 0)
        }
        UserDefaults.standard.set(sidebarCollapsed, forKey: Self.sidebarCollapsedKey)
        updateSidebarToggleButton()
        layoutEditor()
    }

    private func updateSidebarToggleButton() {
        sidebarToggleButton?.toolTip = sidebarCollapsed ? "Show sidebar (⌃⌘S)" : "Hide sidebar (⌃⌘S)"
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
        let draft = WritingDraft()
        drafts.insert(draft, at: 0)
        currentDraft = draft
        tableView.reloadData()
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
        tableView.reloadData()
        if drafts.isEmpty { newDraft() } else { selectRow(0); loadDraft(drafts[0]) }
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
            items.append([
                "from": range.location, "to": NSMaxRange(range),
                "style": style, "accent": cssColor(accent, opaque: true),
                "title": title, "hint": hint,
            ])
        }
        guard let data = try? JSONSerialization.data(withJSONObject: items),
              let json = String(data: data, encoding: .utf8) else { return }
        webView.evaluateJavaScript("window.editorSetDecorations(\(json))")
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

    private func handleChange(markdown: String, text: String) {
        currentDraft?.body = markdown
        currentDraft?.updatedAt = Date()
        if let draft = currentDraft, let index = drafts.firstIndex(where: { $0.id == draft.id }) {
            drafts[index] = draft
            refreshRowTitle(index)
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
        editorReady = false
        if let url = Bundle.main.url(forResource: "index", withExtension: "html", subdirectory: "editor") {
            webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        }
    }

    private func jsString(_ string: String) -> String {
        (try? String(data: JSONEncoder().encode(string), encoding: .utf8)) ?? "\"\""
    }

    // MARK: - Table

    private func selectRow(_ row: Int) {
        guard row >= 0, row < drafts.count else { return }
        tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
    }

    private func refreshRowTitle(_ row: Int) {
        guard row >= 0, row < drafts.count,
              let cell = tableView.view(atColumn: 0, row: row, makeIfNecessary: false) as? DraftCellView else { return }
        let draft = drafts[row]
        cell.configure(
            title: draft.displayTitle,
            subtitle: draft.isEmpty ? "New draft" : relativeDate.localizedString(for: draft.updatedAt, relativeTo: Date()),
            titleColor: theme.primaryText,
            subtitleColor: theme.readableTertiaryText
        )
    }

    func numberOfRows(in tableView: NSTableView) -> Int { drafts.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard row < drafts.count else { return nil }
        let draft = drafts[row]
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
        guard row >= 0, row < drafts.count, drafts[row].id != currentDraft?.id else { return }
        flushCurrent()
        loadDraft(drafts[row])
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
