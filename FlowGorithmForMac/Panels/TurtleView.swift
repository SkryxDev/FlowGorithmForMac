import FlowCore
import SwiftUI

/// The turtle graphics canvas. The origin is the center; y grows upward, as in LOGO.
struct TurtleView: View {
    var session: RunSession
    @State private var zoom: CGFloat = 1
    @State private var darkBackground = false

    var body: some View {
        let zoom = zoom
        let segments = session.segments
        let turtlePosition = session.turtlePosition
        let turtleHeading = session.turtleHeading
        let darkBackground = darkBackground
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

                for segment in segments {
                    var path = Path()
                    path.move(to: map(segment.from))
                    path.addLine(to: map(segment.to))
                    let color = segment.color == .black && darkBackground ? Color.white : segment.color.color
                    context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: 2, lineCap: .round))
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
            .gesture(MagnifyGesture().onChanged { self.zoom = min(8, max(0.2, $0.magnification)) })

            HStack(spacing: 4) {
                Button("Zoom Out", systemImage: "minus.magnifyingglass") { self.zoom = max(0.2, zoom / 1.25) }
                Button("Zoom In", systemImage: "plus.magnifyingglass") { self.zoom = min(8, zoom * 1.25) }
                Button("Background", systemImage: darkBackground ? "sun.max" : "moon") { self.darkBackground.toggle() }
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.glass)
            .padding(10)
        }
    }
}
