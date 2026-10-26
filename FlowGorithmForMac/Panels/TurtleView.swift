// FlowGorithmForMac · Copyright © 2026 SkryxDev
// GNU GPL v3 with additional attribution terms: see LICENSE and NOTICE.

import FlowCore
import SwiftUI

/// The turtle graphics canvas. The origin is the center; y grows upward, as in LOGO.
struct TurtleView: View {
    var session: RunSession
    @State private var zoom: CGFloat = 1
    @State private var darkBackground = false
    @State private var pinchStart: CGFloat?
    @State private var panelSize = CGSize(width: 300, height: 300)

    @Environment(\.displayScale) private var displayScale
    @State private var raster = TurtleRaster()

    var body: some View {
        let zoom = zoom
        let segments = session.segments
        let generation = session.turtleGeneration
        let turtlePosition = session.turtlePosition
        let turtleHeading = session.turtleHeading
        let darkBackground = darkBackground
        let displayScale = displayScale
        let raster = raster
        ZStack(alignment: .bottomTrailing) {
            Canvas { context, size in
                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                func map(_ p: CGPoint) -> CGPoint { CGPoint(x: center.x + p.x * zoom, y: center.y - p.y * zoom) }

                // Axes, faintly.
                var axes = Path()
                axes.move(to: CGPoint(x: 0, y: center.y))
                axes.addLine(to: CGPoint(x: size.width, y: center.y))
                axes.move(to: CGPoint(x: center.x, y: 0))
                axes.addLine(to: CGPoint(x: center.x, y: size.height))
                context.stroke(axes, with: .color(.secondary.opacity(0.15)), lineWidth: 1)

                // The drawing is kept as a bitmap and only new lines are added to it, so a long
                // program doesn't redraw thousands of lines on every update.
                if let image = raster.image(for: segments, generation: generation, size: size, zoom: zoom,
                                            dark: darkBackground, scale: displayScale) {
                    context.draw(Image(decorative: image, scale: displayScale), in: CGRect(origin: .zero, size: size))
                }

                // The turtle: a small arrow pointing where it's heading.
                let position = map(turtlePosition)
                let angle = -turtleHeading * .pi / 180
                func rotated(_ x: Double, _ y: Double) -> CGPoint {
                    CGPoint(x: position.x + x * cos(angle) - y * sin(angle), y: position.y + x * sin(angle) + y * cos(angle))
                }
                var turtle = Path()
                turtle.move(to: rotated(12, 0))
                turtle.addLine(to: rotated(-8, 7))
                turtle.addLine(to: rotated(-4, 0))
                turtle.addLine(to: rotated(-8, -7))
                turtle.closeSubpath()
                context.fill(turtle, with: .color(.green))
                context.stroke(turtle, with: .color(.green.mix(with: .black, by: 0.4)), lineWidth: 1)
            }
            .background(darkBackground ? Color.black : Color.white)
            .onGeometryChange(for: CGSize.self) { $0.size } action: { panelSize = $0 }
            .gesture(
                MagnifyGesture()
                    .onChanged { value in
                        let start = pinchStart ?? self.zoom
                        pinchStart = start
                        self.zoom = min(8, max(0.05, start * value.magnification))
                    }
                    .onEnded { _ in pinchStart = nil }
            )

            HStack(spacing: 4) {
                Button("Fit Drawing", systemImage: "arrow.up.left.and.down.right.magnifyingglass") { fit() }
                    .disabled(segments.isEmpty)
                Button("Zoom Out", systemImage: "minus.magnifyingglass") { self.zoom = max(0.05, zoom / 1.25) }
                Button("Zoom In", systemImage: "plus.magnifyingglass") { self.zoom = min(8, zoom * 1.25) }
                Button("Background", systemImage: darkBackground ? "sun.max" : "moon") { self.darkBackground.toggle() }
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.glass)
            .padding(10)
        }
    }

    /// Zooms so the whole drawing, centered on the origin, fits the panel.
    func fit() {
        let extent = session.segments.reduce(1.0) { result, segment in
            max(result, abs(segment.from.x), abs(segment.from.y), abs(segment.to.x), abs(segment.to.y))
        }
        zoom = min(8, max(0.05, (min(panelSize.width, panelSize.height) / 2 - 16) / extent))
    }
}

/// The turtle's lines as a bitmap that grows with each update.
final class TurtleRaster {
    private struct Key: Equatable {
        var pixelWidth: Int
        var pixelHeight: Int
        var zoom: CGFloat
        var dark: Bool
        var generation: Int
    }

    private var context: CGContext?
    private var key: Key?
    private var drawn = 0
    private var image: CGImage?

    func image(for segments: [TurtleSegment], generation: Int, size: CGSize, zoom: CGFloat, dark: Bool, scale: CGFloat) -> CGImage? {
        guard !segments.isEmpty, size.width >= 1, size.height >= 1 else { return nil }
        let newKey = Key(pixelWidth: Int((size.width * scale).rounded(.up)), pixelHeight: Int((size.height * scale).rounded(.up)),
                         zoom: zoom, dark: dark, generation: generation)
        if newKey != key || drawn > segments.count {
            context = CGContext(data: nil, width: newKey.pixelWidth, height: newKey.pixelHeight, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            // Points, with y growing upward like the turtle's own coordinates.
            context?.scaleBy(x: scale, y: scale)
            context?.setLineWidth(2)
            context?.setLineCap(.round)
            context?.setLineJoin(.round)
            key = newKey
            drawn = 0
            image = nil
        }
        guard let context else { return nil }
        if drawn < segments.count {
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            func map(_ p: CGPoint) -> CGPoint { CGPoint(x: center.x + p.x * zoom, y: center.y + p.y * zoom) }
            var current: PenColor?
            for segment in segments[drawn...] {
                if segment.color != current {
                    if current != nil { context.strokePath() }
                    current = segment.color
                    let rgb = segment.color == .black && dark ? (red: 1.0, green: 1.0, blue: 1.0) : segment.color.rgb
                    context.setStrokeColor(CGColor(srgbRed: rgb.red, green: rgb.green, blue: rgb.blue, alpha: 1))
                }
                context.move(to: map(segment.from))
                context.addLine(to: map(segment.to))
            }
            context.strokePath()
            drawn = segments.count
            image = context.makeImage()
        }
        return image
    }
}
