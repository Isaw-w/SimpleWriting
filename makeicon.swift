import AppKit

// Renders the SimpleWriting icon: a warm terracotta squircle with a cream quill
// pen drawn across it, matching the editor's paper/terracotta palette.
func renderIcon(size: CGFloat) -> Data {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()

    let margin = size * 0.085
    let rect = NSRect(x: margin, y: margin, width: size - margin * 2, height: size - margin * 2)
    let radius = rect.width * 0.2237 // Apple squircle-ish corner
    let squircle = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)

    NSGraphicsContext.saveGraphicsState()
    squircle.addClip()
    let top = NSColor(calibratedRed: 0.82, green: 0.44, blue: 0.25, alpha: 1)
    let bottom = NSColor(calibratedRed: 0.62, green: 0.27, blue: 0.11, alpha: 1)
    NSGradient(starting: top, ending: bottom)?.draw(in: rect, angle: -90)

    // Soft top highlight for a little depth.
    let highlight = NSGradient(
        colors: [NSColor(white: 1, alpha: 0.14), NSColor(white: 1, alpha: 0)]
    )
    highlight?.draw(in: NSRect(x: rect.minX, y: rect.midY, width: rect.width, height: rect.height / 2), angle: -90)

    // A quill drawn in the icon's own coordinate space (0…1 across `rect`), from
    // the feather at top-right down to the writing nib at bottom-left.
    let cream = NSColor(calibratedRed: 0.98, green: 0.96, blue: 0.91, alpha: 1)
    func p(_ x: CGFloat, _ y: CGFloat) -> NSPoint {
        NSPoint(x: rect.minX + x * rect.width, y: rect.minY + y * rect.height)
    }

    // Feather: a leaf-shaped blade along the shaft's top end.
    let feather = NSBezierPath()
    feather.move(to: p(0.80, 0.82))            // tip, top-right
    feather.curve(to: p(0.40, 0.44),           // down the outer (left) edge to the nib area
                  controlPoint1: p(0.55, 0.86),
                  controlPoint2: p(0.40, 0.66))
    feather.curve(to: p(0.80, 0.82),           // back up the inner (right) edge to the tip
                  controlPoint1: p(0.62, 0.58),
                  controlPoint2: p(0.78, 0.66))
    feather.close()
    cream.setFill()
    feather.fill()

    // Nib: a small triangle continuing the shaft to the writing point.
    let nib = NSBezierPath()
    nib.move(to: p(0.44, 0.48))
    nib.line(to: p(0.30, 0.30))                // the point that touches the "paper"
    nib.line(to: p(0.50, 0.42))
    nib.close()
    nib.fill()

    // Central spine of the feather, drawn back over the blade.
    let spine = NSBezierPath()
    spine.move(to: p(0.78, 0.80))
    spine.line(to: p(0.34, 0.34))
    spine.lineWidth = size * 0.022
    spine.lineCapStyle = .round
    let terracotta = NSColor(calibratedRed: 0.62, green: 0.27, blue: 0.11, alpha: 0.85)
    terracotta.setStroke()
    spine.stroke()

    NSGraphicsContext.restoreGraphicsState()

    image.unlockFocus()
    let rep = NSBitmapImageRep(data: image.tiffRepresentation!)!
    return rep.representation(using: .png, properties: [:])!
}

let iconsetPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "writer/AppIcon.iconset"
try? FileManager.default.createDirectory(atPath: iconsetPath, withIntermediateDirectories: true)

let sizes: [(String, CGFloat)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]
for (name, size) in sizes {
    try! renderIcon(size: size).write(to: URL(fileURLWithPath: "\(iconsetPath)/\(name).png"))
}
print("wrote \(sizes.count) sizes to \(iconsetPath)")
