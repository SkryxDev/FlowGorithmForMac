// Draws the white flowchart glyph used as the layer of AppIcon.icon.
// Usage: swift Scripts/make-icon-glyph.swift <output-folder>
import AppKit

let size = 1024.0
let output = URL(fileURLWithPath: CommandLine.arguments[1])

func render(_ name: String, _ draw: (CGContext) -> Void) {
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    let context = CGContext(data: nil, width: Int(size), height: Int(size), bitsPerComponent: 8, bytesPerRow: 0,
                            space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    // Flip so y grows downward, like the chart itself.
    context.translateBy(x: 0, y: size)
    context.scaleBy(x: 1, y: -1)
    context.setFillColor(.white)
    context.setStrokeColor(.white)
    draw(context)
    let image = NSBitmapImageRep(cgImage: context.makeImage()!)
    try! image.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent(name))
}

let cx = size / 2
let line = 26.0

// Shapes: start capsule, decision diamond, two branch boxes, end capsule.
render("shapes.png") { c in
    c.addPath(CGPath(roundedRect: CGRect(x: cx - 120, y: 150, width: 240, height: 96), cornerWidth: 48, cornerHeight: 48, transform: nil))
    c.move(to: CGPoint(x: cx, y: 330)); c.addLine(to: CGPoint(x: cx + 150, y: 430))
    c.addLine(to: CGPoint(x: cx, y: 530)); c.addLine(to: CGPoint(x: cx - 150, y: 430)); c.closePath()
    // Left: a parallelogram (input). Right: a rounded box (assign).
    c.move(to: CGPoint(x: 168, y: 590)); c.addLine(to: CGPoint(x: 368, y: 590))
    c.addLine(to: CGPoint(x: 336, y: 680)); c.addLine(to: CGPoint(x: 136, y: 680)); c.closePath()
    c.addPath(CGPath(roundedRect: CGRect(x: size - 368, y: 590, width: 210, height: 90), cornerWidth: 14, cornerHeight: 14, transform: nil))
    c.addPath(CGPath(roundedRect: CGRect(x: cx - 120, y: 790, width: 240, height: 96), cornerWidth: 48, cornerHeight: 48, transform: nil))
    c.fillPath()
}

// Connectors.
render("lines.png") { c in
    c.setLineWidth(line)
    c.setLineCap(.round)
    c.setLineJoin(.round)
    c.move(to: CGPoint(x: cx, y: 246)); c.addLine(to: CGPoint(x: cx, y: 320))
    c.move(to: CGPoint(x: cx - 150, y: 430)); c.addLine(to: CGPoint(x: 252, y: 430)); c.addLine(to: CGPoint(x: 252, y: 585))
    c.move(to: CGPoint(x: cx + 150, y: 430)); c.addLine(to: CGPoint(x: size - 263, y: 430)); c.addLine(to: CGPoint(x: size - 263, y: 585))
    c.move(to: CGPoint(x: 252, y: 680)); c.addLine(to: CGPoint(x: 252, y: 735)); c.addLine(to: CGPoint(x: size - 263, y: 735))
    c.addLine(to: CGPoint(x: size - 263, y: 680))
    c.move(to: CGPoint(x: cx, y: 735)); c.addLine(to: CGPoint(x: cx, y: 785))
    c.strokePath()
}
