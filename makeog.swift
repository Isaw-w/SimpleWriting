import AppKit

// Renders docs/og-image.png (1200x630) — the social/share card: warm paper,
// the quill mark, the name, and the one-line philosophy.
let W: CGFloat = 1200, H: CGFloat = 630
let image = NSImage(size: NSSize(width: W, height: H))
image.lockFocus()

// Paper background (cool light).
NSColor(calibratedRed: 0.961, green: 0.973, blue: 0.988, alpha: 1).setFill()
NSRect(x: 0, y: 0, width: W, height: H).fill()

// Blue rule down the left.
NSColor(calibratedRed: 0.184, green: 0.435, blue: 0.69, alpha: 1).setFill()
NSRect(x: 0, y: 0, width: 14, height: H).fill()

let ink = NSColor(calibratedRed: 0.102, green: 0.141, blue: 0.196, alpha: 1)
let terra = NSColor(calibratedRed: 0.184, green: 0.435, blue: 0.69, alpha: 1)

func draw(_ s: String, _ font: NSFont, _ color: NSColor, x: CGFloat, y: CGFloat) {
    NSAttributedString(string: s, attributes: [.font: font, .foregroundColor: color])
        .draw(at: NSPoint(x: x, y: y))
}

let serif = { (size: CGFloat) in NSFont(name: "Georgia-Bold", size: size) ?? NSFont.boldSystemFont(ofSize: size) }
let body  = { (size: CGFloat) in NSFont(name: "Georgia", size: size) ?? NSFont.systemFont(ofSize: size) }

draw("SimpleWriting", serif(88), ink, x: 90, y: 380)
draw("Write it yourself.", body(46), terra, x: 92, y: 300)
draw("A minimalist macOS writing app that never writes for you.", body(34), ink, x: 92, y: 210)
draw("No AI ghostwriter. Just your words — and a grammar check that", body(27), ink.withAlphaComponent(0.7), x: 92, y: 150)
draw("names the rule and lets you make the fix.", body(27), ink.withAlphaComponent(0.7), x: 92, y: 112)

// A simple quill mark, top-right.
let cx: CGFloat = 1010, cy: CGFloat = 420, s: CGFloat = 150
func p(_ ax: CGFloat, _ ay: CGFloat) -> NSPoint { NSPoint(x: cx + ax * s, y: cy + ay * s) }
let feather = NSBezierPath()
feather.move(to: p(0.5, 0.5))
feather.curve(to: p(-0.35, -0.35), controlPoint1: p(0.05, 0.55), controlPoint2: p(-0.35, 0.05))
feather.curve(to: p(0.5, 0.5), controlPoint1: p(0.02, -0.05), controlPoint2: p(0.35, 0.05))
feather.close()
terra.setFill(); feather.fill()
let spine = NSBezierPath(); spine.move(to: p(0.46, 0.46)); spine.line(to: p(-0.42, -0.42))
spine.lineWidth = 6; spine.lineCapStyle = .round
NSColor(calibratedRed: 0.98, green: 0.96, blue: 0.91, alpha: 0.9).setStroke(); spine.stroke()

image.unlockFocus()
let rep = NSBitmapImageRep(data: image.tiffRepresentation!)!
let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "docs/og-image.png"
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
print("wrote \(out)")
