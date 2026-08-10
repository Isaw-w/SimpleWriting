import AppKit
import WebKit

/// The Math Playground — a separate window with a MathLive + Compute Engine
/// notebook (see Resources/math). It bridges to the page for save/load, keeping
/// the notebook in one JSON file so it persists between launches.
final class MathWindowController: NSWindowController, WKScriptMessageHandler, WKNavigationDelegate {
    static let shared = MathWindowController()

    private var webView: WKWebView!
    private var saveWork: DispatchWorkItem?

    private var storeURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let dir = base.appendingPathComponent("SimpleWriting", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("math-playground.json")
    }

    private init() { super.init(window: nil) }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func show() {
        if window == nil { build() }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    private func build() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 760, height: 640),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered, defer: false
        )
        window.title = "Math Playground"
        window.minSize = NSSize(width: 480, height: 360)
        window.center()
        window.isReleasedWhenClosed = false
        window.appearance = NSAppearance(named: Theme.current.appearanceName)
        self.window = window

        let config = WKWebViewConfiguration()
        config.userContentController.add(self, name: "math")
        let web = WKWebView(frame: window.contentView!.bounds, configuration: config)
        web.autoresizingMask = [.width, .height]
        web.navigationDelegate = self
        web.underPageBackgroundColor = Theme.current.isDark
            ? NSColor(calibratedWhite: 0.09, alpha: 1) : NSColor(calibratedWhite: 0.985, alpha: 1)
        window.contentView = web
        self.webView = web

        if let url = Bundle.main.url(forResource: "math", withExtension: "html", subdirectory: "math") {
            web.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        } else {
            NSLog("SimpleWriting: math playground bundle missing from Resources/math")
        }
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any], let type = body["type"] as? String else { return }
        switch type {
        case "ready":
            webView.evaluateJavaScript("window.mathSetTheme(\(Theme.current.isDark ? "true" : "false"))")
            let json = (try? String(contentsOf: storeURL, encoding: .utf8)) ?? "[]"
            webView.evaluateJavaScript("window.mathLoad(\(jsString(json)))")
        case "change":
            if let blocks = body["blocks"] { scheduleSave(blocks) }
        default:
            break
        }
    }

    private func scheduleSave(_ blocks: Any) {
        saveWork?.cancel()
        let url = storeURL
        let data = try? JSONSerialization.data(withJSONObject: blocks, options: [.prettyPrinted])
        let work = DispatchWorkItem { if let data { try? data.write(to: url, options: .atomic) } }
        saveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
    }

    private func jsString(_ string: String) -> String {
        (try? String(data: JSONEncoder().encode(string), encoding: .utf8)) ?? "\"\""
    }
}
