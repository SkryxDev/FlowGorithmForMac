// FlowGorithmForMac · Copyright © 2026 SkryxDev
// GNU GPL v3 with additional attribution terms: see LICENSE and NOTICE.

import FlowCore
import SwiftUI

nonisolated enum NodeHighlight: Equatable {
    case none, selected, executing, error, changed
    /// A proposal on the chart: the old version of a shape, and the new one.
    case ghost, proposed
}

/// One flowchart shape: outline, fill, detail lines and its label.
struct ShapeView: View {
    let node: ChartNode
    let theme: Theme
    let fontSize: CGFloat
    let scale: CGFloat
    var highlight: NodeHighlight = .none

    var palette: ShapePalette {
        node.incomplete ? theme.incomplete : theme.palette(for: node.category)
    }

    var body: some View {
        let outline = NodeOutline(shape: node.shape)
        let width = theme.lineWidth * scale
        let palette = palette
        let glow = theme.id == "neon"
        ZStack {
            outline
                .fill(palette.fillStyle)
                // Shadows only where the theme has them: even a clear shadow costs a blur pass.
                .modifier(ShapeShadow(color: palette.stroke, enabled: theme.shadow && !glow, glow: false, scale: scale))
            outline
                .stroke(palette.stroke, style: StrokeStyle(lineWidth: width, lineJoin: .round,
                                                           dash: node.shape == .comment ? [4 * scale, 3 * scale] : []))
                // Neon's fills are almost transparent, so its glow comes from the outline.
                .modifier(ShapeShadow(color: palette.stroke, enabled: glow, glow: true, scale: scale))
            NodeDetail(shape: node.shape)
                .stroke(palette.stroke, lineWidth: width * 0.8)
            if node.shape != .breakpoint {
                Text(node.label)
                    .font(.system(size: fontSize, weight: .medium))
                    .foregroundStyle(palette.text)
                    .multilineTextAlignment(.center)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(textInsets(for: node.shape, height: node.frame.height))
                    .padding(.horizontal, 6 * scale)
            }
        }
        .frame(width: node.frame.width, height: node.frame.height)
        .overlay(alignment: .leading) {
            if node.shape == .breakpoint {
                Text(node.label)
                    .font(.system(size: fontSize, weight: .medium))
                    .foregroundStyle(theme.label)
                    .fixedSize()
                    .offset(x: node.frame.width + 8 * scale)
            }
        }
        .overlay { highlightRing(outline) }
        .contentShape(outline)
    }

    @ViewBuilder
    func highlightRing(_ outline: NodeOutline) -> some View {
        switch highlight {
        case .none:
            EmptyView()
        case .selected:
            outline
                .stroke(Color.accentColor, lineWidth: 2.5 * scale)
                .padding(-3 * scale)
        case .executing:
            ExecutingRing(outline: outline, scale: scale)
        case .error:
            outline
                .stroke(Color.red, lineWidth: 3 * scale)
                .padding(-3 * scale)
                .shadow(color: .red.opacity(0.6), radius: 6 * scale)
        case .changed:
            ChangedRing(outline: outline, scale: scale)
        case .ghost:
            EmptyView()
        case .proposed:
            ExecutingRing(outline: outline, scale: scale, color: AIMode.study.color, glow: AIMode.study.color)
        }
    }
}

/// A purple glow around a shape the assistant just added or changed, which fades in and out.
struct ChangedRing: View {
    let outline: NodeOutline
    let scale: CGFloat
    @State private var shown = false

    var body: some View {
        ZStack {
            outline
                .fill(Color.purple.opacity(0.14))
            outline
                .stroke(Color.purple, lineWidth: 3 * scale)
                .padding(-4 * scale)
                .shadow(color: .purple.opacity(0.8), radius: 8 * scale)
        }
        .opacity(shown ? 1 : 0)
        .scaleEffect(shown ? 1 : 1.08)
        .onAppear { withAnimation(.snappy(duration: 0.35)) { shown = true } }
        .allowsHitTesting(false)
    }
}

/// The soft drop shadow of the Modern theme, or the glow of Neon. Applied only when enabled.
struct ShapeShadow: ViewModifier {
    let color: Color
    let enabled: Bool
    let glow: Bool
    let scale: CGFloat

    func body(content: Content) -> some View {
        if enabled {
            content.shadow(color: color.opacity(glow ? 0.7 : 0.25), radius: (glow ? 6 : 3) * scale, y: glow ? 0 : 1.5 * scale)
        } else {
            content
        }
    }
}

/// A softly pulsing ring around the shape that is running.
///
/// Driven by a 30 fps timeline instead of an animation at the display's full refresh rate:
/// the pulse looks the same, and the blur is recomputed a quarter as often on 120 Hz screens.
struct ExecutingRing: View {
    let outline: NodeOutline
    let scale: CGFloat
    var color: Color = .yellow
    var glow: Color = .orange

    /// One full bright-dim cycle, matching the previous 0.6 s ease-in-out each way.
    static let period = 1.2

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            let bright = (1 - cos(2 * .pi * t / Self.period)) / 2
            ZStack {
                outline
                    .fill(color.opacity(0.12 + 0.16 * bright))
                outline
                    .stroke(color, lineWidth: (3 + 1.5 * bright) * scale)
                    .padding(-5 * scale)
                    .shadow(color: glow.opacity(0.5 + 0.5 * bright), radius: (6 + 8 * bright) * scale)
            }
            .scaleEffect(1 + 0.04 * bright)
        }
    }
}

/// Connectors, merge dots and branch labels, drawn in one Canvas.
struct ChartLines: View {
    let layout: ChartLayout
    let theme: Theme
    let fontSize: CGFloat
    let scale: CGFloat

    var body: some View {
        Canvas { context, _ in
            let width = theme.lineWidth * scale
            let arrowLength = 8 * scale
            let arrowWidth = 4.5 * scale
            // Everything with the same style goes into one path: a few draw calls instead of hundreds.
            var lines = Path()
            var heads = Path()
            var dashed = Path()
            for edge in layout.edges {
                guard edge.points.count >= 2 else { continue }
                if edge.arrow {
                    let end = edge.points[edge.points.count - 1]
                    let before = edge.points[edge.points.count - 2]
                    let angle = atan2(end.y - before.y, end.x - before.x)
                    let base = CGPoint(x: end.x - cos(angle) * arrowLength, y: end.y - sin(angle) * arrowLength)
                    // Stop the line at the arrow's base so the tip stays sharp.
                    lines.move(to: edge.points[0])
                    for point in edge.points.dropFirst().dropLast() { lines.addLine(to: point) }
                    lines.addLine(to: base)
                    heads.move(to: end)
                    heads.addLine(to: CGPoint(x: base.x + sin(angle) * arrowWidth, y: base.y - cos(angle) * arrowWidth))
                    heads.addLine(to: CGPoint(x: base.x - sin(angle) * arrowWidth, y: base.y + cos(angle) * arrowWidth))
                    heads.closeSubpath()
                } else if edge.dashed {
                    dashed.move(to: edge.points[0])
                    for point in edge.points.dropFirst() { dashed.addLine(to: point) }
                } else {
                    lines.move(to: edge.points[0])
                    for point in edge.points.dropFirst() { lines.addLine(to: point) }
                }
            }
            context.stroke(lines, with: .color(theme.line), style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round))
            context.fill(heads, with: .color(theme.line))
            if !dashed.isEmpty {
                context.stroke(dashed, with: .color(theme.label), style: StrokeStyle(lineWidth: width, dash: [3 * scale, 3 * scale]))
            }

            let radius = 5 * scale
            var dots = Path()
            for dot in layout.dots {
                dots.addEllipse(in: CGRect(x: dot.x - radius, y: dot.y - radius, width: radius * 2, height: radius * 2))
            }
            context.fill(dots, with: .color(theme.canvas))
            context.stroke(dots, with: .color(theme.line), lineWidth: width)

            // Only a handful of distinct labels (True, False, Next, Done): resolve each once.
            var resolved: [String: GraphicsContext.ResolvedText] = [:]
            for text in layout.texts {
                let label = resolved[text.text] ?? context.resolve(
                    Text(text.text).font(.system(size: fontSize * 0.85, weight: .medium)).foregroundStyle(theme.label))
                resolved[text.text] = label
                context.draw(label, at: text.position, anchor: text.anchor)
            }
        }
        .allowsHitTesting(false)
    }
}

/// A light dot grid behind the chart.
struct ChartGrid: View {
    let theme: Theme
    let scale: CGFloat

    var body: some View {
        Canvas { context, size in
            let spacing = max(12, 22 * scale)
            let radius = max(0.6, 1 * scale)
            // One tile with a single dot, repeated by the GPU: much cheaper than thousands of
            // separate circles, which had to be redrawn on every scroll.
            let color = Color(theme.grid.resolve(in: context.environment))
            let tile = Image(size: CGSize(width: spacing, height: spacing)) { tile in
                tile.fill(Path(ellipseIn: CGRect(x: spacing / 2 - radius, y: spacing / 2 - radius,
                                                 width: radius * 2, height: radius * 2)), with: .color(color))
            }
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .tiledImage(tile))
        }
        .allowsHitTesting(false)
    }
}

// Equality lets SwiftUI skip redrawing shapes, lines and the grid when nothing they show changed,
// which matters while a program runs and only the highlighted shape moves.

extension ShapeView: Equatable {
    nonisolated static func == (a: ShapeView, b: ShapeView) -> Bool {
        a.node.id == b.node.id && a.node.label == b.node.label && a.node.frame == b.node.frame
            && a.node.problem == b.node.problem
            && a.node.incomplete == b.node.incomplete && a.node.shape == b.node.shape
            && a.node.category == b.node.category && a.theme.id == b.theme.id
            && a.fontSize == b.fontSize && a.scale == b.scale && a.highlight == b.highlight
    }
}

extension ChartLines: Equatable {
    nonisolated static func == (a: ChartLines, b: ChartLines) -> Bool {
        a.layout.revision == b.layout.revision && a.theme.id == b.theme.id
            && a.fontSize == b.fontSize && a.scale == b.scale
    }
}

extension ChartGrid: Equatable {
    nonisolated static func == (a: ChartGrid, b: ChartGrid) -> Bool {
        a.theme.id == b.theme.id && a.scale == b.scale
    }
}
